import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/chat_providers.dart';
import 'package:mascoti/core/domain/chat.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/chat/presentation/comun/conversation_providers.dart';
import 'package:mascoti/plugins/chat/presentation/dueno/owner_chat_tile.dart';
import 'package:mascoti/plugins/chat/presentation/dueno/owner_inbox_page.dart';

import '../../a11y.dart';

const ana = AppUser(uid: 'ana', email: 'ana@example.com', displayName: 'Ana', role: UserRole.dueno);

/// Hora de Bogotá → instante UTC.
DateTime bogota(int d, int h, [int min = 0]) => DateTime.utc(2026, 11, d, h + 5, min);
final now = bogota(17, 10);

Chat chat(String clinic, DateTime? at, {int unread = 0, String? last, String from = 'vet'}) => Chat(
      id: 'ana_$clinic',
      ownerUid: 'ana',
      clinicId: clinic,
      clinicOwnerUid: 'vet',
      clinicNombre: 'Clínica $clinic',
      noLeidos: {'ana': unread},
      lastMessageAt: at,
      lastMessage: last == null
          ? null
          : ChatLastMessage(texto: last, tipo: ChatMessageType.texto, senderUid: from),
    );

void main() {
  Future<void> pump(WidgetTester tester, Stream<List<Chat>> chats) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: OwnerInboxPage())),
      GoRoute(path: '/chat/:id', builder: (_, s) => Text('chat ${s.pathParameters['id']}')),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(ana),
        userChatsProvider.overrideWith((ref, uid) => chats),
        chatClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  final chats = [
    chat('Sur', bogota(16, 18), last: 'Gracias por venir'),
    chat('Norte', bogota(17, 9, 30), unread: 2, last: '¿Cómo sigue Luna?'),
    chat('Centro', bogota(9, 8), last: 'Nos vemos', from: 'ana'),
  ];

  testWidgets('la más reciente primero, con vista previa, hora y no leídos', (tester) async {
    await pump(tester, Stream.value(chats));

    final names = tester
        .widgetList<OwnerChatTile>(find.byType(OwnerChatTile))
        .map((t) => t.chat.clinicNombre)
        .toList();
    expect(names, ['Clínica Norte', 'Clínica Sur', 'Clínica Centro']);
    expect(find.text('¿Cómo sigue Luna?'), findsOneWidget);
    expect(find.text('9:30 a. m.'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(find.text('lun 9 nov'), findsOneWidget);
    expect(find.text('Tú: Nos vemos'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Clínica Norte'));
    await tester.pumpAndSettle();
    expect(find.text('chat ana_Norte'), findsOneWidget);
  });

  testWidgets('vacía: mensaje del RF', (tester) async {
    await pump(tester, Stream.value(const []));
    expect(find.text(OwnerInboxPage.emptyText), findsOneWidget);
  });

  testWidgets('error con "Reintentar"', (tester) async {
    await pump(tester, Stream.error(Exception('sin conexión')));
    expect(find.text('No se pudieron cargar tus mensajes.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('TalkBack lee la conversación completa', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, Stream.value(chats));
    expect(
      find.bySemanticsLabel('Clínica Norte, ¿Cómo sigue Luna?, 9:30 a. m., 2 mensajes sin leer'),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await pump(tester, Stream.value(chats));
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      useLargeText(tester);
      await pump(tester, Stream.value(chats));
      expectNoOverflow(tester);
    });
  });
}
