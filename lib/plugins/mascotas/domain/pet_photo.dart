import 'package:flutter/foundation.dart';

/// Foto de una mascota lista para subir: JPG o PNG de máximo [maxBytes]
/// (ya comprimida en el teléfono).
@immutable
class PetPhoto {
  const PetPhoto({required this.bytes, this.png = false});

  /// 1 MB: límite de la app (el bucket `mascotas` acepta hasta 5 MB).
  static const maxBytes = 1024 * 1024;

  final Uint8List bytes;
  final bool png;
}

/// Etapas de guardado que se muestran en el formulario.
enum PetSaveStage {
  saving('Guardando…'),
  uploadingPhoto('Subiendo foto…');

  const PetSaveStage(this.label);

  final String label;
}

/// Resultado de guardar una mascota. Si la foto no se pudo subir, la mascota
/// quedó guardada sin ella ([photoFailed]) y se puede reintentar.
@immutable
class PetSaveResult {
  const PetSaveResult({required this.petId, this.photoFailed = false});

  final String petId;
  final bool photoFailed;
}
