import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'chat_message.dart';

/// Resumen del último mensaje, para la bandeja (`chats.lastMessage`).
@immutable
class ChatLastMessage {
  const ChatLastMessage({required this.texto, required this.tipo, required this.senderUid});

  /// Vista previa de un texto (máximo [ChatLimits.maxPreview] caracteres).
  /// En un adjunto, el nombre del archivo.
  final String texto;
  final ChatMessageType tipo;
  final String senderUid;

  factory ChatLastMessage.fromMap(Map<String, dynamic> map) => ChatLastMessage(
        texto: map['texto'] as String? ?? '',
        tipo: ChatMessageType.fromValue(map['tipo']) ?? ChatMessageType.texto,
        senderUid: map['senderUid'] as String? ?? '',
      );

  /// Resumen de [message] (lo que la app escribe al enviar).
  factory ChatLastMessage.of(ChatMessage message) => ChatLastMessage(
        texto: message.tipo == ChatMessageType.adjunto
            ? ChatLimits.preview(message.adjunto?.nombre ?? '')
            : ChatLimits.preview(message.texto),
        tipo: message.tipo,
        senderUid: message.senderUid,
      );

  Map<String, dynamic> toMap() => {'texto': texto, 'tipo': tipo.value, 'senderUid': senderUid};

  @override
  bool operator ==(Object other) =>
      other is ChatLastMessage &&
      other.texto == texto &&
      other.tipo == tipo &&
      other.senderUid == senderUid;

  @override
  int get hashCode => Object.hash(texto, tipo, senderUid);
}

/// Documento `chats/{ownerUid}_{clinicId}` (RF-15): una conversación entre
/// un dueño y una clínica. Los mensajes están en la subcolección `messages`.
///
/// - `participantes`: `[ownerUid, clinicOwnerUid]` (uid de quien maneja la
///   clínica); con eso se leen las reglas y la bandeja.
/// - `noLeidos[uid]`: mensajes sin leer de cada participante. Al enviar sube
///   en 1 el del receptor, en el mismo lote que el mensaje (las reglas lo
///   validan); cada uno solo pone el suyo en 0.
/// - `typing[uid]`: hora de la última tecla de ese participante ("escribiendo…"
///   si tiene menos de [typingTimeout]).
@immutable
class Chat {
  const Chat({
    required this.id,
    required this.ownerUid,
    required this.clinicId,
    required this.clinicOwnerUid,
    this.ownerNombre = '',
    this.clinicNombre = '',
    this.petIds = const [],
    this.lastMessage,
    this.lastMessageId,
    this.lastMessageAt,
    this.noLeidos = const {},
    this.typing = const {},
    this.createdAt,
  });

  /// "escribiendo…" deja de mostrarse si la última tecla tiene más de esto
  /// (la app se cerró sin borrar `typing`).
  static const typingTimeout = Duration(seconds: 6);

  /// Id determinístico: una sola conversación por dueño y clínica.
  static String idFor(String ownerUid, String clinicId) => '${ownerUid}_$clinicId';

