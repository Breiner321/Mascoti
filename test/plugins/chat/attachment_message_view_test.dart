import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/chat_providers.dart';
import 'package:mascoti/core/data/chat_repository.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/chat/presentation/comun/adjuntos/attachment_link_cache.dart';
import 'package:mascoti/plugins/chat/presentation/comun/adjuntos/attachment_message_view.dart';
import 'package:mascoti/plugins/chat/presentation/comun/chat_ui_providers.dart';

import 'chat_test_fakes.dart';

ChatMessage pdfMessage({String? referencia}) => ChatMessage(
      id: 'm1',
      senderUid: 'vet',
      tipo: ChatMessageType.adjunto,
      adjunto: const ChatAttachment(
        path: 'ana_c1/x-hemograma.pdf',
        nombre: 'hemograma.pdf',
        tipo: ChatAttachmentType.pdf,
        tamanoBytes: 2048,
      ),
      referenciaHistorialId: referencia,
    );

void main() {
  late FakeChatRepository repository;
  late List<Uri> opened;

  setUp(() {
    repository = FakeChatRepository();
    opened = [];
  });

  Future<void> pump(WidgetTester tester, ChatMessage message) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        chatUrlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
        chatPetProvider.overrideWith(
          (ref, petId) async => petId == 'p1'
              ? const Pet(id: 'p1', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.gato)
              : null,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AttachmentMessageView(chatId: 'ana_c1', message: message, mine: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('al dueño le aparece "Del historial médico de <mascota>"', (tester) async {
    await pump(tester, pdfMessage(referencia: 'p1/r1'));
    expect(find.text('hemograma.pdf'), findsOneWidget);
    expect(find.text('Del historial médico de Luna'), findsOneWidget);
  });

  testWidgets('un archivo nuevo no lleva etiqueta', (tester) async {
    await pump(tester, pdfMessage());
    expect(find.textContaining('Del historial'), findsNothing);
  });

  testWidgets('el PDF se abre con un enlace de adjuntos-chat', (tester) async {
    repository.urls
      ..clear()
      ..add('https://files/pdf');
    await pump(tester, pdfMessage());
    await tester.tap(find.text('hemograma.pdf'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://files/pdf')]);
  });

  testWidgets('si el enlace falla pide otro sin avisar', (tester) async {
    repository.urls
      ..clear()
      ..addAll([const ChatFailure('vencido', canRetry: true), 'https://files/nuevo']);
    await pump(tester, pdfMessage());
    await tester.tap(find.text('hemograma.pdf'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://files/nuevo')]);
    expect(find.text(AttachmentMessageView.unavailable), findsNothing);
  });

  testWidgets('si el archivo ya no existe: "Archivo no disponible"', (tester) async {
    repository.urls
      ..clear()
      ..add(const ChatFailure('Object not found'));
    await pump(tester, pdfMessage());
    await tester.tap(find.text('hemograma.pdf'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text(AttachmentMessageView.unavailable), findsWidgets);
  });

  group('AttachmentLinkCache', () {
    test('reutiliza el enlace y pide otro cuando vence', () async {
      var now = DateTime(2026, 11, 12, 10);
      var calls = 0;
      final cache = AttachmentLinkCache(
        ({required chatId, required path}) async => 'url${++calls}',
        clock: () => now,
      );
      expect(await cache.url(chatId: 'c', path: 'c/a'), 'url1');
      now = now.add(const Duration(minutes: 10));
      expect(await cache.url(chatId: 'c', path: 'c/a'), 'url1');
      now = now.add(const Duration(minutes: 4));
      expect(await cache.url(chatId: 'c', path: 'c/a'), 'url2');
      expect(await cache.url(chatId: 'c', path: 'c/a', refresh: true), 'url3');
    });

    test('dos pedidos a la vez comparten la misma llamada', () async {
      var calls = 0;
      final cache = AttachmentLinkCache(({required chatId, required path}) async {
        calls++;
        return 'url';
      });
      await Future.wait([
        cache.url(chatId: 'c', path: 'c/a'),
        cache.url(chatId: 'c', path: 'c/a'),
      ]);
      expect(calls, 1);
    });
  });
}
