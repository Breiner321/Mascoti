import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Archivo elegido para adjuntar (historial médico o chat).
@immutable
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Elige una radiografía, examen o foto (JPG, PNG o PDF) del teléfono. Lo
/// usan el historial médico (RF-08) y el chat (RF-16). Se reemplaza en las
/// pruebas.
class AttachmentPicker {
  const AttachmentPicker();

  /// Imagen o PDF. null si el usuario cancela.
  Future<PickedFile?> pick() => _pickFile(const ['jpg', 'jpeg', 'png', 'pdf']);

  /// Solo un PDF. null si el usuario cancela.
  Future<PickedFile?> pickPdf() => _pickFile(const ['pdf']);

  /// Una foto de la galería. null si el usuario cancela.
  Future<PickedFile?> pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return PickedFile(name: file.name, bytes: await file.readAsBytes());
  }

  Future<PickedFile?> _pickFile(List<String> extensions) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (file == null) return null;
    return PickedFile(name: file.name, bytes: await file.xFile.readAsBytes());
  }
}
