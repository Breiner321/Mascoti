import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Límites de `pets/{petId}/medicalRecords` (iguales a firestore.rules).
abstract final class MedicalRecordLimits {
  static const maxDiagnostico = 2000;
  static const maxTratamiento = 2000;
  static const maxVacunas = 10;
  static const maxAdjuntos = 10;
  static const maxVacunaNombre = 80;
  static const maxLote = 40;
  static const maxAdjuntoNombre = 120;

  /// Archivos de máximo 10 MB (bucket `registros` de Supabase).
  static const maxAdjuntoBytes = 10 * 1024 * 1024;

  /// La clínica autora puede corregir el registro durante 24 horas.
  static const editWindow = Duration(hours: 24);
}

/// Vacuna aplicada en una consulta (RF-08).
@immutable
class Vaccine {
  const Vaccine({
    required this.nombre,
    required this.lote,
    required this.fechaAplicacion,
    this.fechaProximaDosis,
  });

  factory Vaccine.fromMap(Map<String, dynamic> map) => Vaccine(
        nombre: map['nombre'] as String? ?? '',
        lote: map['lote'] as String? ?? '',
        fechaAplicacion: (map['fechaAplicacion'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        fechaProximaDosis: (map['fechaProximaDosis'] as Timestamp?)?.toDate(),
      );

  final String nombre;
  final String lote;
  final DateTime fechaAplicacion;

  /// Si tiene refuerzo, se crea un recordatorio en `vacunasProgramadas` (RF-13).
  final DateTime? fechaProximaDosis;

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'lote': lote,
        'fechaAplicacion': Timestamp.fromDate(fechaAplicacion),
        if (fechaProximaDosis != null)
          'fechaProximaDosis': Timestamp.fromDate(fechaProximaDosis!),
      };

  @override
  bool operator ==(Object other) =>
      other is Vaccine &&
      other.nombre == nombre &&
      other.lote == lote &&
      other.fechaAplicacion == fechaAplicacion &&
      other.fechaProximaDosis == fechaProximaDosis;

  @override
  int get hashCode => Object.hash(nombre, lote, fechaAplicacion, fechaProximaDosis);
}

enum AttachmentType {
  imagen('imagen'),
  pdf('pdf');

  const AttachmentType(this.value);

  final String value;

  static AttachmentType fromValue(Object? value) => value == 'pdf' ? pdf : imagen;
}

/// Archivo adjunto (radiografía, examen…) en el bucket privado `registros`
/// de Supabase. Se guarda la ruta; para verlo se pide un enlace firmado con
/// MedicalRecordsRepository.attachmentUrl (solo dueño y clínicas autorizadas).
@immutable
class RecordAttachment {
  const RecordAttachment({required this.path, required this.tipo, required this.nombre});

  factory RecordAttachment.fromMap(Map<String, dynamic> map) => RecordAttachment(
        path: map['path'] as String? ?? '',
        tipo: AttachmentType.fromValue(map['tipo']),
        nombre: map['nombre'] as String? ?? '',
      );

  /// `{petId}/{recordId}/{archivo}`.
  final String path;
  final AttachmentType tipo;

  /// Nombre original del archivo, para mostrarlo.
  final String nombre;

  Map<String, dynamic> toMap() => {'path': path, 'tipo': tipo.value, 'nombre': nombre};

  @override
  bool operator ==(Object other) =>
      other is RecordAttachment &&
      other.path == path &&
      other.tipo == tipo &&
      other.nombre == nombre;

