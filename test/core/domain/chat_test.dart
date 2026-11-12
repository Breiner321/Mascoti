import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/chat.dart';
import 'package:mascoti/core/domain/chat_message.dart';

void main() {
  final at = DateTime.utc(2026, 11, 10, 15);

  group('Chat', () {
    test('id determinístico {ownerUid}_{clinicId}', () {
      expect(Chat.idFor('ana', 'c1'), 'ana_c1');
    });

    test('fromMap lee todos los campos', () {
      final chat = Chat.fromMap('ana_c1', {
        'participantes': ['ana', 'vet'],
        'ownerUid': 'ana',
        'clinicId': 'c1',
        'clinicOwnerUid': 'vet',
        'ownerNombre': 'Ana Pérez',
        'clinicNombre': 'Vet Sur',
        'petIds': ['p1'],
        'lastMessage': {'texto': 'Hola', 'tipo': 'texto', 'senderUid': 'ana'},
        'lastMessageId': 'm1',
        'lastMessageAt': Timestamp.fromDate(at),
        'noLeidos': {'ana': 0, 'vet': 3},
        'typing': {'vet': Timestamp.fromDate(at)},
        'createdAt': Timestamp.fromDate(at),
      });
      expect(chat.participantes, ['ana', 'vet']);
      expect(chat.petIds, ['p1']);
      expect(chat.lastMessage,
          const ChatLastMessage(texto: 'Hola', tipo: ChatMessageType.texto, senderUid: 'ana'));
      expect(chat.lastMessageAt, at);
      expect(chat.unreadFor('vet'), 3);
      expect(chat.unreadFor('ana'), 0);
      expect(chat.typing, {'vet': at});
    });

    test('documento incompleto: valores por defecto', () {
      final chat = Chat.fromMap('ana_c1', {'participantes': ['ana', 'vet']});
      expect(chat.ownerUid, 'ana');
      expect(chat.clinicOwnerUid, 'vet');
      expect(chat.lastMessage, isNull);
      expect(chat.lastMessageAt, isNull);
      expect(chat.unreadFor('ana'), 0);
    });

    test('el otro participante y su nombre', () {
      const chat = Chat(
        id: 'ana_c1',
        ownerUid: 'ana',
        clinicId: 'c1',
        clinicOwnerUid: 'vet',
        ownerNombre: 'Ana',
        clinicNombre: 'Vet Sur',
      );
      expect(chat.otherUid('ana'), 'vet');
      expect(chat.otherUid('vet'), 'ana');
      expect(chat.otherName('ana'), 'Vet Sur');
      expect(chat.otherName('vet'), 'Ana');
      expect(chat.isParticipant('vet'), isTrue);
      expect(chat.isParticipant('otro'), isFalse);
    });

    test('"escribiendo…" caduca a los 6 s', () {
      final chat = Chat(
        id: 'ana_c1',
        ownerUid: 'ana',
        clinicId: 'c1',
        clinicOwnerUid: 'vet',
        typing: {'vet': at},
      );
      expect(chat.isOtherTyping('ana', at.add(const Duration(seconds: 5))), isTrue);
      expect(chat.isOtherTyping('ana', at.add(const Duration(seconds: 7))), isFalse);
      // El propio no cuenta.
      expect(chat.isOtherTyping('vet', at), isFalse);
    });

    test('toCreateMap: participantes, contadores en 0 y hora del servidor', () {
      const chat = Chat(
        id: 'ana_c1',
        ownerUid: 'ana',
        clinicId: 'c1',
        clinicOwnerUid: 'vet',
        ownerNombre: 'Ana',
        clinicNombre: 'Vet Sur',
      );
      final map = chat.toCreateMap();
      expect(map['participantes'], ['ana', 'vet']);
      expect(map['noLeidos'], {'ana': 0, 'vet': 0});
      expect(map['typing'], isEmpty);
      expect(map['lastMessage'], isNull);
      expect(map['lastMessageAt'], FieldValue.serverTimestamp());
      expect(map['createdAt'], FieldValue.serverTimestamp());
    });
  });

  group('ChatMessage', () {
    test('texto: fromMap y toCreateMap', () {
      final m = ChatMessage.fromMap('m1', {
        'senderUid': 'ana',
        'tipo': 'texto',
        'texto': 'Hola',
        'timestamp': Timestamp.fromDate(at),
        'leido': true,
      });
      expect(m.tipo, ChatMessageType.texto);
      expect(m.timestamp, at);
      expect(m.leido, isTrue);
      expect(m.pendiente, isFalse);
      expect(m.isMine('ana'), isTrue);

      final map = m.toCreateMap();
      expect(map, {
        'senderUid': 'ana',
        'tipo': 'texto',
        'texto': 'Hola',
        'timestamp': FieldValue.serverTimestamp(),
        'leido': false,
      });
    });

    test('adjunto: sin texto vacío y con la referencia al historial', () {
      const m = ChatMessage(
        id: 'm2',
        senderUid: 'ana',
        tipo: ChatMessageType.adjunto,
        adjunto: ChatAttachment(
          path: 'ana_c1/abc-examen.pdf',
          nombre: 'examen.pdf',
          tipo: ChatAttachmentType.pdf,
          tamanoBytes: 2048,
        ),
        referenciaHistorialId: 'r1',
      );
      final map = m.toCreateMap();
      expect(map.containsKey('texto'), isFalse);
      expect(map['adjunto'], {
        'path': 'ana_c1/abc-examen.pdf',
        'nombre': 'examen.pdf',
        'tipo': 'pdf',
        'tamanoBytes': 2048,
      });
      expect(map['referenciaHistorialId'], 'r1');
      final read = ChatMessage.fromMap('m2', {...map, 'timestamp': null});
      expect(read.adjunto, m.adjunto);
      expect(read.referenciaHistorialId, 'r1');
    });

    test('pendiente: escrito sin confirmar (sin conexión)', () {
      final m = ChatMessage.fromMap('m1', {'senderUid': 'ana', 'tipo': 'texto'}, pendiente: true);
      expect(m.pendiente, isTrue);
      expect(m.timestamp, isNull);
    });
  });

  group('ChatLimits', () {
    test('texto de 1 a 2000 caracteres, sin contar espacios de los extremos', () {
      expect(ChatLimits.validateText(''), 'Escribe un mensaje.');
      expect(ChatLimits.validateText('   '), 'Escribe un mensaje.');
      expect(ChatLimits.validateText('a' * 2000), isNull);
      expect(ChatLimits.validateText('  ${'a' * 2000}  '), isNull);
      expect(ChatLimits.validateText('a' * 2001), 'El mensaje no puede superar 2000 caracteres.');
    });

    test('vista previa en una línea y de máximo 100 caracteres', () {
      expect(ChatLimits.preview(' Hola\n  doctor '), 'Hola doctor');
      final long = ChatLimits.preview('a' * 300);
      expect(long.length, ChatLimits.maxPreview);
      expect(long.endsWith('…'), isTrue);
    });

    test('tipos de adjunto permitidos: JPG, PNG y PDF', () {
      expect(ChatAttachmentType.fromFileName('foto.JPG'), ChatAttachmentType.imagen);
      expect(ChatAttachmentType.fromFileName('foto.jpeg'), ChatAttachmentType.imagen);
      expect(ChatAttachmentType.fromFileName('rx.png'), ChatAttachmentType.imagen);
      expect(ChatAttachmentType.fromFileName('examen.pdf'), ChatAttachmentType.pdf);
      expect(ChatAttachmentType.fromFileName('video.mp4'), isNull);
      expect(ChatAttachmentType.fromFileName('sin_extension'), isNull);
    });

    test('resumen del último mensaje: texto o nombre del archivo', () {
      const text = ChatMessage(id: 'm', senderUid: 'ana', tipo: ChatMessageType.texto, texto: 'Hola');
      expect(ChatLastMessage.of(text).toMap(), {'texto': 'Hola', 'tipo': 'texto', 'senderUid': 'ana'});
      const file = ChatMessage(
        id: 'm',
        senderUid: 'vet',
        tipo: ChatMessageType.adjunto,
        adjunto: ChatAttachment(
            path: 'a/b.png', nombre: 'rx.png', tipo: ChatAttachmentType.imagen, tamanoBytes: 1),
      );
      expect(ChatLastMessage.of(file).texto, 'rx.png');
    });
  });
}
