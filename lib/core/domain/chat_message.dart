import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Tipo de mensaje (RF-15, RF-16). [value] se guarda en Firestore.
enum ChatMessageType {
  texto('texto'),
  adjunto('adjunto');

  const ChatMessageType(this.value);

  final String value;

  static ChatMessageType? fromValue(Object? value) {
    for (final t in values) {
      if (t.value == value) return t;
    }
    return null;
  }
}

/// Tipo de archivo adjunto (RF-16). [value] se guarda en Firestore.
enum ChatAttachmentType {
  imagen('imagen'),
  pdf('pdf');

  const ChatAttachmentType(this.value);

  final String value;

  static ChatAttachmentType? fromValue(Object? value) {
    for (final t in values) {
      if (t.value == value) return t;
    }
    return null;
  }

  /// Tipo según la extensión del archivo (JPG, PNG o PDF), o null si no se
  /// permite.
  static ChatAttachmentType? fromFileName(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' || 'png' => ChatAttachmentType.imagen,
      'pdf' => ChatAttachmentType.pdf,
      _ => null,
    };
  }
}

/// Límites del chat (iguales a firestore.rules y a la Edge Function
/// `adjuntos-chat`).
abstract final class ChatLimits {
  /// RF-15 paso 5.
  static const maxText = 2000;

  /// RF-16 paso 4: 10 MB.
  static const maxAttachmentBytes = 10 * 1024 * 1024;

  /// Largo máximo de la vista previa de `chats.lastMessage.texto`.
  static const maxPreview = 100;

  static const maxFileName = 120;

  /// Mensajes por página (RF-15: los últimos 30 y "cargar anteriores").
  static const pageSize = 30;

  /// Mensaje de error del texto, o null si se puede enviar.
  static String? validateText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Escribe un mensaje.';
    if (trimmed.length > maxText) {
      return 'El mensaje no puede superar $maxText caracteres.';
    }
    return null;
  }

  /// Vista previa de un texto para la bandeja, en una sola línea.
  static String preview(String text) {
    final line = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return line.length <= maxPreview ? line : '${line.substring(0, maxPreview - 1)}…';
  }
}

/// Archivo adjunto de un mensaje. [path] es la ruta en el bucket privado
/// `chats` de Supabase (`{chatId}/{uuid}-{nombre}`); para verlo se pide un
/// enlace temporal a la Edge Function `adjuntos-chat`.
@immutable
class ChatAttachment {
  const ChatAttachment({
    required this.path,
    required this.nombre,
    required this.tipo,
    required this.tamanoBytes,
  });

  factory ChatAttachment.fromMap(Map<String, dynamic> map) => ChatAttachment(
        path: map['path'] as String? ?? '',
        nombre: map['nombre'] as String? ?? '',
        tipo: ChatAttachmentType.fromValue(map['tipo']) ?? ChatAttachmentType.pdf,
        tamanoBytes: (map['tamanoBytes'] as num?)?.toInt() ?? 0,
      );

  final String path;
  final String nombre;
  final ChatAttachmentType tipo;
  final int tamanoBytes;

  Map<String, dynamic> toMap() => {
        'path': path,
        'nombre': nombre,
        'tipo': tipo.value,
        'tamanoBytes': tamanoBytes,
      };

  @override
  bool operator ==(Object other) =>
      other is ChatAttachment &&
      other.path == path &&
      other.nombre == nombre &&
      other.tipo == tipo &&
      other.tamanoBytes == tamanoBytes;

  @override
  int get hashCode => Object.hash(path, nombre, tipo, tamanoBytes);
}

/// Documento `chats/{chatId}/messages/{messageId}` (RF-15, RF-16). Nadie
/// edita el texto ni lo borra; el receptor solo cambia [leido] a true.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.tipo,
    this.texto = '',
    this.adjunto,
    this.referenciaHistorialId,
    this.timestamp,
    this.leido = false,
    this.pendiente = false,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map, {bool pendiente = false}) =>
      ChatMessage(
        id: id,
        senderUid: map['senderUid'] as String? ?? '',
        tipo: ChatMessageType.fromValue(map['tipo']) ?? ChatMessageType.texto,
        texto: map['texto'] as String? ?? '',
        adjunto: map['adjunto'] is Map
            ? ChatAttachment.fromMap(Map<String, dynamic>.from(map['adjunto'] as Map))
            : null,
        referenciaHistorialId: map['referenciaHistorialId'] as String?,
        timestamp: (map['timestamp'] as Timestamp?)?.toDate().toUtc(),
        leido: map['leido'] as bool? ?? false,
        pendiente: pendiente,
      );

  final String id;
  final String senderUid;
  final ChatMessageType tipo;

  /// El texto (tipo texto, 1–2000 caracteres) o un comentario opcional del
  /// adjunto.
  final String texto;
  final ChatAttachment? adjunto;

  /// Registro del historial médico del que viene el adjunto (RF-16).
  final String? referenciaHistorialId;

  /// Hora del servidor; null (o estimada) mientras no se confirma.
  final DateTime? timestamp;
  final bool leido;

  /// Escrito en el teléfono y aún sin confirmar por el servidor (sin conexión:
  /// "Enviando…"). No se guarda en Firestore.
  final bool pendiente;

  bool isMine(String uid) => senderUid == uid;

  /// Datos para crear el mensaje (`timestamp` con la hora del servidor).
  Map<String, dynamic> toCreateMap() => {
        'senderUid': senderUid,
        'tipo': tipo.value,
        if (tipo == ChatMessageType.texto || texto.isNotEmpty) 'texto': texto,
        if (adjunto != null) 'adjunto': adjunto!.toMap(),
        if (referenciaHistorialId != null) 'referenciaHistorialId': referenciaHistorialId,
        'timestamp': FieldValue.serverTimestamp(),
        'leido': false,
      };

  ChatMessage copyWith({bool? leido, bool? pendiente, DateTime? timestamp}) => ChatMessage(
        id: id,
        senderUid: senderUid,
        tipo: tipo,
        texto: texto,
        adjunto: adjunto,
        referenciaHistorialId: referenciaHistorialId,
        timestamp: timestamp ?? this.timestamp,
        leido: leido ?? this.leido,
        pendiente: pendiente ?? this.pendiente,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.senderUid == senderUid &&
      other.tipo == tipo &&
      other.texto == texto &&
      other.adjunto == adjunto &&
      other.referenciaHistorialId == referenciaHistorialId &&
      other.timestamp == timestamp &&
      other.leido == leido &&
      other.pendiente == pendiente;

  @override
  int get hashCode => Object.hash(
      id, senderUid, tipo, texto, adjunto, referenciaHistorialId, timestamp, leido, pendiente);
}
