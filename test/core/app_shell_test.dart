import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/shop_providers.dart';
import 'package:mascoti/core/domain/cart_item.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/core/widgets/app_shell.dart';

import 'fake_plugins.dart';

void main() {
  const owner = AppUser(
    uid: 'u1',
    email: 'ana@correo.co',
    displayName: 'Ana',
    role: UserRole.dueno,
  );
  const clinic = AppUser(
    uid: 'v1',
    email: 'vet@correo.co',
    displayName: 'Vet',
    role: UserRole.clinica,
  );

  Future<void> pumpShell(
    WidgetTester tester, {
    required AppUser user,
    required List<String> plugins,
    List<CartItem> cart = const [],
  }) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(user),
            cartProvider.overrideWith((ref) => Stream.value(cart)),
            pluginRegistryProvider.overrideWithValue(PluginRegistry([
              for (final id in plugins)
                FakePlugin(id, roles: {UserRole.dueno, UserRole.clinica}),
            ])),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AppShell(location: '/mascotas', child: SizedBox()),
          ),
        ),
      );

  final cart = find.byTooltip('Carrito');
  final sos = find.text('SOS');

  testWidgets('siempre muestra el logo y el acceso al perfil', (tester) async {
    await pumpShell(tester, user: owner, plugins: ['mascotas']);
    expect(find.text('Mascoti'), findsOneWidget);
    expect(find.byTooltip('Perfil'), findsOneWidget);
  });

  testWidgets('sin tienda ni sos no hay carrito ni SOS', (tester) async {
    await pumpShell(tester, user: owner, plugins: ['mascotas']);
    expect(cart, findsNothing);
    expect(sos, findsNothing);
  });

  testWidgets('el dueño ve carrito y SOS si sus plugins están activos',
      (tester) async {
    await pumpShell(tester, user: owner, plugins: ['mascotas', 'tienda', 'sos']);
    expect(cart, findsOneWidget);
    expect(sos, findsOneWidget);
  });

  testWidgets('la clínica nunca ve carrito ni SOS', (tester) async {
    await pumpShell(tester, user: clinic, plugins: ['clinica', 'tienda', 'sos']);
    expect(cart, findsNothing);
    expect(sos, findsNothing);
  });

  testWidgets('el carrito muestra cuántas unidades tiene (RF-12)', (tester) async {
    const item = CartItem(productId: 'p1', clinicId: 'c1', nombre: 'Collar', precio: 1000, cantidad: 2);
    await pumpShell(
      tester,
      user: owner,
      plugins: ['mascotas', 'tienda'],
      cart: [item, item.copyWith(cantidad: 1)],
    );
    await tester.pump();
    expect(find.byTooltip('Carrito, 3 productos'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