  factory Chat.fromMap(String id, Map<String, dynamic> map) {
    final participants = (map['participantes'] as List?)?.cast<String>() ?? const [];
    return Chat(
      id: id,
      ownerUid: map['ownerUid'] as String? ?? (participants.isNotEmpty ? participants.first : ''),
      clinicId: map['clinicId'] as String? ?? '',
      clinicOwnerUid: map['clinicOwnerUid'] as String? ??
          (participants.length > 1 ? participants[1] : ''),
      ownerNombre: map['ownerNombre'] as String? ?? '',
      clinicNombre: map['clinicNombre'] as String? ?? '',
      petIds: (map['petIds'] as List?)?.cast<String>() ?? const [],
      lastMessage: map['lastMessage'] is Map
          ? ChatLastMessage.fromMap(Map<String, dynamic>.from(map['lastMessage'] as Map))
          : null,
      lastMessageId: map['lastMessageId'] as String?,
      lastMessageAt: (map['lastMessageAt'] as Timestamp?)?.toDate().toUtc(),
      noLeidos: {
        for (final e in (map['noLeidos'] as Map? ?? const {}).entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
      typing: {
        for (final e in (map['typing'] as Map? ?? const {}).entries)
          if (e.value is Timestamp) '${e.key}': (e.value as Timestamp).toDate().toUtc(),
      },
      createdAt: (map['createdAt'] as Timestamp?)?.toDate().toUtc(),
    );
  }

  final String id;
  final String ownerUid;
  final String clinicId;
  final String clinicOwnerUid;

  /// Copias al crear el chat (la clínica no puede leer `users`).
  final String ownerNombre;
  final String clinicNombre;

  /// Mascotas de la conversación (opcional; obligatoria si la crea la clínica).
  final List<String> petIds;
  final ChatLastMessage? lastMessage;
  final String? lastMessageId;

  /// null mientras el servidor no confirma la hora.
  final DateTime? lastMessageAt;
  final Map<String, int> noLeidos;
  final Map<String, DateTime> typing;
  final DateTime? createdAt;

  List<String> get participantes => [ownerUid, clinicOwnerUid];

  bool isParticipant(String uid) => uid == ownerUid || uid == clinicOwnerUid;

  /// El otro participante de [uid].
  String otherUid(String uid) => uid == ownerUid ? clinicOwnerUid : ownerUid;

  /// Nombre del otro participante, para el encabezado y la bandeja.
  String otherName(String uid) => uid == ownerUid ? clinicNombre : ownerNombre;

  int unreadFor(String uid) => noLeidos[uid] ?? 0;

  /// El otro participante de [uid] está escribiendo (a la hora [now]).
  bool isOtherTyping(String uid, DateTime now) {
    final last = typing[otherUid(uid)];
    return last != null && now.difference(last) < typingTimeout;
  }

  /// Datos para crear el chat (`lastMessageAt` y `createdAt` con la hora del
  /// servidor; los dos contadores en 0).
  Map<String, dynamic> toCreateMap() => {
        'participantes': participantes,
        'ownerUid': ownerUid,
        'clinicId': clinicId,
        'clinicOwnerUid': clinicOwnerUid,
        'ownerNombre': ownerNombre,
        'clinicNombre': clinicNombre,
        'petIds': petIds,
        'lastMessage': null,
        'lastMessageId': null,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'noLeidos': {ownerUid: 0, clinicOwnerUid: 0},
        'typing': <String, dynamic>{},
        'createdAt': FieldValue.serverTimestamp(),
      };

  Chat copyWith({
    String? ownerNombre,
    String? clinicNombre,
    List<String>? petIds,
    ChatLastMessage? lastMessage,
    String? lastMessageId,
    DateTime? lastMessageAt,
    Map<String, int>? noLeidos,
    Map<String, DateTime>? typing,
  }) =>
      Chat(
        id: id,
        ownerUid: ownerUid,
        clinicId: clinicId,
        clinicOwnerUid: clinicOwnerUid,
        ownerNombre: ownerNombre ?? this.ownerNombre,
        clinicNombre: clinicNombre ?? this.clinicNombre,
        petIds: petIds ?? this.petIds,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageId: lastMessageId ?? this.lastMessageId,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        noLeidos: noLeidos ?? this.noLeidos,
        typing: typing ?? this.typing,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Chat &&
      other.id == id &&
      other.ownerUid == ownerUid &&
      other.clinicId == clinicId &&
      other.clinicOwnerUid == clinicOwnerUid &&
      other.ownerNombre == ownerNombre &&
      other.clinicNombre == clinicNombre &&
      listEquals(other.petIds, petIds) &&
      other.lastMessage == lastMessage &&
      other.lastMessageId == lastMessageId &&
      other.lastMessageAt == lastMessageAt &&
      mapEquals(other.noLeidos, noLeidos) &&
      mapEquals(other.typing, typing) &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, ownerUid, clinicId, clinicOwnerUid, ownerNombre,
      clinicNombre, Object.hashAll(petIds), lastMessage, lastMessageId, lastMessageAt);
}
