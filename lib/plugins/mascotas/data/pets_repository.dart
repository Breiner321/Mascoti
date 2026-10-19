import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/domain/clinic.dart';
import '../../../core/domain/patient_code.dart';
import '../../../core/domain/pet.dart';
import '../../../core/storage/storage_repository.dart';
import '../domain/pet_photo.dart';

/// Firestore rechazó la escritura (`firestore.rules`).
class PetPermissionDenied implements Exception {
  const PetPermissionDenied();
}

/// Acceso a `pets` desde el plugin mascotas. La foto va al bucket `mascotas`
/// de Supabase Storage y en el documento se guarda su ruta (`fotoPath`).
class PetsRepository {
  PetsRepository({
    FirebaseFirestore? firestore,
    StorageRepository? storage,
    String Function()? generateCode,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage,
        _generateCode = generateCode ?? PatientCode.generate;

  final FirebaseFirestore _firestore;
  final String Function() _generateCode;

  /// Intentos para encontrar un código de paciente libre. Con 923.521
  /// códigos, una colisión es rara; dos seguidas, casi imposibles.
  static const _maxCodeAttempts = 5;

  /// Campos que el formulario nunca escribe al editar: el código no cambia y
  /// las clínicas solo se quitan con [revokeClinic].
  static const _systemFields = ['createdAt', 'codigoPaciente', 'clinicasAutorizadas'];

  /// null en pruebas que no suben fotos.
  final StorageRepository? _storage;

  CollectionReference<Map<String, dynamic>> get _pets => _firestore.collection('pets');
  CollectionReference<Map<String, dynamic>> get _codes =>
      _firestore.collection('codigosPaciente');

  /// Mascotas del dueño, la más reciente primero.
  ///
  /// Se ordena en el cliente para no necesitar un índice compuesto
  /// (ownerUid + createdAt): un dueño tiene pocas mascotas.
  Stream<List<Pet>> watchPets(String ownerUid) => _pets
      .where('ownerUid', isEqualTo: ownerUid)
      .snapshots()
      .map((snap) {
        final pets = [for (final d in snap.docs) Pet.fromMap(d.id, d.data())];
        pets.sort((a, b) {
          final ad = a.createdAt, bd = b.createdAt;
          if (ad == null || bd == null) return a.nombre.compareTo(b.nombre);
          return bd.compareTo(ad);
        });
        return pets;
      });

  /// Una mascota; null si no existe (o se borró).
  Stream<Pet?> watchPet(String petId) => _pets.doc(petId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : Pet.fromMap(doc.id, data);
      });

  /// Id para una mascota nueva (se necesita antes de guardar para la ruta
  /// de la foto).
  String newPetId() => _pets.doc().id;

  /// Crea ([isNew]) o edita la mascota y, si hay [photo], la sube después.
  ///
  /// Si la subida falla, la mascota queda guardada sin la foto nueva y el
  /// resultado lo indica con `photoFailed` para ofrecer el reintento
  /// ([uploadPhoto]).
  Future<PetSaveResult> savePet(
    Pet pet, {
    required bool isNew,
    PetPhoto? photo,
    ValueChanged<PetSaveStage>? onStage,
  }) async {
    onStage?.call(PetSaveStage.saving);
    final data = pet.toMap();
    for (final field in _systemFields) {
      data.remove(field);
    }
    final ref = _pets.doc(pet.id);
    if (isNew) {
      await _withNewCode(pet, (batch, code) {
        batch.set(ref, {
          ...data,
          'codigoPaciente': code,
          'clinicasAutorizadas': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } else {
      try {
        await ref.update(data);
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') throw const PetPermissionDenied();
        rethrow;
      }
    }

    if (photo == null) return PetSaveResult(petId: pet.id);
    final uploaded = await uploadPhoto(pet, photo, onStage: onStage);
    return PetSaveResult(petId: pet.id, photoFailed: !uploaded);
  }

  /// Asigna el código de paciente a una mascota creada antes de la semana 3
  /// (las nuevas ya lo traen). Devuelve el código.
  Future<String> ensurePatientCode(Pet pet) async {
    final existing = pet.codigoPaciente;
    if (existing != null) return existing;
    return _withNewCode(pet, (batch, code) {
      batch.update(_pets.doc(pet.id), {'codigoPaciente': code});
    });
  }

  /// Nombre y datos de una clínica autorizada (cualquier usuario con sesión
  /// puede leer `clinics`). null si ya no existe.
  Stream<Clinic?> watchClinic(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : Clinic.fromMap(doc.id, data);
      });

  /// RF-08: el dueño quita el acceso de una clínica a la mascota y a su
  /// historial. Agregar clínicas solo lo hace `vincular-mascota`.
  Future<void> revokeClinic(String petId, String clinicId) async {
    try {
      await _pets.doc(petId).update({
        'clinicasAutorizadas': FieldValue.arrayRemove([clinicId]),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw const PetPermissionDenied();
      rethrow;
    }
  }

  /// Escribe en un mismo lote `codigosPaciente/{codigo}` y lo que [write]
  /// haga con la mascota. Si el código ya existe, las reglas rechazan el
  /// lote completo (el código solo se puede crear) y se prueba con otro.
  Future<String> _withNewCode(
    Pet pet,
    void Function(WriteBatch batch, String code) write,
  ) async {
    for (var attempt = 1; ; attempt++) {
      final code = _generateCode();
      final batch = _firestore.batch()
        ..set(_codes.doc(code), {
          'petId': pet.id,
          'ownerUid': pet.ownerUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      write(batch, code);
      try {
        await batch.commit();
        return code;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        if (attempt >= _maxCodeAttempts) throw const PetPermissionDenied();
      }
    }
  }

  /// Sube la foto y guarda su ruta en la mascota. Devuelve false si falla;
  /// en ese caso la mascota queda como estaba.
  Future<bool> uploadPhoto(
    Pet pet,
    PetPhoto photo, {
    ValueChanged<PetSaveStage>? onStage,
  }) async {
    onStage?.call(PetSaveStage.uploadingPhoto);
    final storage = _storage;
    if (storage == null) return false;
    try {
      final path = await storage.uploadPetPhoto(
        ownerUid: pet.ownerUid,
        petId: pet.id,
        bytes: photo.bytes,
        png: photo.png,
      );
      await _pets.doc(pet.id).update({'fotoPath': path});
      // Si cambió de JPG a PNG (o al revés) queda un archivo huérfano.
      final previous = pet.fotoPath;
      if (previous != null && previous != path) {
        try {
          await storage.delete(previous, bucketId: StorageRepository.petsBucket);
        } catch (_) {
          // No es grave: la mascota ya apunta a la foto nueva.
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