  @override
  int get hashCode => Object.hash(path, tipo, nombre);
}

/// Documento `pets/{petId}/medicalRecords/{recordId}` (RF-08). Lo crea una
/// clínica autorizada; el dueño y las clínicas autorizadas lo leen; la
/// clínica autora lo puede corregir 24 h; nunca se borra.
@immutable
class MedicalRecord {
  const MedicalRecord({
    required this.id,
    required this.petId,
    required this.clinicId,
    required this.fecha,
    required this.diagnostico,
    this.clinicNombre = '',
    this.appointmentId,
    this.tratamiento = '',
    this.vacunas = const [],
    this.adjuntos = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory MedicalRecord.fromMap(String petId, String id, Map<String, dynamic> map) =>
      MedicalRecord(
        id: id,
        petId: petId,
        clinicId: map['clinicId'] as String? ?? '',
        clinicNombre: map['clinicNombre'] as String? ?? '',
        appointmentId: map['appointmentId'] as String?,
        fecha: (map['fecha'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        diagnostico: map['diagnostico'] as String? ?? '',
        tratamiento: map['tratamiento'] as String? ?? '',
        vacunas: _list(map['vacunas'], Vaccine.fromMap),
        adjuntos: _list(map['adjuntos'], RecordAttachment.fromMap),
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      );

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) fromMap) =>
      raw is List
          ? [
              for (final item in raw)
                if (item is Map) fromMap(Map<String, dynamic>.from(item)),
            ]
          : const [];

  final String id;
  final String petId;
  final String clinicId;
  final String clinicNombre;
  final String? appointmentId;

  /// Fecha de la consulta.
  final DateTime fecha;
  final String diagnostico;
  final String tratamiento;
  final List<Vaccine> vacunas;
  final List<RecordAttachment> adjuntos;

  /// Hora del servidor al crearlo (marca el inicio de las 24 h de edición).
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// La clínica autora aún puede corregirlo (`now` < createdAt + 24 h).
  bool isEditable(DateTime now) {
    final created = createdAt;
    return created != null && now.isBefore(created.add(MedicalRecordLimits.editWindow));
  }

  /// Datos del documento sin `createdAt`/`updatedAt` (los pone el
  /// repositorio con la hora del servidor).
  Map<String, dynamic> toMap() => {
        'clinicId': clinicId,
        'clinicNombre': clinicNombre,
        if (appointmentId != null) 'appointmentId': appointmentId,
        'fecha': Timestamp.fromDate(fecha),
        'diagnostico': diagnostico,
        'tratamiento': tratamiento,
        'vacunas': [for (final v in vacunas) v.toMap()],
        'adjuntos': [for (final a in adjuntos) a.toMap()],
      };

  MedicalRecord copyWith({
    DateTime? fecha,
    String? diagnostico,
    String? tratamiento,
    List<Vaccine>? vacunas,
    List<RecordAttachment>? adjuntos,
  }) =>
      MedicalRecord(
        id: id,
        petId: petId,
        clinicId: clinicId,
        clinicNombre: clinicNombre,
        appointmentId: appointmentId,
        fecha: fecha ?? this.fecha,
        diagnostico: diagnostico ?? this.diagnostico,
        tratamiento: tratamiento ?? this.tratamiento,
        vacunas: vacunas ?? this.vacunas,
        adjuntos: adjuntos ?? this.adjuntos,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is MedicalRecord &&
      other.id == id &&
      other.petId == petId &&
      other.clinicId == clinicId &&
      other.clinicNombre == clinicNombre &&
      other.appointmentId == appointmentId &&
      other.fecha == fecha &&
      other.diagnostico == diagnostico &&
      other.tratamiento == tratamiento &&
      listEquals(other.vacunas, vacunas) &&
      listEquals(other.adjuntos, adjuntos) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        petId,
        clinicId,
        clinicNombre,
        appointmentId,
        fecha,
        diagnostico,
        tratamiento,
        Object.hashAll(vacunas),
        Object.hashAll(adjuntos),
        createdAt,
        updatedAt,
      );
}

/// Documento `vacunasProgramadas/{recordId}_{n}`: una próxima dosis por
/// vacuna con refuerzo. Lo crea la clínica en el mismo lote que el registro
/// y lo consulta RF-13 (recordatorios), porque Firestore no puede buscar por
/// fechas dentro de una lista de objetos.
@immutable
class ScheduledVaccine {
  const ScheduledVaccine({
    required this.id,
    required this.petId,
    required this.ownerUid,
    required this.clinicId,
    required this.recordId,
    required this.vacuna,
    required this.fechaProximaDosis,
    this.notificado = false,
  });

  factory ScheduledVaccine.fromMap(String id, Map<String, dynamic> map) => ScheduledVaccine(
        id: id,
        petId: map['petId'] as String? ?? '',
        ownerUid: map['ownerUid'] as String? ?? '',
        clinicId: map['clinicId'] as String? ?? '',
        recordId: map['recordId'] as String? ?? '',
        vacuna: map['vacuna'] as String? ?? '',
        fechaProximaDosis: (map['fechaProximaDosis'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        notificado: map['notificado'] == true,
      );

  static String idFor(String recordId, int index) => '${recordId}_$index';

  final String id;
  final String petId;
  final String ownerUid;
  final String clinicId;
  final String recordId;
  final String vacuna;
  final DateTime fechaProximaDosis;

  /// Lo marca RF-13 al enviar el recordatorio.
  final bool notificado;

  Map<String, dynamic> toMap() => {
        'petId': petId,
        'ownerUid': ownerUid,
        'clinicId': clinicId,
        'recordId': recordId,
        'vacuna': vacuna,
        'fechaProximaDosis': Timestamp.fromDate(fechaProximaDosis),
        'notificado': notificado,
      };
}
