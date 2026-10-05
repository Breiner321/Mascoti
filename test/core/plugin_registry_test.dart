import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/router/core_routes.dart';

import 'fake_plugins.dart';

void main() {
  group('PluginRegistry', () {
    test('rechaza ids duplicados', () {
      expect(
        () => PluginRegistry([
          FakePlugin('a', roles: {UserRole.dueno}),
          FakePlugin('a', roles: {UserRole.clinica}),
        ]),
        throwsStateError,
      );
    });

    test('rechaza rutas fuera del prefijo del plugin', () {
      expect(
        () => PluginRegistry([
          FakePlugin('a', roles: {UserRole.dueno}, paths: ['/otra']),
        ]),
        throwsStateError,
      );
    });

    test('rechaza plugins que usan un prefijo del core', () {
      expect(
        () => PluginRegistry([FakePlugin('perfil', roles: {UserRole.dueno})]),
        throwsStateError,
      );
    });

    test('ordena las pestañas y filtra por rol', () {
      final registry = PluginRegistry([
        FakePlugin('b', roles: {UserRole.dueno}, tabs: [tab('/b', 20)]),
        FakePlugin('a', roles: {UserRole.dueno}, tabs: [tab('/a', 10)]),
        FakePlugin('c', roles: {UserRole.clinica}, tabs: [tab('/c', 0)]),
      ]);

      expect(
        registry.destinationsFor(UserRole.dueno).map((d) => d.path),
        ['/a', '/b'],
      );
      expect(registry.homeFor(UserRole.dueno), '/a');
      expect(registry.homeFor(UserRole.clinica), '/c');
    });

    test('homeFor usa /inicio si el rol no tiene pestañas', () {
      final registry = PluginRegistry([FakePlugin('a', roles: {UserRole.dueno})]);
      expect(registry.homeFor(UserRole.clinica), CoreRoutes.home);
    });

    test('pluginForLocation reconoce subrutas pero no prefijos parciales', () {
      final registry = PluginRegistry([
        FakePlugin('chat', roles: {UserRole.dueno}, paths: ['/chat', '/chat/sala']),
      ]);
      expect(registry.pluginForLocation('/chat/sala')?.id, 'chat');
      expect(registry.pluginForLocation('/chatbot'), isNull);
      expect(registry.isEnabled('chat'), isTrue);
      expect(registry.isEnabled('tienda'), isFalse);
    });

    test('hasRoute reconoce rutas declaradas, parámetros y query', () {
      final registry = PluginRegistry([
        FakePlugin('reservas',
            roles: {UserRole.dueno}, paths: ['/reservas', '/reservas/:id']),
      ]);
      expect(registry.hasRoute('/reservas'), isTrue);
      expect(registry.hasRoute('/reservas/abc'), isTrue);
      expect(registry.hasRoute('/reservas?categoria=consulta'), isTrue);
      expect(registry.hasRoute('/reservas/abc/editar'), isFalse);
      expect(registry.hasRoute('/tienda'), isFalse);
    });
  });
}
