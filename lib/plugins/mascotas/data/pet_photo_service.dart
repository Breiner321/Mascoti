import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/pet_photo.dart';
import '../domain/pet_validators.dart';

enum PetPhotoSource { camera, gallery }

/// Error al elegir o procesar la foto; [message] se muestra al usuario.
class PetPhotoException implements Exception {
  const PetPhotoException(this.message);

  final String message;
}

/// Elige una foto con la cámara o la galería y la deja lista para subir.
/// Es una interfaz para poder reemplazarla en las pruebas.
abstract interface class PetPhotoPicker {
  /// null si el usuario cancela.
  Future<PetPhoto?> pick(PetPhotoSource source);
}

class DevicePetPhotoPicker implements PetPhotoPicker {
  DevicePetPhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PetPhoto?> pick(PetPhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PetPhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (file == null) return null;
    final type = PetValidators.imageType(file.name, file.mimeType);
    if (type == null) {
      throw const PetPhotoException('Solo se permiten fotos JPG o PNG');
    }
    return compressPetPhoto(
      await file.readAsBytes(),
      png: type == PetImageType.png,
    );
  }
}

/// Reduce una imagen a JPEG de lado máximo [maxSide] con calidad [quality].
typedef PhotoCompressor = Future<Uint8List> Function(
  Uint8List bytes,
  int maxSide,
  int quality,
);

Future<Uint8List> _compressWithPlugin(Uint8List bytes, int maxSide, int quality) =>
    FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxSide,
      minHeight: maxSide,
      quality: quality,
      format: CompressFormat.jpeg,
    );

/// Intentos de compresión, de más calidad a menos.
const _attempts = [(1600, 85), (1600, 70), (1280, 60), (1024, 50), (800, 40)];

/// Deja la foto en máximo 1 MB ([PetPhoto.maxBytes]). Si ya cabe se deja
/// igual; si no, se convierte a JPEG bajando tamaño y calidad hasta que
/// quepa.
Future<PetPhoto> compressPetPhoto(
  Uint8List bytes, {
  required bool png,
  PhotoCompressor compress = _compressWithPlugin,
}) async {
  if (bytes.length <= PetPhoto.maxBytes) return PetPhoto(bytes: bytes, png: png);
  for (final (side, quality) in _attempts) {
    final Uint8List out;
    try {
      out = await compress(bytes, side, quality);
    } catch (_) {
      throw const PetPhotoException('No se pudo procesar la foto. Elige otra.');
    }
    if (out.isNotEmpty && out.length <= PetPhoto.maxBytes) {
      return PetPhoto(bytes: out);
    }
  }
  throw const PetPhotoException('La foto es muy pesada. Elige otra.');
}
