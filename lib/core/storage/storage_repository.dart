import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Archivos de la app (fotos de mascotas y productos, adjuntos del chat,
/// PDF) en Supabase Storage, bucket privado `mascoti`.
///
/// Cada usuario solo escribe en `usuarios/{uid}/...` (lo exigen las políticas
/// de supabase/migrations). Para mostrar un archivo se pide un enlace firmado
/// temporal. Lo comparten varios plugins, por eso vive en el core.
class StorageRepository {
  StorageRepository(this._storage);

  /// null = Supabase no está configurado en este equipo (falta env/dev.json).
  final SupabaseStorageClient? _storage;

  static const bucket = 'mascoti';

  StorageFileApi get _files {
    final storage = _storage;
    if (storage == null) {
      throw StateError('Supabase no está configurado (ver env/dev.json)');
    }
    return storage.from(bucket);
  }

  /// Ruta completa dentro del bucket para un archivo del usuario [uid].
  /// [path] es relativo, p. ej. `mascotas/<petId>/foto.jpg`.
  static String userPath(String uid, String path) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    if (uid.isEmpty || clean.isEmpty || clean.contains('..')) {
      throw ArgumentError('Ruta de archivo inválida: $path');
    }
    return 'usuarios/$uid/$clean';
  }

  /// Sube (o reemplaza) un archivo y devuelve su ruta en el bucket, que es
  /// lo que se guarda en Firestore (p. ej. `pets/{id}.fotoPath`).
  Future<String> upload({
    required String uid,
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final fullPath = userPath(uid, path);
    await _files.uploadBinary(
      fullPath,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: true),
    );
    return fullPath;
  }

  /// Enlace temporal para ver o descargar un archivo privado.
  Future<String> signedUrl(
    String fullPath, {
    Duration expiresIn = const Duration(hours: 1),
  }) =>
      _files.createSignedUrl(fullPath, expiresIn.inSeconds);

  Future<void> delete(String fullPath) => _files.remove([fullPath]);
}
