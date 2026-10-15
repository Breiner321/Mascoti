import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Archivos de la app en Supabase Storage (buckets privados). Lo comparten
/// varios plugins, por eso vive en el core.
///
/// - `mascoti`: archivos de cada usuario en `usuarios/{uid}/...` (adjuntos
///   del chat, PDF…). Máximo 10 MB; imágenes y PDF.
/// - `mascotas`: fotos de mascotas en `{ownerUid}/{petId}/foto.jpg|png`.
///   Máximo 5 MB; solo JPG/PNG. Las lee cualquier usuario con sesión.
///
/// Las políticas están en supabase/migrations. Para mostrar un archivo se
/// pide un enlace firmado temporal ([signedUrl]); en Firestore se guarda la
/// ruta, no la URL.
class StorageRepository {
  StorageRepository(this._storage);

  /// null = Supabase no está configurado en este equipo (falta env/dev.json).
  final SupabaseStorageClient? _storage;

  static const bucket = 'mascoti';
  static const petsBucket = 'mascotas';

  StorageFileApi _files(String bucketId) {
    final storage = _storage;
    if (storage == null) {
      throw StateError('Supabase no está configurado (ver env/dev.json)');
    }
    return storage.from(bucketId);
  }

  /// Ruta completa dentro del bucket `mascoti` para un archivo del usuario
  /// [uid]. [path] es relativo, p. ej. `chat/<chatId>/adjunto.pdf`.
  static String userPath(String uid, String path) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    if (uid.isEmpty || clean.isEmpty || clean.contains('..')) {
      throw ArgumentError('Ruta de archivo inválida: $path');
    }
    return 'usuarios/$uid/$clean';
  }

  /// Ruta de la foto de una mascota en el bucket `mascotas`
  /// (= `pets/{petId}.fotoPath`).
  static String petPhotoPath(String ownerUid, String petId, {bool png = false}) {
    if (ownerUid.isEmpty || petId.isEmpty || ownerUid.contains('/') || petId.contains('/')) {
      throw ArgumentError('Mascota inválida: $ownerUid/$petId');
    }
    return '$ownerUid/$petId/foto.${png ? 'png' : 'jpg'}';
  }

  /// Sube (o reemplaza) un archivo del usuario al bucket `mascoti` y devuelve
  /// su ruta.
  Future<String> upload({
    required String uid,
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final fullPath = userPath(uid, path);
    await _files(bucket).uploadBinary(
      fullPath,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: true),
    );
    return fullPath;
  }

  /// Sube (o reemplaza) la foto de una mascota y devuelve la ruta que se
  /// guarda en `pets/{petId}.fotoPath`. Supabase rechaza archivos de más de
  /// 5 MB o que no sean JPG/PNG.
  Future<String> uploadPetPhoto({
    required String ownerUid,
    required String petId,
    required Uint8List bytes,
    bool png = false,
  }) async {
    final path = petPhotoPath(ownerUid, petId, png: png);
    await _files(petsBucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: png ? 'image/png' : 'image/jpeg',
        upsert: true,
      ),
    );
    return path;
  }

  /// Enlace temporal para ver o descargar un archivo privado.
  Future<String> signedUrl(
    String fullPath, {
    String bucketId = bucket,
    Duration expiresIn = const Duration(hours: 1),
  }) =>
      _files(bucketId).createSignedUrl(fullPath, expiresIn.inSeconds);

  Future<void> delete(String fullPath, {String bucketId = bucket}) =>
      _files(bucketId).remove([fullPath]);
}
