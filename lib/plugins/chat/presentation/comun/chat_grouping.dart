import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../../../../core/domain/chat_message.dart';
import '../../../../core/format/bogota_time.dart';
import '../../../../core/format/time_format.dart';

/// Lógica pura de la conversación (RF-15): separadores por día, estados del
/// mensaje y la frase que lee TalkBack. Las fechas se muestran en hora de
/// Bogotá, como el resto de la app.

/// Estado de un mensaje propio: enviando (reloj), enviado (✓), leído (✓✓).
enum MessageStatus {
  sending('enviando'),
  sent('enviado'),
  read('leído');

  const MessageStatus(this.label);

  /// Texto para el lector de pantalla.
  final String label;

  static MessageStatus of(ChatMessage message) => message.pendiente
      ? sending
      : message.leido
          ? read
          : sent;
}

/// Elemento de la lista de la conversación.
@immutable
sealed class ChatItem {
  const ChatItem();
}

/// "Hoy", "Ayer", "lun 9 nov".
class DaySeparatorItem extends ChatItem {
  const DaySeparatorItem(this.label);

  final String label;

  @override
  bool operator ==(Object other) => other is DaySeparatorItem && other.label == label;

  @override
  int get hashCode => label.hashCode;
}

class MessageItem extends ChatItem {
  const MessageItem(this.message);

  final ChatMessage message;

  @override
  bool operator ==(Object other) => other is MessageItem && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'];

/// Hora del mensaje; los que aún no confirma el servidor se toman como "ahora".
DateTime _instantOf(ChatMessage m, DateTime now) => m.timestamp ?? now;

DateTime _bogotaDay(DateTime instant) {
  final w = BogotaTime.wallClock(instant);
  return DateTime.utc(w.year, w.month, w.day);
}

/// "Hoy", "Ayer", "lun 9 nov" (con el año si no es el actual).
String dayLabel(DateTime instant, DateTime now) {
  final day = _bogotaDay(instant);
  final today = _bogotaDay(now);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  final base = '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
  return day.year == today.year ? base : '$base ${day.year}';
}

/// "9:30 a. m." en hora de Bogotá.
String timeLabel(DateTime instant) {
  final w = BogotaTime.wallClock(instant);
  return TimeFormat.ofTime(TimeOfDay(hour: w.hour, minute: w.minute));
}

/// Hora de la bandeja: la hora si es de hoy; si no, "Ayer" o "lun 9 nov".
String inboxTimeLabel(DateTime? instant, DateTime now) {
  if (instant == null) return '';
  final label = dayLabel(instant, now);
  return label == 'Hoy' ? timeLabel(instant) : label;
}

/// Mensajes (del más antiguo al más nuevo) con un separador antes del
/// primero de cada día.
List<ChatItem> groupByDay(List<ChatMessage> messages, DateTime now) {
  final items = <ChatItem>[];
  String? current;
  for (final m in messages) {
    final label = dayLabel(_instantOf(m, now), now);
    if (label != current) {
      items.add(DaySeparatorItem(label));
      current = label;
    }
    items.add(MessageItem(m));
  }
  return items;
}

/// Lo que TalkBack lee de una burbuja, completo y en orden:
/// "Clínica Patitas, 9:30 a. m.: ¿Cómo sigue Luna?" o
/// "Tú, 9:31 a. m.: Mucho mejor, leído". El estado solo en los propios.
String bubbleSemantics({
  required ChatMessage message,
  required bool mine,
  required String otherName,
  required DateTime now,
}) {
  final who = mine ? 'Tú' : (otherName.isEmpty ? 'Mensaje' : otherName);
  final body = switch ((message.tipo, message.adjunto)) {
    (ChatMessageType.adjunto, final ChatAttachment a) => [
        'archivo ${a.nombre}',
        if (message.texto.trim().isNotEmpty) message.texto.trim(),
      ].join(', '),
    _ => message.texto.trim(),
  };
  final status = mine ? ', ${MessageStatus.of(message).label}' : '';
  return '$who, ${timeLabel(_instantOf(message, now))}: $body$status';
}

/// El contador del campo aparece al acercarse al máximo.
const counterFrom = ChatLimits.maxText - 200;

bool showCounter(String text) => text.length >= counterFrom;
