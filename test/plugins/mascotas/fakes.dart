import 'dart:convert';
import 'dart:typed_data';

import 'package:mascoti/core/storage/storage_repository.dart';
import 'package:mascoti/plugins/mascotas/data/pet_photo_service.dart';
import 'package:mascoti/plugins/mascotas/domain/pet_photo.dart';

/// PNG válido de 1 × 1 (las pruebas de widgets decodifican la imagen).
final tinyPng = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
));

/// Storage en memoria: registra las subidas y puede simular fallos.
class FakePetStorage extends StorageRepository {
  FakePetStorage() : super(null);

  bool fail = false;
  final uploads = <String>[];
  final deleted = <String>[];

  @override
  Future<String> uploadPetPhoto({
    required String ownerUid,
    required String petId,
    required Uint8List bytes,
    bool png = false,
  }) async {
    if (fail) throw Exception('sin conexión');
    final path = StorageRepository.petPhotoPath(ownerUid, petId, png: png);
    uploads.add(path);
    return path;
  }

  @override
  Future<void> delete(String fullPath, {String bucketId = StorageRepository.bucket}) async {
    deleted.add(fullPath);
  }
}

/// Selector de fotos que devuelve siempre [photo] (null = cancelado).
class FakePhotoPicker implements PetPhotoPicker {
  FakePhotoPicker([this.photo]);

  final PetPhoto? photo;
  final sources = <PetPhotoSource>[];

  @override
  Future<PetPhoto?> pick(PetPhotoSource source) async {
    sources.add(source);
    return photo;
  }
}
