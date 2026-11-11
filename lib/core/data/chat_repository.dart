import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat.dart';
import '../domain/chat_message.dart';

/// Error del chat, con el mensaje para mostrar.
@immutable
class ChatFailure implements Exception {
  const ChatFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;

  static const network = ChatFailure('No se pudo conectar. Verifica tu conexión', canRetry: true);
  static const notConfigured =
      ChatFailure('Los archivos del chat no están disponibles en esta versión de la app');

  /// RF-16, flujo alterno: archivo de más de 10 MB.
  static const tooLarge = ChatFailure(
    'El archivo supera los 10 MB. Comprime la imagen o selecciona un archivo más liviano.',
  );
  static const invalidType = ChatFailure('Solo se permiten imágenes JPG o PNG y archivos PDF.');

  /// RF-16, flujo alterno: falla en la subida (con reintento).
  static const uploadFailed = ChatFailure('Error al enviar archivo', canRetry: true);

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
///
/// Servidor (Edge Functions de Supabase):
/// - `notificar-mensaje`: push al receptor. Se llama sola cuando el servidor
///   confirma un mensaje; si falla, el mensaje igual quedó enviado.
/// - `adjuntos-chat`: enlaces firmados para subir y ver archivos (bucket
///   privado `chats`).
class ChatRepository {
  ChatRepository({
    FirebaseFirestore? firestore,
    FunctionsClient? functions,
    SupabaseStorageClient? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions,
        _storage = storage;

  final FirebaseFirestore _firestore;

  /// null = Supabase no está configurado (falta env/dev.json): el chat de
  /// texto funciona, sin push ni archivos.
  final FunctionsClient? _functions;
  final SupabaseStorageClient? _storage;

  static const attachmentsBucket = 'chats';
  static const notifyFunction = 'notificar-mensaje';
  static const attachmentsFunction = 'adjuntos-chat';
  static const _timeout = Duration(seconds: 30);

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
    final delivered = batch.commit();
    // Push al receptor cuando el servidor confirma (sin conexión, al volver).
    unawaited(delivered.then(
      (_) => notifyMessage(chatId: chat.id, messageId: message.id),
      onError: (Object _) {},
    ));
    return (message: message.copyWith(pendiente: true), delivered: delivered);
  }

  /// Pide a `notificar-mensaje` el push del mensaje [messageId]. Nunca
  /// lanza: el push es opcional (el servidor además lo omite si el receptor
  /// ya lo leyó o si hubo otro push de la conversación hace menos de 30 s).
  Future<void> notifyMessage({required String chatId, required String messageId}) async {
    final functions = _functions;
    if (functions == null) return;
    try {
      await functions
          .invoke(notifyFunction, body: {'chatId': chatId, 'messageId': messageId})
          .timeout(_timeout);
    } catch (e) {
      debugPrint('notificar-mensaje falló para $chatId/$messageId: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Adjuntos (RF-16, Edge Function `adjuntos-chat`)
  // ---------------------------------------------------------------------------

  /// Valida el archivo en la app (RF-16 paso 4): JPG, PNG o PDF de máximo
  /// 10 MB. Lanza [ChatFailure.invalidType] o [ChatFailure.tooLarge].
  static ChatAttachmentType validateFile(String fileName, int sizeBytes) {
    final type = ChatAttachmentType.fromFileName(fileName);
    if (type == null) throw ChatFailure.invalidType;
    if (sizeBytes > ChatLimits.maxAttachmentBytes) throw ChatFailure.tooLarge;
    return type;
  }

  /// Sube [bytes] al bucket `chats` con un enlace de un solo uso y devuelve
  /// el adjunto para [sendAttachment]. Si falla la subida lanza
  /// [ChatFailure.uploadFailed] (reintentar no bloquea los mensajes de texto).
  Future<ChatAttachment> uploadAttachment({
    required String chatId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    validateFile(fileName, bytes.length);
    final data = await _invoke(attachmentsFunction, {
      'accion': 'subir',
      'chatId': chatId,
      'nombreArchivo': fileName,
      'tamanoBytes': bytes.length,
    });
    final storage = _storage;
    if (storage == null) throw ChatFailure.notConfigured;
    final path = data['path'] as String;
    try {
      await storage.from(attachmentsBucket).uploadBinaryToSignedUrl(
            path,
            data['token'] as String,
            bytes,
            FileOptions(contentType: _contentType(fileName)),
          );
    } on StorageException {
      throw ChatFailure.uploadFailed;
    } on SocketException {
      throw ChatFailure.uploadFailed;
    } on http.ClientException {
      throw ChatFailure.uploadFailed;
    }
    return ChatAttachment(
      path: path,
      nombre: data['nombre'] as String? ?? fileName,
      tipo: ChatAttachmentType.fromValue(data['tipo']) ?? ChatAttachmentType.pdf,
      tamanoBytes: bytes.length,
    );
  }

  /// Sube el archivo y envía el mensaje (RF-16 pasos 4–6).
  Future<SentMessage> sendFile({
    required Chat chat,
    required String senderUid,
    required String fileName,
    required Uint8List bytes,
    String texto = '',
    String? referenciaHistorialId,
  }) async {
    final adjunto = await uploadAttachment(chatId: chat.id, fileName: fileName, bytes: bytes);
    return sendAttachment(
      chat: chat,
      senderUid: senderUid,
      adjunto: adjunto,
      texto: texto,
      referenciaHistorialId: referenciaHistorialId,
    );
  }

  /// Enlace temporal (15 min) para ver o descargar un adjunto (RF-16 paso 8).
  Future<String> attachmentUrl({required String chatId, required String path}) async {
    final data = await _invoke(
      attachmentsFunction,
      {'accion': 'leer', 'chatId': chatId, 'path': path},
    );
    return data['url'] as String;
  }

  Future<Map<String, dynamic>> _invoke(String function, Map<String, dynamic> body) async {
    final functions = _functions;
    if (functions == null) throw ChatFailure.notConfigured;
    try {
      final response = await functions.invoke(function, body: body).timeout(_timeout);
      return Map<String, dynamic>.from(response.data as Map);
    } on TimeoutException {
      throw ChatFailure.network;
    } on SocketException {
      throw ChatFailure.network;
    } on http.ClientException {
      throw ChatFailure.network;
    } on FunctionException catch (e) {
      final error = e.details is Map ? (e.details as Map)['error'] : null;
      final message = error is Map ? error['message'] as String? : null;
      throw ChatFailure(
        message ?? 'No se pudo procesar el archivo. Intenta de nuevo.',
        canRetry: e.status >= 500,
      );
    }
  }

  static String _contentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      _ => 'image/jpeg',
    };
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
