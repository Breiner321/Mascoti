import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Origen de la foto: cámara o galería.
enum PhotoSource { camera, gallery }

/// Foto lista para subir: JPG o PNG de máximo [maxBytes] (ya comprimida en
/// el teléfono). La usan los plugins que suben fotos con límite de 1 MB
/// (productos de la tienda, RF-07).
@immutable
class PickedPhoto {
  const PickedPhoto({required this.bytes, this.png = false});

  /// 1 MB después de comprimir.
  static const maxBytes = 1024 * 1024;

  /// 5 MB antes de comprimir: un archivo más grande se rechaza (RF-07).
  static const maxSourceBytes = 5 * 1024 * 1024;

  final Uint8List bytes;
  final bool png;
}

/// Error al elegir o procesar la foto; [message] se muestra al usuario.
class PhotoException implements Exception {
  const PhotoException(this.message);

  final String message;

  static const unsupported =
      PhotoException('Solo se permiten fotos JPG o PNG de máximo 5 MB. Elige otra.');

  @override
  String toString() => 'PhotoException($message)';
}

/// true si [fileName] / [mimeType] es PNG; false si es JPG; null si no es
/// ninguno de los dos.
bool? isPngImage(String fileName, String? mimeType) {
  final mime = mimeType?.toLowerCase();
  if (mime == 'image/jpeg' || mime == 'image/jpg') return false;
  if (mime == 'image/png') return true;
  final name = fileName.toLowerCase();
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return false;
  if (name.endsWith('.png')) return true;
  return null;
}

/// Elige una foto con la cámara o la galería y la deja lista para subir.
/// Es una interfaz para poder reemplazarla en las pruebas.
abstract interface class PhotoPicker {
  /// null si el usuario cancela. Lanza [PhotoException] si el archivo no
  /// sirve.
  Future<PickedPhoto?> pick(PhotoSource source);
}

class DevicePhotoPicker implements PhotoPicker {
  DevicePhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (file == null) return null;
    final png = isPngImage(file.name, file.mimeType);
    if (png == null) throw PhotoException.unsupported;
    return compressPhoto(await file.readAsBytes(), png: png);
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

/// Rechaza archivos de más de [PickedPhoto.maxSourceBytes] y deja la foto en
/// máximo [PickedPhoto.maxBytes]. Si ya cabe se deja igual; si no, se
/// convierte a JPEG bajando tamaño y calidad hasta que quepa.
Future<PickedPhoto> compressPhoto(
  Uint8List bytes, {
  required bool png,
  PhotoCompressor compress = _compressWithPlugin,
}) async {
  if (bytes.isEmpty || bytes.length > PickedPhoto.maxSourceBytes) {
    throw PhotoException.unsupported;
  }
  if (bytes.length <= PickedPhoto.maxBytes) return PickedPhoto(bytes: bytes, png: png);
  for (final (side, quality) in _attempts) {
    final Uint8List out;
    try {
      out = await compress(bytes, side, quality);
    } catch (_) {
      throw const PhotoException('No se pudo procesar la foto. Elige otra.');
    }
    if (out.isNotEmpty && out.length <= PickedPhoto.maxBytes) {
      return PickedPhoto(bytes: out);
    }
  }
  throw const PhotoException('La foto es muy pesada. Elige otra.');
}
