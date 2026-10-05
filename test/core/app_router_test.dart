import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/session_state.dart';
import 'package:mascoti/core/kernel/plugin_manifest.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/router/app_router.dart';
import 'package:mascoti/core/router/pending_step_provider.dart';

void main() {
  // go_router valida la configuración (navigator keys, rutas duplicadas…) al
  // construirse. Esta prueba lo hace con los plugins reales del manifiesto.
  test('el router se construye con los plugins habilitados', () {
    final container = ProviderContainer(
      overrides: [
        pluginRegistryProvider.overrideWithValue(PluginRegistry(enabledPlugins)),
        sessionProvider.overrideWithValue(const SignedOut()),
        pendingStepProvider.overrideWithValue(const AsyncData(null)),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(routerProvider), isA<GoRouter>());
  });
}
