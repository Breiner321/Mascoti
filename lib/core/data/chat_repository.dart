import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/chat.dart';
import '../domain/chat_message.dart';

/// Error del chat, con el mensaje para mostrar.
@immutable
class ChatFailure implements Exception {
  const ChatFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;

  static const network = ChatFailure('No se pudo conectar. Verifica tu conexión', canRetry: true);

  @override
  String toString() => 'ChatFailure($message)';
}

/// Mensaje recién escrito: [message] ya está en la cola local (la pantalla
/// lo muestra con "Enviando…") y [delivered] termina cuando el servidor lo
/// confirma. Sin conexión, Firestore lo envía solo al volver la conexión.
typedef SentMessage = ({ChatMessage message, Future<void> delivered});

/// Chat entre dueño y clínica (RF-15, RF-16), compartido por las pantallas
/// de los dos roles.
///
/// Todo se escribe directo en Firestore (así funciona la cola offline);
/// `firestore.rules` valida participantes, emisor, largo y contadores. Enviar
/// es un solo lote: el mensaje y el resumen del chat con +1 en `noLeidos`
/// del receptor.
class ChatRepository {
  ChatRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _chats => _firestore.collection('chats');

  CollectionReference<Map<String, dynamic>> _messages(String chatId) =>
      _chats.doc(chatId).collection('messages');

  // ---------------------------------------------------------------------------
  // Conversaciones
  // ---------------------------------------------------------------------------

  /// Abre la conversación entre el dueño y la clínica: la reutiliza si ya
  /// existe o la crea (RF-15 paso 2). La clínica debe indicar al menos una
  /// mascota del dueño que la autorizó ([petIds]); el dueño puede hablar con
  /// cualquier clínica activa.
  Future<Chat> openChat({
    required String ownerUid,
    required String ownerNombre,
    required String clinicId,
    required String clinicOwnerUid,
    required String clinicNombre,
    List<String> petIds = const [],
  }) async {
    final ref = _chats.doc(Chat.idFor(ownerUid, clinicId));
    try {
      final existing = await ref.get();
      if (existing.exists) return Chat.fromMap(existing.id, existing.data()!);
      final chat = Chat(
        id: ref.id,
        ownerUid: ownerUid,
        clinicId: clinicId,
        clinicOwnerUid: clinicOwnerUid,
        ownerNombre: ownerNombre,
        clinicNombre: clinicNombre,
        petIds: petIds,
        noLeidos: {ownerUid: 0, clinicOwnerUid: 0},
      );
      await ref.set(chat.toCreateMap());
      return chat;
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') throw ChatFailure.network;
      if (e.code == 'permission-denied') {
        throw const ChatFailure('No puedes iniciar una conversación con esta clínica.');
      }
      rethrow;
    }
  }

  /// Una conversación, o null si no existe.
  Stream<Chat?> watchChat(String chatId) => _chats.doc(chatId).snapshots().map(
        (d) => d.exists ? Chat.fromMap(d.id, d.data()!) : null,
      );

  /// Bandeja de [uid]: sus conversaciones, la del último mensaje más
  /// reciente primero.
  Stream<List<Chat>> watchUserChats(String uid) => _chats
      .where('participantes', arrayContains: uid)
      .orderBy('lastMessageAt', descending: true)
      .snapshots()
      .map((snap) => [for (final d in snap.docs) Chat.fromMap(d.id, d.data())]);

  // ---------------------------------------------------------------------------
  // Mensajes
  // ---------------------------------------------------------------------------

  static ChatMessage _message(DocumentSnapshot<Map<String, dynamic>> d) =>
      ChatMessage.fromMap(d.id, d.data()!, pendiente: d.metadata.hasPendingWrites);

