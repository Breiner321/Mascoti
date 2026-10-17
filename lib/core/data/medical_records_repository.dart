import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/medical_record.dart';

/// Error al trabajar con el historial, con el mensaje para mostrar.
@immutable
class MedicalRecordFailure implements Exception {
  const MedicalRecordFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;

  static const network = MedicalRecordFailure(
    'No se pudo conectar. Verifica tu conexión',
    canRetry: true,
  );
  static const denied = MedicalRecordFailure('No tienes permiso para modificar este historial.');
  static const notConfigured =
      MedicalRecordFailure('Los adjuntos no están disponibles en esta versión de la app');

  @override
  String toString() => 'MedicalRecordFailure($message)';
}

/// Historial médico (RF-08), compartido por el plugin clinica (crea y
/// corrige registros) y el plugin mascotas (timeline del dueño).
///
/// - Registros: `pets/{petId}/medicalRecords/{recordId}` en Firestore.
/// - Próximas dosis: `vacunasProgramadas/{recordId}_{n}`, en el mismo lote.
/// - Adjuntos: bucket privado `registros` de Supabase, con enlaces firmados
///   de la Edge Function `adjuntos-historial`.
class MedicalRecordsRepository {
  MedicalRecordsRepository({
    FirebaseFirestore? firestore,
    FunctionsClient? functions,
    SupabaseStorageClient? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions,
        _storage = storage;

  final FirebaseFirestore _firestore;

  /// null = Supabase no está configurado (falta env/dev.json).
  final FunctionsClient? _functions;
  final SupabaseStorageClient? _storage;

  static const attachmentsBucket = 'registros';
  static const _timeout = Duration(seconds: 30);

  CollectionReference<Map<String, dynamic>> _records(String petId) =>
      _firestore.collection('pets').doc(petId).collection('medicalRecords');

  CollectionReference<Map<String, dynamic>> get _scheduled =>
      _firestore.collection('vacunasProgramadas');

  /// Timeline de la mascota, la consulta más reciente primero. Se actualiza
  /// sola cuando una clínica agrega un registro (RF-08, flujo alterno).
  Stream<List<MedicalRecord>> watchRecords(String petId) => _records(petId)
      .orderBy('fecha', descending: true)
      .snapshots()
      .map((snap) => [
            for (final d in snap.docs) MedicalRecord.fromMap(petId, d.id, d.data()),
          ]);

  /// Id para un registro nuevo (se necesita antes de subir adjuntos).
  String newRecordId(String petId) => _records(petId).doc().id;

  /// Próximas dosis de las mascotas del dueño (RF-13 / carnet).
  Stream<List<ScheduledVaccine>> watchScheduledVaccines(String ownerUid) => _scheduled
      .where('ownerUid', isEqualTo: ownerUid)
      .orderBy('fechaProximaDosis')
      .snapshots()
      .map((snap) => [for (final d in snap.docs) ScheduledVaccine.fromMap(d.id, d.data())]);

  /// La clínica (autorizada) crea el registro y, en el mismo lote, una
  /// próxima dosis por cada vacuna con refuerzo. [ownerUid] es el dueño de la
  /// mascota.
  Future<void> createRecord(MedicalRecord record, {required String ownerUid}) async {
    final batch = _firestore.batch()
      ..set(_records(record.petId).doc(record.id), {
        ...record.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    _writeScheduled(batch, record, ownerUid);
    await _commit(batch);
  }

  /// Corrige un registro (solo su clínica autora, dentro de 24 h) y ajusta
  /// sus próximas dosis: quita las de [previous] que ya no apliquen.
  Future<void> updateRecord(
    MedicalRecord record, {
    required MedicalRecord previous,
    required String ownerUid,
  }) async {
    final batch = _firestore.batch()
      ..update(_records(record.petId).doc(record.id), {
        ...record.toMap(),
        // Un campo opcional que se quitó debe borrarse del documento.
        if (record.appointmentId == null) 'appointmentId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    for (var i = 0; i < previous.vacunas.length; i++) {
      final stillScheduled =
          i < record.vacunas.length && record.vacunas[i].fechaProximaDosis != null;
      if (previous.vacunas[i].fechaProximaDosis != null && !stillScheduled) {
        batch.delete(_scheduled.doc(ScheduledVaccine.idFor(record.id, i)));
      }
    }
    _writeScheduled(batch, record, ownerUid);
    await _commit(batch);
  }

  void _writeScheduled(WriteBatch batch, MedicalRecord record, String ownerUid) {
    for (var i = 0; i < record.vacunas.length; i++) {
      final next = record.vacunas[i].fechaProximaDosis;
      if (next == null) continue;
      batch.set(_scheduled.doc(ScheduledVaccine.idFor(record.id, i)), {
        ...ScheduledVaccine(
          id: ScheduledVaccine.idFor(record.id, i),
          petId: record.petId,
          ownerUid: ownerUid,
          clinicId: record.clinicId,
          recordId: record.id,
          vacuna: record.vacunas[i].nombre,
          fechaProximaDosis: next,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _commit(WriteBatch batch) async {
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw MedicalRecordFailure.denied;
      if (e.code == 'unavailable') throw MedicalRecordFailure.network;
      rethrow;
    }
  }

  /// Sube un adjunto (JPG, PNG o PDF de máximo 10 MB) para el registro
  /// [recordId] y devuelve el adjunto para guardarlo en el registro.
  Future<RecordAttachment> uploadAttachment({
    required String petId,
    required String recordId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.length > MedicalRecordLimits.maxAdjuntoBytes) {
      throw const MedicalRecordFailure('El archivo supera el máximo de 10 MB.');
    }
    final data = await _invoke({
      'accion': 'subir',
      'petId': petId,
      'recordId': recordId,
      'nombreArchivo': fileName,
    });
    final path = data['path'] as String;
    final tipo = AttachmentType.fromValue(data['tipo']);
    final storage = _storage;
    if (storage == null) throw MedicalRecordFailure.notConfigured;
    try {
      await storage.from(attachmentsBucket).uploadBinaryToSignedUrl(
            path,
            data['token'] as String,
            bytes,
            FileOptions(contentType: _contentType(fileName)),
          );
    } on StorageException catch (e) {
      throw MedicalRecordFailure('No se pudo subir el archivo: ${e.message}', canRetry: true);
    } on SocketException {
      throw MedicalRecordFailure.network;
    }
    return RecordAttachment(path: path, tipo: tipo, nombre: fileName);
  }

  /// Enlace temporal (1 h) para ver o descargar un adjunto. Si falla, la UI
  /// muestra "Archivo no disponible" sin bloquear el resto (RF-08).
  Future<String> attachmentUrl({required String petId, required String path}) async {
    final data = await _invoke({'accion': 'leer', 'petId': petId, 'path': path});
    return data['url'] as String;
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final functions = _functions;
    if (functions == null) throw MedicalRecordFailure.notConfigured;
    try {
      final response =
          await functions.invoke('adjuntos-historial', body: body).timeout(_timeout);
      return Map<String, dynamic>.from(response.data as Map);
    } on TimeoutException {
      throw MedicalRecordFailure.network;
    } on SocketException {
      throw MedicalRecordFailure.network;
    } on http.ClientException {
      throw MedicalRecordFailure.network;
    } on FunctionException catch (e) {
      final error = e.details is Map ? (e.details as Map)['error'] : null;
      final message = error is Map ? error['message'] as String? : null;
      throw MedicalRecordFailure(
        message ?? 'No se pudo procesar el archivo. Intenta de nuevo.',
        canRetry: e.status >= 500,
      );
    }
  }

  static String _contentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      _ => 'image/jpeg',
    };
  }
}
