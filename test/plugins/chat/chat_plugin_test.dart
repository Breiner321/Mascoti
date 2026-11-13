import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/chat_providers.dart';
import 'package:mascoti/core/data/chat_repository.dart';
import 'package:mascoti/core/domain/chat.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/core/kernel/plugin_manifest.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/router/navigator_keys.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/chat/chat_plugin.dart';
import 'package:mascoti/plugins/chat/presentation/comun/conversation_page.dart';
import 'package:mascoti/plugins/chat/presentation/dueno/owner_inbox_page.dart';

const owner = AppUser(uid: 'ana', email: 'ana@example.com', displayName: 'Ana', role: UserRole.dueno);

Chat chat(String id, {int unreadAna = 0, String? last}) => Chat(
      id: id,
      ownerUid: 'ana',
      clinicId: id.split('_').last,
      clinicOwnerUid: 'vet_${id.split('_').last}',
      ownerNombre: 'Ana',
      clinicNombre: 'Clínica ${id.split('_').last}',
      noLeidos: {'ana': unreadAna},
      lastMessage: last == null
          ? null
          : ChatLastMessage(texto: last, tipo: ChatMessageType.texto, senderUid: 'vet'),
    );

void main() {
  group('ChatPlugin', () {
    const plugin = ChatPlugin();

    test('pestaña "Mensajes" para ambos roles, al final y con contador', () {
      final owner = plugin.destinations(UserRole.dueno).single;
      final clinic = plugin.destinations(UserRole.clinica).single;
      expect(owner.label, 'Mensajes');
      expect(owner.path, '/chat');
      expect(owner.order, 40);
      expect(clinic.order, 30);
      expect(owner.badge, same(unreadMessagesCountProvider));
    });

    test('la conversación se abre a pantalla completa', () {
      final routes = plugin.routes().cast<GoRoute>();
      expect(routes.map((r) => r.path), ['/chat', '/chat/abrir', '/chat/:chatId']);
      expect(routes[1].parentNavigatorKey, same(rootNavigatorKey));
      expect(routes.last.parentNavigatorKey, same(rootNavigatorKey));
    });

    test('está registrado en el manifiesto y las rutas no chocan', () {
      final registry = PluginRegistry(enabledPlugins);
      expect(registry.isEnabled('chat'), isTrue);
      expect(registry.hasRoute('/chat/ana_c1'), isTrue);
      expect(registry.destinationsFor(UserRole.clinica).map((d) => d.label), contains('Mensajes'));
    });
  });

  test('el contador suma los no leídos del usuario en todas sus conversaciones', () async {
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(owner),
      userChatsProvider.overrideWith((ref, uid) => Stream.value([
            chat('ana_c1', unreadAna: 2),
            chat('ana_c2', unreadAna: 3),
            chat('ana_c3'),
          ])),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(unreadMessagesCountProvider, (_, __) {});
    addTearDown(sub.close);
    await container.read(userChatsProvider('ana').future);
    expect(container.read(unreadMessagesCountProvider), 5);
  });

  Widget inbox(Stream<List<Chat>> Function() chats) => ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(owner),
          userChatsProvider.overrideWith((ref, uid) => chats()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: OwnerInboxPage())),
      );

  testWidgets('bandeja provisional: conversaciones con el último mensaje y no leídos',
      (tester) async {
    await tester.pumpWidget(inbox(() => Stream.value([
          chat('ana_c1', unreadAna: 2, last: '¿Cómo sigue Luna?'),
          chat('ana_c2'),
        ])));
    await tester.pumpAndSettle();
    expect(find.text('Clínica c1'), findsOneWidget);
    expect(find.text('¿Cómo sigue Luna?'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Sin mensajes'), findsOneWidget);
  });

  testWidgets('bandeja provisional: vacía y error con reintento', (tester) async {
    await tester.pumpWidget(inbox(() => Stream.value(const [])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aún no tienes conversaciones'), findsOneWidget);

    await tester.pumpWidget(Container());
    await tester.pumpWidget(inbox(() => Stream.error(Exception('sin red'))));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar tus mensajes.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('conversación provisional: marca como leído, envía y muestra "escribiendo…"',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final repository = ChatRepository(firestore: firestore);
    await firestore.doc('chats/ana_c1').set({
      'participantes': ['ana', 'vet'],
      'ownerUid': 'ana',
      'clinicId': 'c1',
      'clinicOwnerUid': 'vet',
      'ownerNombre': 'Ana',
      'clinicNombre': 'Vet Sur',
      'lastMessageAt': Timestamp.now(),
      'noLeidos': {'ana': 1, 'vet': 0},
      'typing': {'vet': Timestamp.now()},
    });
    await firestore.doc('chats/ana_c1/messages/m1').set({
      'senderUid': 'vet',
      'tipo': 'texto',
      'texto': '¿Cómo sigue Luna?',
      'timestamp': Timestamp.now(),
      'leido': false,
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(owner),
        chatRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const ConversationPage(chatId: 'ana_c1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Vet Sur'), findsOneWidget);
    expect(find.text('escribiendo…'), findsOneWidget);
    expect(find.text('¿Cómo sigue Luna?'), findsOneWidget);
    expect((await firestore.doc('chats/ana_c1/messages/m1').get())['leido'], isTrue);
    expect((await firestore.doc('chats/ana_c1').get())['noLeidos'], {'ana': 0, 'vet': 0});

    await tester.enterText(find.byType(TextField), 'Mucho mejor, gracias');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mucho mejor, gracias'), findsOneWidget);
    expect((await firestore.doc('chats/ana_c1').get())['noLeidos'], {'ana': 0, 'vet': 1});

    // Vacío: no se envía.
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();
    expect(find.text('Escribe un mensaje.'), findsOneWidget);
    await tester.pumpWidget(Container());
    await tester.pump(const Duration(seconds: 5));
  });
}