  /// Los últimos [limit] mensajes, del más antiguo al más nuevo, en tiempo
  /// real (incluye los que están en la cola sin conexión). Para "cargar
  /// anteriores" se puede volver a escuchar con un [limit] mayor (los
  /// mensajes viejos siguen recibiendo el doble check) o usar
  /// [fetchOlderMessages].
  Stream<List<ChatMessage>> watchMessages(String chatId, {int limit = ChatLimits.pageSize}) =>
      _messages(chatId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots(includeMetadataChanges: true)
          .map((snap) => [for (final d in snap.docs.reversed) _message(d)]);

  /// Hasta [limit] mensajes anteriores a [before], del más antiguo al más
  /// nuevo. Vacío si ya no hay más.
  Future<List<ChatMessage>> fetchOlderMessages(
    String chatId, {
    required ChatMessage before,
    int limit = ChatLimits.pageSize,
  }) async {
    final timestamp = before.timestamp;
    if (timestamp == null) return const [];
    final snap = await _messages(chatId)
        .where('timestamp', isLessThan: Timestamp.fromDate(timestamp))
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return [for (final d in snap.docs.reversed) _message(d)];
  }

  /// Envía un texto (RF-15 pasos 4–6). Lanza [ChatFailure] si está vacío o
  /// supera 2000 caracteres. No espera al servidor: devuelve el mensaje en
  /// cuanto queda en la cola local.
  SentMessage sendText({required Chat chat, required String senderUid, required String text}) {
    final error = ChatLimits.validateText(text);
    if (error != null) throw ChatFailure(error);
    return _send(
      chat,
      ChatMessage(
        id: _messages(chat.id).doc().id,
        senderUid: senderUid,
        tipo: ChatMessageType.texto,
        texto: text.trim(),
      ),
    );
  }

  /// Envía un archivo ya subido al bucket `chats` (RF-16). [texto] es un
  /// comentario opcional.
  SentMessage sendAttachment({
    required Chat chat,
    required String senderUid,
    required ChatAttachment adjunto,
    String texto = '',
    String? referenciaHistorialId,
  }) {
    if (texto.trim().length > ChatLimits.maxText) {
      throw const ChatFailure('El mensaje no puede superar ${ChatLimits.maxText} caracteres.');
    }
    return _send(
      chat,
      ChatMessage(
        id: _messages(chat.id).doc().id,
        senderUid: senderUid,
        tipo: ChatMessageType.adjunto,
        texto: texto.trim(),
        adjunto: adjunto,
        referenciaHistorialId: referenciaHistorialId,
      ),
    );
  }

  SentMessage _send(Chat chat, ChatMessage message) {
    final receiver = chat.otherUid(message.senderUid);
    final batch = _firestore.batch()
      ..set(_messages(chat.id).doc(message.id), message.toCreateMap())
      ..update(_chats.doc(chat.id), {
        'lastMessage': ChatLastMessage.of(message).toMap(),
        'lastMessageId': message.id,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'noLeidos.$receiver': FieldValue.increment(1),
        // Al enviar deja de "escribir".
        'typing.${message.senderUid}': FieldValue.delete(),
      });
    return (message: message.copyWith(pendiente: true), delivered: batch.commit());
  }

  /// Marca como leídos los mensajes que [uid] recibió y pone su contador en
  /// 0 (RF-15 paso 9). Se llama al abrir la conversación y al llegar
  /// mensajes con la conversación abierta.
  Future<void> markAsRead({required Chat chat, required String uid}) async {
    final unread = await _messages(chat.id)
        .where('leido', isEqualTo: false)
        .where('senderUid', isEqualTo: chat.otherUid(uid))
        .get();
    if (unread.docs.isEmpty && chat.unreadFor(uid) == 0) return;
    // Máximo 500 escrituras por lote.
    const chunk = 450;
    for (var i = 0; i < unread.docs.length || i == 0; i += chunk) {
      final batch = _firestore.batch();
      for (final d in unread.docs.skip(i).take(chunk)) {
        batch.update(d.reference, {'leido': true});
      }
      if (i == 0) batch.update(_chats.doc(chat.id), {'noLeidos.$uid': 0});
      await batch.commit();
    }
  }

  /// "escribiendo…" de [uid]: la hora del servidor o se borra.
  Future<void> setTyping({required String chatId, required String uid, required bool typing}) =>
      _chats.doc(chatId).update({
        'typing.$uid': typing ? FieldValue.serverTimestamp() : FieldValue.delete(),
      });
}

/// Debounce de "escribiendo…" (RF-15 paso 8): escribe en Firestore como
/// máximo cada [refresh] mientras el usuario teclea y lo borra después de
/// [idle] sin teclear, al vaciar el campo o al enviar ([stop]).
class TypingController {
  TypingController({
    required Future<void> Function(bool typing) write,
    this.refresh = const Duration(seconds: 3),
    this.idle = const Duration(seconds: 4),
  }) : _write = write;

  final Future<void> Function(bool typing) _write;
  final Duration refresh;
  final Duration idle;

  bool _typing = false;
  bool _canRefresh = true;
  Timer? _refreshTimer;
  Timer? _idleTimer;

  bool get isTyping => _typing;

  /// Llamar en cada cambio del campo de texto.
  void onTextChanged(String text) {
    if (text.trim().isEmpty) {
      stop();
      return;
    }
    if (!_typing || _canRefresh) {
      _typing = true;
      _canRefresh = false;
      _refreshTimer?.cancel();
      _refreshTimer = Timer(refresh, () => _canRefresh = true);
      _send(true);
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(idle, stop);
  }

  /// Deja de "escribir" (al enviar, al vaciar el campo o al salir).
  void stop() {
    _idleTimer?.cancel();
    _refreshTimer?.cancel();
    _canRefresh = true;
    if (!_typing) return;
    _typing = false;
    _send(false);
  }

  void dispose() => stop();

  // Un fallo (sin conexión) no importa: es un indicador efímero.
  void _send(bool typing) => unawaited(_write(typing).catchError((Object _) {}));
}
