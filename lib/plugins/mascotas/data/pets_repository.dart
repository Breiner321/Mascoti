import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
  PetsRepository({FirebaseFirestore? firestore, StorageRepository? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage;

  final FirebaseFirestore _firestore;

  /// null en pruebas que no suben fotos.
  final StorageRepository? _storage;

  CollectionReference<Map<String, dynamic>> get _pets => _firestore.collection('pets');

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
    final data = pet.toMap()..remove('createdAt');
    final ref = _pets.doc(pet.id);
    try {
      if (isNew) {
        await ref.set({...data, 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await ref.update(data);
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw const PetPermissionDenied();
      rethrow;
    }

    if (photo == null) return PetSaveResult(petId: pet.id);
    final uploaded = await uploadPhoto(pet, photo, onStage: onStage);
    return PetSaveResult(petId: pet.id, photoFailed: !uploaded);
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
