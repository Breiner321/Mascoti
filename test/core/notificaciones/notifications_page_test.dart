import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/notificaciones/data/notifications_repository.dart';
import 'package:mascoti/core/notificaciones/notifications_providers.dart';
import 'package:mascoti/core/notificaciones/presentation/notifications_page.dart';
import 'package:mascoti/core/notificaciones/push/notification_navigator.dart';
import 'package:mascoti/core/router/core_routes.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/core/widgets/app_shell.dart';

import '../fake_plugins.dart';

void main() {
  const owner = AppUser(uid: 'ana', email: 'ana@correo.co', displayName: 'Ana', role: UserRole.dueno);
  late FakeFirebaseFirestore firestore;

  final registry = PluginRegistry([
    FakePlugin('reservas',
        roles: {UserRole.dueno}, paths: ['/reservas', '/reservas/:id'], tabs: [tab('/reservas', 10)]),
  ]);

  setUp(() => firestore = FakeFirebaseFirestore());

  final unreadDots = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Sin leer');

  Future<void> seed(String id, {bool leido = false, String tipo = 'cita_aprobada', int minute = 0}) =>
      firestore.doc('notifications/$id').set({
        'uid': 'ana',
        'tipo': tipo,
        'titulo': 'Título $id',
        'cuerpo': 'Cuerpo $id',
        'referenciaId': 'a1',
        'leido': leido,
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(Duration(minutes: 10 - minute))),
      });

  List<Override> overrides() => [
        currentUserProvider.overrideWithValue(owner),
        pluginRegistryProvider.overrideWithValue(registry),
        notificationsRepositoryProvider
            .overrideWithValue(NotificationsRepository(firestore: firestore)),
      ];

  Future<GoRouter> pumpPage(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: CoreRoutes.notifications,
      routes: [
        GoRoute(
          path: CoreRoutes.notifications,
          builder: (context, state) => const Scaffold(body: NotificationsPage()),
        ),
        GoRoute(
          path: '/reservas/:id',
          builder: (context, state) => Text('Detalle ${state.pathParameters['id']}'),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('lista en tiempo real y "Marcar como leídas"', (tester) async {
    await seed('n1', minute: 1);
    await seed('n2', minute: 5, leido: true);
    await pumpPage(tester);

    expect(find.text('Título n1'), findsOneWidget);
    expect(find.text('Título n2'), findsOneWidget);
    expect(find.text('Hace 5 min'), findsOneWidget);
    expect(unreadDots, findsOneWidget);

    await seed('n3', minute: 9);
    await tester.pumpAndSettle();
    expect(find.text('Título n3'), findsOneWidget);
    expect(unreadDots, findsNWidgets(2));

    await tester.tap(find.text('Marcar como leídas'));
    await tester.pumpAndSettle();
    expect(unreadDots, findsNothing);
    final unread = await firestore.collection('notifications').where('leido', isEqualTo: false).get();
    expect(unread.docs, isEmpty);
    // Sin no leídas, el botón queda desactivado.
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Marcar como leídas')).onPressed,
        isNull);
  });

  testWidgets('tocar una notificación la marca como leída y abre la cita', (tester) async {
    await seed('n1');
    await pumpPage(tester);

    await tester.tap(find.text('Título n1'));
    await tester.pumpAndSettle();

    expect(find.text('Detalle a1'), findsOneWidget);
    expect((await firestore.doc('notifications/n1').get()).data()!['leido'], isTrue);
  });

  testWidgets('sin notificaciones', (tester) async {
    await pumpPage(tester);
    expect(find.text('No tienes notificaciones'), findsOneWidget);
  });

  testWidgets('la campana del encabezado muestra las no leídas', (tester) async {
    await seed('n1');
    await seed('n2');
    await seed('n3', leido: true);
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const AppShell(location: '/reservas', child: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Notificaciones, 2 sin leer'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await firestore.doc('notifications/n1').update({'leido': true});
    await firestore.doc('notifications/n2').update({'leido': true});
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notificaciones'), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('abrir desde un push: espera a que el usuario entre a la app', (tester) async {
    AppUser? user;
    final router = GoRouter(
      initialLocation: CoreRoutes.splash,
      routes: [
        GoRoute(path: CoreRoutes.splash, builder: (context, state) => const Text('Cargando')),
        GoRoute(path: '/reservas', builder: (context, state) => const Text('Mis citas')),
        GoRoute(
          path: '/reservas/:id',
          builder: (context, state) => Text('Detalle ${state.pathParameters['id']}'),
        ),
      ],
    );
    final navigator =
        NotificationNavigator(router: router, registry: registry, currentUser: () => user);
    addTearDown(navigator.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // La app se abrió tocando el push: todavía no hay sesión.
    navigator.open({'tipo': 'cita_cancelada', 'referenciaId': 'a7'});
    await tester.pumpAndSettle();
    expect(find.text('Cargando'), findsOneWidget);
    expect(navigator.pending, isNotNull);

    // Inició sesión y el redirect la llevó al inicio: ahora sí navega.
    user = owner;
    router.go('/reservas');
    await tester.pumpAndSettle();
    expect(find.text('Detalle a7'), findsOneWidget);
    expect(navigator.pending, isNull);

    // Con la app abierta navega de una vez; si la pantalla no existe, al inicio.
    navigator.open({'tipo': 'pedido', 'referenciaId': 'o1'});
    await tester.pumpAndSettle();
    expect(find.text('Mis citas'), findsOneWidget);
  });
}
