import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../../../../core/data/chat_repository.dart';
import '../../../../../core/domain/chat_message.dart';

/// Comprime una imagen (JPG o PNG según [png]). Se reemplaza en las pruebas.
typedef ImageCompressor = Future<Uint8List> Function(Uint8List bytes, {required bool png});

/// Lado mayor y calidad de las imágenes del chat: se ven bien en el teléfono
/// y una foto de la cámara (4–8 MB) queda en unos cientos de KB.
const chatImageMaxSide = 1920;
const chatImageQuality = 80;

Future<Uint8List> compressWithPlugin(Uint8List bytes, {required bool png}) =>
    FlutterImageCompress.compressWithList(
      bytes,
      minWidth: chatImageMaxSide,
      minHeight: chatImageMaxSide,
      quality: chatImageQuality,
      format: png ? CompressFormat.png : CompressFormat.jpeg,
    );

/// Archivo listo para subir al chat.
@immutable
class PreparedAttachment {
  const PreparedAttachment({required this.name, required this.bytes, required this.tipo});

  final String name;
  final Uint8List bytes;
  final ChatAttachmentType tipo;
}

/// Valida y prepara un archivo para el chat (RF-16 paso 4):
/// 1. solo JPG, PNG o PDF ([ChatFailure.invalidType]);
/// 2. las imágenes se comprimen (si la compresión falla o no ayuda, se usa
///    la original);
/// 3. máximo 10 MB ya comprimido ([ChatFailure.tooLarge], que sugiere
///    comprimir o elegir otro archivo).
Future<PreparedAttachment> prepareChatAttachment(
  String name,
  Uint8List bytes, {
  ImageCompressor compress = compressWithPlugin,
}) async {
  final tipo = ChatAttachmentType.fromFileName(name);
  if (tipo == null) throw ChatFailure.invalidType;
  if (bytes.isEmpty) throw const ChatFailure('El archivo está vacío. Elige otro.');
  var out = bytes;
  if (tipo == ChatAttachmentType.imagen) {
    try {
      final compressed = await compress(bytes, png: name.toLowerCase().endsWith('.png'));
      if (compressed.isNotEmpty && compressed.length < bytes.length) out = compressed;
    } catch (e) {
      debugPrint('No se pudo comprimir $name: $e');
    }
  }
  ChatRepository.validateFile(name, out.length);
  return PreparedAttachment(name: name, bytes: out, tipo: tipo);
}
