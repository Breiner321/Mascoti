import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/chat_providers.dart';
import 'package:mascoti/core/data/chat_repository.dart';
import 'package:mascoti/core/domain/chat.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/chat/presentation/comun/chat_ui_providers.dart';
import 'package:mascoti/plugins/chat/presentation/comun/conversation_page.dart';
import 'package:mascoti/plugins/chat/presentation/comun/conversation_providers.dart';
import 'package:mocktail/mocktail.dart';

import '../../a11y.dart';

class _MockRepo extends Mock implements ChatRepository {}

const ana = AppUser(uid: 'ana', email: 'ana@example.com', displayName: 'Ana', role: UserRole.dueno);
const vet =
    AppUser(uid: 'vet', email: 'vet@example.com', displayName: 'Vet', role: UserRole.clinica, clinicId: 'c1');

/// Hora de Bogotá → instante UTC.
DateTime bogota(int d, int h, [int min = 0]) => DateTime.utc(2026, 11, d, h + 5, min);
final now = bogota(17, 10);

Chat chatWith({Map<String, DateTime> typing = const {}}) => Chat(
      id: 'ana_c1',
      ownerUid: 'ana',
      clinicId: 'c1',
      clinicOwnerUid: 'vet',
      ownerNombre: 'Ana Pérez',
      clinicNombre: 'Clínica Patitas',
      noLeidos: const {'ana': 1, 'vet': 0},
      typing: typing,
    );

ChatMessage m(String id, String from, String text, DateTime? at,
        {bool leido = false, bool pendiente = false}) =>
    ChatMessage(
      id: id,
      senderUid: from,
      tipo: ChatMessageType.texto,
      texto: text,
      timestamp: at,
      leido: leido,
      pendiente: pendiente,
    );

