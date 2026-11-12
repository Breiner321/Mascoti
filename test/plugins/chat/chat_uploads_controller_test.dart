import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/attachments/attachment_status.dart';
import 'package:mascoti/core/data/chat_providers.dart';
import 'package:mascoti/core/data/chat_repository.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/plugins/chat/presentation/comun/adjuntos/chat_uploads_controller.dart';

import 'chat_test_fakes.dart';

void main() {
  late FakeChatRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeChatRepository();
    container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(repository),
    ]);
  });
  tearDown(() => container.dispose());

  List<PendingUpload> uploads() => container.read(chatUploadsProvider('ana_c1'));
  ChatUploadsController controller() => container.read(chatUploadsProvider('ana_c1').notifier);

  void send({String nombre = 'placa.jpg', String? referencia, UploadSource? source}) =>
      controller().send(
        chat: testChat,
        senderUid: 'vet',
        nombre: nombre,
        tipo: ChatAttachmentType.fromFileName(nombre)!,
        referenciaHistorialId: referencia,
        source: source ?? () async => Uint8List(10),
      );

  test('subiendo → listo: envía el mensaje tipo adjunto y quita la burbuja', () async {
    final gate = Completer<void>();
    repository.onUpload = (name, bytes) async {
      await gate.future;
      return const ChatAttachment(
        path: 'ana_c1/u-placa.jpg',
        nombre: 'placa.jpg',
        tipo: ChatAttachmentType.imagen,
        tamanoBytes: 10,
      );
    };
    send(referencia: 'p1/r1');
    expect(uploads().single.status, AttachmentStatus.uploading);
    expect(repository.sent, isEmpty);

    gate.complete();
    await pumpEventQueue();
    expect(uploads(), isEmpty);
    final message = repository.sent.single;
    expect(message.tipo, ChatMessageType.adjunto);
    expect(message.senderUid, 'vet');
    expect(message.adjunto!.path, 'ana_c1/u-placa.jpg');
    expect(message.referenciaHistorialId, 'p1/r1');
  });

  test('subiendo → error: "Error al enviar archivo" y Reintentar lo envía', () async {
    repository.onUpload = (_, __) async => throw ChatFailure.network;
    send();
    await pumpEventQueue();
    expect(uploads().single.status, AttachmentStatus.failed);
    expect(uploads().single.error, 'Error al enviar archivo');
    expect(repository.sent, isEmpty);

    repository.onUpload = null;
    controller().retry(uploads().single.id);
    expect(uploads().single.status, AttachmentStatus.uploading);
    await pumpEventQueue();
    expect(uploads(), isEmpty);
    expect(repository.sent, hasLength(1));
  });

  test('un error que no se arregla reintentando muestra su propio mensaje', () async {
    repository.onUpload = (_, __) async => throw ChatFailure.tooLarge;
    send();
    await pumpEventQueue();
    expect(uploads().single.error, contains('supera los 10 MB'));
  });

  test('al reintentar no vuelve a descargar el archivo del historial', () async {
    var downloads = 0;
    repository.onUpload = (_, __) async => throw StateError('sin red');
    send(source: () async {
      downloads++;
      return Uint8List(5);
    });
    await pumpEventQueue();
    expect(uploads().single.status, AttachmentStatus.failed);

    repository.onUpload = null;
    controller().retry(uploads().single.id);
    await pumpEventQueue();
    expect(downloads, 1);
    expect(repository.sent, hasLength(1));
  });

  test('si falla la descarga del historial queda en error con reintento', () async {
    send(source: () async => throw Exception('404'));
    await pumpEventQueue();
    expect(uploads().single.status, AttachmentStatus.failed);
    expect(repository.uploads, isEmpty);
  });

  test('varias subidas a la vez son independientes y se pueden descartar', () async {
    repository.onUpload = (name, _) async {
      if (name == 'mala.pdf') throw ChatFailure.uploadFailed;
      return ChatAttachment(
        path: 'ana_c1/u-$name',
        nombre: name,
        tipo: ChatAttachmentType.fromFileName(name)!,
        tamanoBytes: 1,
      );
    };
    send(nombre: 'mala.pdf');
    send(nombre: 'buena.png');
    await pumpEventQueue();
    expect(uploads().map((u) => u.nombre), ['mala.pdf']);
    expect(repository.sent.single.adjunto!.nombre, 'buena.png');

    controller().discard(uploads().single.id);
    expect(uploads(), isEmpty);
  });
}
