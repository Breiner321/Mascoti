import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/attachments/attachment_status.dart';
import '../../../../../core/data/chat_providers.dart';
import '../../../../../core/data/chat_repository.dart';
import '../../../../../core/domain/chat.dart';
import '../../../../../core/domain/chat_message.dart';

/// Archivo que se está enviando al chat: se muestra como burbuja con barra
/// de progreso y, si falla, con "Reintentar" (RF-16, flujo alterno).
@immutable
class PendingUpload {
  const PendingUpload({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.status = AttachmentStatus.uploading,
    this.error,
    this.referenciaHistorialId,
  });

  final String id;
  final String nombre;
  final ChatAttachmentType tipo;
  final AttachmentStatus status;
  final String? error;
  final String? referenciaHistorialId;

  PendingUpload copyWith({AttachmentStatus? status, String? error}) => PendingUpload(
        id: id,
        nombre: nombre,
        tipo: tipo,
        status: status ?? this.status,
        error: error,
        referenciaHistorialId: referenciaHistorialId,
      );
}

/// Contenido del archivo. Para un adjunto del historial se descarga primero;
/// el resultado se guarda para reintentar sin volver a bajarlo.
typedef UploadSource = Future<Uint8List> Function();

/// Subidas en curso de una conversación. Van por fuera del envío de texto:
/// una subida lenta o fallida no bloquea el resto del chat. Cuando termina,
/// se envía el mensaje tipo adjunto y la burbuja sale de esta lista (el
/// mensaje ya aparece en la conversación).
class ChatUploadsController extends Notifier<List<PendingUpload>> {
  ChatUploadsController(this.chatId);

  final String chatId;
  final _sources = <String, UploadSource>{};
  final _bytes = <String, Uint8List>{};
  final _chats = <String, (Chat, String)>{};
  int _seq = 0;

  @override
  List<PendingUpload> build() => const [];

  /// Sube [source] como [nombre] y lo envía a [chat] de parte de [senderUid].
  void send({
    required Chat chat,
    required String senderUid,
    required String nombre,
    required ChatAttachmentType tipo,
    required UploadSource source,
    String? referenciaHistorialId,
  }) {
    final upload = PendingUpload(
      id: 'u${_seq++}',
      nombre: nombre,
      tipo: tipo,
      referenciaHistorialId: referenciaHistorialId,
    );
    _sources[upload.id] = source;
    _chats[upload.id] = (chat, senderUid);
    state = [...state, upload];
    _run(upload);
  }

  /// "Reintentar" en una burbuja con error.
  void retry(String id) {
    final upload = _find(id);
    if (upload == null || upload.status != AttachmentStatus.failed) return;
    final again = upload.copyWith(status: AttachmentStatus.uploading);
    _replace(again);
    _run(again);
  }

  /// Quita una burbuja con error (el usuario decide no enviarla).
  void discard(String id) {
    _forget(id);
    state = [for (final u in state) if (u.id != id) u];
  }

  Future<void> _run(PendingUpload upload) async {
    final repository = ref.read(chatRepositoryProvider);
    final (chat, senderUid) = _chats[upload.id]!;
    try {
      final bytes = _bytes[upload.id] ??= await _sources[upload.id]!();
      final adjunto = await repository.uploadAttachment(
        chatId: chatId,
        fileName: upload.nombre,
        bytes: bytes,
      );
      if (!ref.mounted || _find(upload.id) == null) return;
      repository.sendAttachment(
        chat: chat,
        senderUid: senderUid,
        adjunto: adjunto,
        referenciaHistorialId: upload.referenciaHistorialId,
      );
      discard(upload.id);
    } catch (e) {
      if (!ref.mounted || _find(upload.id) == null) return;
      // Los errores que se pueden reintentar (red, servidor) se muestran
      // como dice el RF; los demás (tipo, tamaño) con su propio mensaje.
      final message = e is ChatFailure && !e.canRetry
          ? e.message
          : ChatFailure.uploadFailed.message;
      if (e is! ChatFailure) debugPrint('Falló el adjunto ${upload.nombre}: $e');
      _replace(upload.copyWith(status: AttachmentStatus.failed, error: message));
    }
  }

  PendingUpload? _find(String id) {
    for (final u in state) {
      if (u.id == id) return u;
    }
    return null;
  }

  void _replace(PendingUpload upload) =>
      state = [for (final u in state) u.id == upload.id ? upload : u];

  void _forget(String id) {
    _sources.remove(id);
    _bytes.remove(id);
    _chats.remove(id);
  }
}

/// Subidas en curso de cada conversación: `chatUploadsProvider(chatId)`.
final chatUploadsProvider =
    NotifierProvider.family<ChatUploadsController, List<PendingUpload>, String>(
  ChatUploadsController.new,
);
