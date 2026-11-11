import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/chat_repository.dart';
import 'package:mascoti/core/domain/chat.dart';
import 'package:mascoti/core/domain/chat_message.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ChatRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = ChatRepository(firestore: firestore);
  });

  Future<Chat> open({String ownerUid = 'ana', String clinicId = 'c1'}) => repository.openChat(
        ownerUid: ownerUid,
        ownerNombre: 'Ana Pérez',
        clinicId: clinicId,
        clinicOwnerUid: 'vet',
        clinicNombre: 'Vet Sur',
      );

  Future<Map<String, dynamic>> chatDoc([String id = 'ana_c1']) async =>
      (await firestore.doc('chats/$id').get()).data()!;

  group('openChat', () {
    test('crea el chat con el id determinístico y lo reutiliza', () async {
      final chat = await open();
      expect(chat.id, 'ana_c1');
      final data = await chatDoc();
      expect(data['participantes'], ['ana', 'vet']);
      expect(data['noLeidos'], {'ana': 0, 'vet': 0});
      expect(data['clinicNombre'], 'Vet Sur');
      expect(data['lastMessageAt'], isA<Timestamp>());

      await firestore.doc('chats/ana_c1').update({'noLeidos.ana': 2});
      final again = await open();
      expect(again.unreadFor('ana'), 2);
      expect((await firestore.collection('chats').get()).docs, hasLength(1));
    });
  });

  group('enviar', () {
    test('un lote: mensaje, resumen y +1 al receptor', () async {
      final chat = await open();
      final sent = repository.sendText(chat: chat, senderUid: 'ana', text: '  Hola doctor  ');
      expect(sent.message.pendiente, isTrue);
      await sent.delivered;

      final message = (await firestore.doc('chats/ana_c1/messages/${sent.message.id}').get()).data()!;
      expect(message['senderUid'], 'ana');
      expect(message['texto'], 'Hola doctor');
      expect(message['leido'], isFalse);
      expect(message['timestamp'], isA<Timestamp>());

      var data = await chatDoc();
      expect(data['lastMessageId'], sent.message.id);
      expect(data['lastMessage'], {'texto': 'Hola doctor', 'tipo': 'texto', 'senderUid': 'ana'});
      expect(data['noLeidos'], {'ana': 0, 'vet': 1});

      await repository.sendText(chat: chat, senderUid: 'ana', text: 'Otra').delivered;
      await repository.sendText(chat: chat, senderUid: 'vet', text: 'Hola Ana').delivered;
      data = await chatDoc();
      expect(data['noLeidos'], {'ana': 1, 'vet': 2});
    });

    test('rechaza vacío y más de 2000 caracteres (RF-15 paso 5)', () async {
      final chat = await open();
      expect(() => repository.sendText(chat: chat, senderUid: 'ana', text: '   '),
          throwsA(isA<ChatFailure>().having((e) => e.message, 'message', 'Escribe un mensaje.')));
      expect(() => repository.sendText(chat: chat, senderUid: 'ana', text: 'a' * 2001),
          throwsA(isA<ChatFailure>()));
      expect((await firestore.collection('chats/ana_c1/messages').get()).docs, isEmpty);
    });

    test('adjunto: guarda el archivo y el resumen con su nombre', () async {
      final chat = await open();
      const adjunto = ChatAttachment(
        path: 'ana_c1/abc-examen.pdf',
        nombre: 'examen.pdf',
        tipo: ChatAttachmentType.pdf,
        tamanoBytes: 2048,
      );
      final sent = repository.sendAttachment(
          chat: chat, senderUid: 'ana', adjunto: adjunto, referenciaHistorialId: 'r1');
      await sent.delivered;
      final message = (await firestore.doc('chats/ana_c1/messages/${sent.message.id}').get()).data()!;
      expect(message['tipo'], 'adjunto');
      expect(message['adjunto'], adjunto.toMap());
      expect(message['referenciaHistorialId'], 'r1');
      expect((await chatDoc())['lastMessage'],
          {'texto': 'examen.pdf', 'tipo': 'adjunto', 'senderUid': 'ana'});
    });
  });

  group('leer', () {
    test('bandeja del usuario, la más reciente primero', () async {
      await firestore.doc('chats/ana_c1').set({
        'participantes': ['ana', 'vet'],
        'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1)),
      });
      await firestore.doc('chats/ana_c2').set({
        'participantes': ['ana', 'vet2'],
        'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 11, 9)),
      });
      await firestore.doc('chats/beto_c1').set({
        'participantes': ['beto', 'vet'],
        'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 11, 5)),
      });
      final chats = await repository.watchUserChats('ana').first;
      expect(chats.map((c) => c.id), ['ana_c2', 'ana_c1']);
    });

    test('últimos 30 mensajes en orden y "cargar anteriores"', () async {
      await open();
      final base = DateTime.utc(2026, 11, 10, 8);
      for (var i = 0; i < 35; i++) {
        await firestore.doc('chats/ana_c1/messages/m$i').set({
          'senderUid': 'ana',
          'tipo': 'texto',
          'texto': 'Mensaje $i',
          'timestamp': Timestamp.fromDate(base.add(Duration(minutes: i))),
          'leido': false,
        });
      }
      final latest = await repository.watchMessages('ana_c1').first;
      expect(latest, hasLength(30));
      expect(latest.first.texto, 'Mensaje 5');
      expect(latest.last.texto, 'Mensaje 34');

      final older = await repository.fetchOlderMessages('ana_c1', before: latest.first);
      expect(older.map((m) => m.texto), ['Mensaje 0', 'Mensaje 1', 'Mensaje 2', 'Mensaje 3', 'Mensaje 4']);
      expect(await repository.fetchOlderMessages('ana_c1', before: older.first), isEmpty);
    });

    test('marcar como leídos solo los recibidos y poner el contador propio en 0', () async {
      final chat = await open();
      final mine = repository.sendText(chat: chat, senderUid: 'vet', text: 'Hola').message;
      await repository.sendText(chat: chat, senderUid: 'ana', text: 'Hola').delivered;
      await repository.sendText(chat: chat, senderUid: 'ana', text: '¿Hay cita?').delivered;

      final current = Chat.fromMap('ana_c1', await chatDoc());
      expect(current.unreadFor('vet'), 2);
      await repository.markAsRead(chat: current, uid: 'vet');

      final messages = await firestore.collection('chats/ana_c1/messages').get();
      for (final d in messages.docs) {
        expect(d['leido'], d['senderUid'] == 'ana', reason: d.id);
      }
      expect(messages.docs.firstWhere((d) => d.id == mine.id)['leido'], isFalse);
      expect((await chatDoc())['noLeidos'], {'ana': 1, 'vet': 0});
    });

    test('"escribiendo…" con la hora del servidor y se borra', () async {
      await open();
      await repository.setTyping(chatId: 'ana_c1', uid: 'ana', typing: true);
      expect(((await chatDoc())['typing'] as Map)['ana'], isA<Timestamp>());
      await repository.setTyping(chatId: 'ana_c1', uid: 'ana', typing: false);
      expect((await chatDoc())['typing'], isEmpty);
    });
  });

  group('TypingController', () {
    test('escribe como máximo cada 3 s y se borra a los 4 s sin teclear', () {
      fakeAsync((async) {
        final writes = <bool>[];
        final controller = TypingController(write: (t) async => writes.add(t));

        controller.onTextChanged('H');
        controller.onTextChanged('Ho');
        controller.onTextChanged('Hol');
        async.flushMicrotasks();
        expect(writes, [true]);

        async.elapse(const Duration(seconds: 3));
        controller.onTextChanged('Hola');
        async.flushMicrotasks();
        expect(writes, [true, true]);

        async.elapse(const Duration(seconds: 4));
        expect(writes, [true, true, false]);
        expect(controller.isTyping, isFalse);
      });
    });

    test('vaciar el campo o enviar lo borra; sin escribir no hace nada', () {
      fakeAsync((async) {
        final writes = <bool>[];
        final controller = TypingController(write: (t) async => writes.add(t));
        controller.stop();
        controller.onTextChanged('   ');
        async.flushMicrotasks();
        expect(writes, isEmpty);

        controller.onTextChanged('Hola');
        controller.onTextChanged('');
        async.flushMicrotasks();
        expect(writes, [true, false]);

        controller.onTextChanged('Otra');
        controller.stop();
        async.elapse(const Duration(seconds: 10));
        expect(writes, [true, false, true, false]);
      });
    });

    test('un error al escribir no rompe nada', () {
      fakeAsync((async) {
        final controller = TypingController(write: (_) async => throw Exception('sin conexión'));
        controller.onTextChanged('Hola');
        async.elapse(const Duration(seconds: 5));
        expect(controller.isTyping, isFalse);
      });
    });
  });
}