void main() {
  late _MockRepo repo;
  late List<int> requestedLimits;
  late List<Uri> opened;

  setUpAll(() => registerFallbackValue(chatWith()));

  setUp(() {
    repo = _MockRepo();
    requestedLimits = [];
    opened = [];
    when(() => repo.markAsRead(chat: any(named: 'chat'), uid: any(named: 'uid')))
        .thenAnswer((_) async {});
    when(() => repo.setTyping(
          chatId: any(named: 'chatId'),
          uid: any(named: 'uid'),
          typing: any(named: 'typing'),
        )).thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    AppUser user = ana,
    Chat? chat,
    List<ChatMessage> Function(int limit)? messages,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        chatRepositoryProvider.overrideWithValue(repo),
        chatProvider('ana_c1').overrideWith((ref) => Stream.value(chat ?? chatWith())),
        chatMessagesProvider.overrideWith((ref, q) {
          requestedLimits.add(q.limit);
          return Stream.value(messages?.call(q.limit) ?? const []);
        }),
        clinicPhoneProvider('c1').overrideWith((ref) async => '6041234567'),
        chatClockProvider.overrideWithValue(() => now),
        offlineNoticeDelayProvider.overrideWithValue(const Duration(seconds: 1)),
        chatUrlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const ConversationPage(chatId: 'ana_c1'),
      ),
    ));
    await tester.pumpAndSettle();
  }

  List<ChatMessage> sample(int _) => [
        m('1', 'vet', 'Hola, ¿cómo sigue Luna?', bogota(16, 18)),
        m('2', 'ana', 'Mejor, gracias', bogota(16, 18, 5), leido: true),
        m('3', 'vet', 'Que siga con la dieta', bogota(17, 9, 30)),
        m('4', 'ana', 'Listo', bogota(17, 9, 40)),
        m('5', 'ana', 'Sin red', null, pendiente: true),
      ];

  testWidgets('encabezado, separadores por día y estados con ícono', (tester) async {
    await pump(tester, messages: sample);

    expect(find.text('Clínica Patitas'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Que siga con la dieta'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget); // leído
    expect(find.byIcon(Icons.done), findsOneWidget); // enviado
    expect(find.byIcon(Icons.schedule), findsOneWidget); // enviando
    // Al abrir marca como leídos.
    verify(() => repo.markAsRead(chat: any(named: 'chat'), uid: 'ana')).called(greaterThan(0));
  });

  testWidgets('cada burbuja se lee completa con TalkBack', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, messages: sample);
    expect(find.bySemanticsLabel('Clínica Patitas, 9:30 a. m.: Que siga con la dieta'), findsOneWidget);
    expect(find.bySemanticsLabel('Tú, 6:05 p. m.: Mejor, gracias, leído'), findsOneWidget);
    expect(find.bySemanticsLabel('Tú, 10:00 a. m.: Sin red, enviando'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('enviar: deshabilitado vacío, envía y limpia el campo', (tester) async {
    when(() => repo.sendText(
          chat: any(named: 'chat'),
          senderUid: any(named: 'senderUid'),
          text: any(named: 'text'),
        )).thenAnswer((inv) => (
          message: m('n', 'ana', inv.namedArguments[#text] as String, null, pendiente: true),
          delivered: Future<void>.value(),
        ));
    await pump(tester, messages: sample);

    IconButton send() => tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(send().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(send().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '¿A qué hora abren?');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();

    verify(() => repo.sendText(
          chat: any(named: 'chat'),
          senderUid: 'ana',
          text: '¿A qué hora abren?',
        )).called(1);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(ConversationPage.offlineNotice), findsNothing);
  });

  testWidgets('si el servidor rechaza el envío, lo avisa y devuelve el texto al campo',
      (tester) async {
    when(() => repo.sendText(
          chat: any(named: 'chat'),
          senderUid: any(named: 'senderUid'),
          text: any(named: 'text'),
        )).thenAnswer((_) => (
          message: m('n', 'ana', 'Hola', null, pendiente: true),
          delivered: Future<void>.error(Exception('permission-denied')),
        ));
    await pump(tester, messages: sample);

    await tester.enterText(find.byType(TextField), 'Holaaaa');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    await tester.pump();

    expect(find.text(ConversationPage.sendFailedNotice), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Holaaaa');
  });

  testWidgets('sin conexión: aviso no bloqueante hasta que el servidor confirma', (tester) async {
    final server = Completer<void>();
    when(() => repo.sendText(
          chat: any(named: 'chat'),
          senderUid: any(named: 'senderUid'),
          text: any(named: 'text'),
        )).thenAnswer((_) => (
          message: m('n', 'ana', 'Hola', null, pendiente: true),
          delivered: server.future,
        ));
    await pump(tester, messages: sample);

    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(ConversationPage.offlineNotice), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(ConversationPage.offlineNotice), findsOneWidget);
    // El campo sigue disponible: no bloquea.
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isNot(false));

    server.complete();
    await tester.pump();
    expect(find.text(ConversationPage.offlineNotice), findsNothing);
  });

  testWidgets('conversación vacía', (tester) async {
    await pump(tester);
    expect(find.text(ConversationPage.emptyText), findsOneWidget);
  });

  testWidgets('contador al acercarse a 2000', (tester) async {
    await pump(tester, messages: sample);
    await tester.enterText(find.byType(TextField), 'a' * 1799);
    await tester.pump();
    expect(find.text('1799/2000'), findsNothing);
    await tester.enterText(find.byType(TextField), 'a' * 1850);
    await tester.pump();
    expect(find.text('1850/2000'), findsOneWidget);
  });

  testWidgets('"Cargar mensajes anteriores" pide una página más', (tester) async {
    await pump(
      tester,
      messages: (limit) => [
        for (var i = 0; i < limit; i++) m('$i', 'vet', 'Mensaje $i', bogota(10, 8, i)),
      ],
    );
    expect(requestedLimits.last, ChatLimits.pageSize);

    await tester.dragUntilVisible(
      find.text('Cargar mensajes anteriores'),
      find.byType(ListView),
      const Offset(0, 600),
    );
    await tester.tap(find.text('Cargar mensajes anteriores'));
    await tester.pumpAndSettle();
    expect(requestedLimits.last, ChatLimits.pageSize * 2);
  });

  testWidgets('"escribiendo…" y "Llamar" para el dueño', (tester) async {
    await pump(tester, chat: chatWith(typing: {'vet': now}), messages: sample);
    expect(find.text('escribiendo…'), findsOneWidget);

    await tester.tap(find.byTooltip('Llamar'));
    await tester.pumpAndSettle();
    expect(opened, [Uri(scheme: 'tel', path: '6041234567')]);
  });

  testWidgets('la clínica ve el nombre del dueño y no tiene "Llamar"', (tester) async {
    await pump(tester, user: vet, messages: sample);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.byTooltip('Llamar'), findsNothing);
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await pump(tester, messages: sample);
      await expectAccessible(tester);
    });

    testWidgets('modo oscuro', (tester) async {
      await pump(tester, messages: sample, theme: AppTheme.of(AppPalette.dark));
      await expectAccessible(tester);
      AppTheme.light();
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      useLargeText(tester);
      await pump(tester, messages: sample);
      expectNoOverflow(tester);
    });
  });
}
