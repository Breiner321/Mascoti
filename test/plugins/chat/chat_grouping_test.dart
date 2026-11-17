import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/plugins/chat/presentation/comun/chat_avatar.dart';
import 'package:mascoti/plugins/chat/presentation/comun/chat_grouping.dart';

/// Hora de Bogotá → instante UTC (Bogotá es UTC-5).
DateTime bogota(int y, int m, int d, int h, [int min = 0]) => DateTime.utc(y, m, d, h + 5, min);

ChatMessage msg(String id, DateTime? at, {bool leido = false, bool pendiente = false}) =>
    ChatMessage(
      id: id,
      senderUid: 'ana',
      tipo: ChatMessageType.texto,
      texto: 'Hola $id',
      timestamp: at,
      leido: leido,
      pendiente: pendiente,
    );

void main() {
  // Martes 17 de noviembre de 2026, 10:00 a. m. en Bogotá.
  final now = bogota(2026, 11, 17, 10);

  group('etiquetas de día', () {
    test('Hoy, Ayer y "lun 9 nov"', () {
      expect(dayLabel(bogota(2026, 11, 17, 0, 5), now), 'Hoy');
      expect(dayLabel(bogota(2026, 11, 16, 23, 59), now), 'Ayer');
      expect(dayLabel(bogota(2026, 11, 9, 8), now), 'lun 9 nov');
      expect(dayLabel(bogota(2025, 12, 31, 8), now), 'mié 31 dic 2025');
    });

    test('se usa la hora de Bogotá aunque en UTC ya sea otro día', () {
      // 11:30 p. m. del 16 en Bogotá = 4:30 a. m. del 17 en UTC.
      expect(dayLabel(DateTime.utc(2026, 11, 17, 4, 30), now), 'Ayer');
    });

    test('la bandeja muestra la hora hoy y la fecha los otros días', () {
      expect(inboxTimeLabel(bogota(2026, 11, 17, 9, 30), now), '9:30 a. m.');
      expect(inboxTimeLabel(bogota(2026, 11, 16, 18), now), 'Ayer');
      expect(inboxTimeLabel(null, now), '');
    });
  });

  test('agrupa por día con un separador antes del primero de cada día', () {
    final items = groupByDay([
      msg('1', bogota(2026, 11, 9, 8)),
      msg('2', bogota(2026, 11, 16, 20)),
      msg('3', bogota(2026, 11, 16, 21)),
      msg('4', bogota(2026, 11, 17, 9)),
      // Sin hora del servidor aún (en la cola): cuenta como hoy.
      msg('5', null, pendiente: true),
    ], now);

    expect(items.map((i) => switch (i) {
          DaySeparatorItem(:final label) => '[$label]',
          MessageItem(:final message) => message.id,
        }), ['[lun 9 nov]', '1', '[Ayer]', '2', '3', '[Hoy]', '4', '5']);
    expect(groupByDay(const [], now), isEmpty);
  });

  test('estados: enviando, enviado y leído', () {
    expect(MessageStatus.of(msg('a', null, pendiente: true)), MessageStatus.sending);
    expect(MessageStatus.of(msg('b', now)), MessageStatus.sent);
    expect(MessageStatus.of(msg('c', now, leido: true)), MessageStatus.read);
  });

  group('lo que lee TalkBack', () {
    test('mensaje recibido: nombre, hora y texto', () {
      expect(
        bubbleSemantics(
          message: ChatMessage(
            id: 'x',
            senderUid: 'vet',
            tipo: ChatMessageType.texto,
            texto: '¿Cómo sigue Luna?',
            timestamp: bogota(2026, 11, 17, 9, 30),
          ),
          mine: false,
          otherName: 'Clínica Patitas',
          now: now,
        ),
        'Clínica Patitas, 9:30 a. m.: ¿Cómo sigue Luna?',
      );
    });

    test('mensaje propio: "Tú" y el estado', () {
      expect(
        bubbleSemantics(
          message: msg('y', bogota(2026, 11, 17, 9, 31), leido: true),
          mine: true,
          otherName: 'Clínica Patitas',
          now: now,
        ),
        'Tú, 9:31 a. m.: Hola y, leído',
      );
    });

    test('adjunto: nombre del archivo', () {
      expect(
        bubbleSemantics(
          message: ChatMessage(
            id: 'z',
            senderUid: 'vet',
            tipo: ChatMessageType.adjunto,
            adjunto: const ChatAttachment(
              path: 'p',
              nombre: 'examen.pdf',
              tipo: ChatAttachmentType.pdf,
              tamanoBytes: 10,
            ),
            timestamp: bogota(2026, 11, 17, 9),
          ),
          mine: false,
          otherName: 'Clínica Patitas',
          now: now,
        ),
        'Clínica Patitas, 9:00 a. m.: archivo examen.pdf',
      );
    });
  });

  test('el contador aparece al acercarse a 2000', () {
    expect(showCounter('a' * 1799), isFalse);
    expect(showCounter('a' * 1800), isTrue);
  });

  test('iniciales del avatar', () {
    expect(ChatAvatar.initials('Clínica Patitas'), 'CP');
    expect(ChatAvatar.initials('ana'), 'A');
    expect(ChatAvatar.initials('  '), '?');
  });
}
