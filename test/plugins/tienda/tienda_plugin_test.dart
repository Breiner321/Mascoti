import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/kernel/plugin_manifest.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/notificaciones/notification_route.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/tienda/presentation/dueno/store_page.dart';
import 'package:mascoti/plugins/tienda/tienda_plugin.dart';
import 'package:mascoti/plugins/tienda/tienda_routes.dart';

import '../../a11y.dart';

void main() {
  const plugin = TiendaPlugin();

  test('pestaña "Tienda" para el dueño e "Inventario" para la clínica', () {
    final owner = plugin.destinations(UserRole.dueno).single;
    final clinic = plugin.destinations(UserRole.clinica).single;
    expect(owner.label, 'Tienda');
    expect(owner.path, '/tienda');
    expect(clinic.label, 'Inventario');
    expect(clinic.path, '/tienda/inventario');
  });

  test('declara las rutas acordadas', () {
    expect(plugin.routes().cast<GoRoute>().map((r) => r.path), [
      '/tienda',
      '/tienda/producto/:id',
      '/tienda/carrito',
      '/tienda/pedidos',
      '/tienda/pedidos/:id',
      '/tienda/inventario',
      '/tienda/clinica/pedidos',
    ]);
    expect(TiendaRoutes.product('c 1', 'p1'), '/tienda/producto/p1?clinicId=c+1');
  });

  test('está registrado y las notificaciones de pedidos llevan a sus pantallas', () {
    final registry = PluginRegistry(enabledPlugins);
    expect(registry.isEnabled('tienda'), isTrue);
    // El ícono del carrito del encabezado.
    expect(registry.hasRoute('/tienda/carrito'), isTrue);
    for (final role in UserRole.values) {
      final route = notificationRoute(role == UserRole.dueno ? 'pedido' : 'pedido_nuevo', 'o1');
      expect(resolveNotificationTarget(route: route, registry: registry, role: role), route);
    }
    final owner = registry.destinationsFor(UserRole.dueno).map((d) => d.label).toList();
    expect(owner.indexOf('Tienda'), owner.indexOf('Citas') - 1);
  });

  testWidgets('la pantalla provisional es accesible', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: StorePage())));
    expect(find.text('Tienda'), findsOneWidget);
    await expectAccessible(tester);
  });
}
