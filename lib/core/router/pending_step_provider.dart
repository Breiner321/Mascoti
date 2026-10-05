import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../kernel/plugin_registry.dart';

/// Paso obligatorio pendiente del usuario con sesión, aportado por algún
/// plugin de su rol mediante [MascotiPlugin.requiredStep] (p. ej. la clínica
/// en estado 'incompleto' debe ir a su perfil de atención).
///
/// El core no sabe qué significa cada paso: solo combina lo que dicen los
/// plugins. `AsyncLoading` mientras algún plugin no ha respondido; el primer
/// paso no nulo gana. Si un plugin falla al calcularlo, no se bloquea la app.
final pendingStepProvider = Provider<AsyncValue<String?>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const AsyncData(null);

  final registry = ref.watch(pluginRegistryProvider);
  for (final plugin in registry.pluginsFor(user.role)) {
    final listenable = plugin.requiredStep(user);
    if (listenable == null) continue;

    final AsyncValue<String?> step = ref.watch(listenable);
    if (step.isLoading && !step.hasValue) return const AsyncLoading();
    final path = step.hasValue ? step.value : null;
    if (path != null) return AsyncData(path);
  }
  return const AsyncData(null);
});
