import 'dart:async';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:mascoti/core/data/chat_repository.dart';
import 'package:mascoti/core/domain/chat.dart';
import 'package:mascoti/core/domain/chat_message.dart';

/// ChatRepository con la subida y los enlaces de `adjuntos-chat` simulados.
class FakeChatRepository extends ChatRepository {
  FakeChatRepository() : super(firestore: FakeFirebaseFirestore());

  /// Lo que hace cada subida: completar, fallar o quedarse esperando.
  Future<ChatAttachment> Function(String fileName, Uint8List bytes)? onUpload;
  final uploads = <String>[];
  final sent = <ChatMessage>[];

  /// Respuestas de `leer`, en orden (la última se repite).
  final urls = <Object>['https://files/1'];
  int urlCalls = 0;

  @override
  Future<ChatAttachment> uploadAttachment({
    required String chatId,
    required String fileName,
    required Uint8List bytes,
  }) {
    uploads.add(fileName);
    final upload = onUpload;
    if (upload != null) return upload(fileName, bytes);
    return Future.value(ChatAttachment(
      path: '$chatId/u-$fileName',
      nombre: fileName,
      tipo: ChatAttachmentType.fromFileName(fileName)!,
      tamanoBytes: bytes.length,
    ));
  }

  @override
  SentMessage sendAttachment({
    required Chat chat,
    required String senderUid,
    required ChatAttachment adjunto,
    String texto = '',
    String? referenciaHistorialId,
  }) {
    final message = ChatMessage(
      id: 'm${sent.length}',
      senderUid: senderUid,
      tipo: ChatMessageType.adjunto,
      adjunto: adjunto,
      referenciaHistorialId: referenciaHistorialId,
    );
    sent.add(message);
    return (message: message.copyWith(pendiente: true), delivered: Future.value());
  }

  @override
  Future<String> attachmentUrl({required String chatId, required String path}) async {
    final answer = urls[urlCalls < urls.length ? urlCalls : urls.length - 1];
    urlCalls++;
    if (answer is Exception) throw answer;
    return answer as String;
  }
}

const testChat = Chat(
  id: 'ana_c1',
  ownerUid: 'ana',
  clinicId: 'c1',
  clinicOwnerUid: 'vet',
  ownerNombre: 'Ana Pérez',
  clinicNombre: 'Vet Sur',
  petIds: ['p1'],
);
