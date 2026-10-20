import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Archivo elegido para adjuntar a una consulta.
@immutable
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Elige una radiografía o examen (JPG, PNG o PDF) del teléfono. Se
/// reemplaza en las pruebas.
class AttachmentPicker {
  const AttachmentPicker();

  /// null si el usuario cancela.
  Future<PickedFile?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (file == null) return null;
    return PickedFile(name: file.name, bytes: await file.xFile.readAsBytes());
  }
}
