import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/domain/session_state.dart';
import '../kernel/plugin_registry.dart';
import 'core_routes.dart';

/// Decide a dónde debe ir el usuario según su sesión y su paso obligatorio
/// pendiente ([pendingStep], ver pending_step_provider.dart).
/// Devuelve null si puede quedarse en [location]. Función pura: ver test/core/redirect_test.dart.
String? resolveRedirect({
  required SessionState session,
  required String location,
  required PluginRegistry registry,
  AsyncValue<String?> pendingStep = const AsyncData(null),
}) {
  String? goTo(String target) => location == target ? null : target;

  switch (session) {
    case SessionLoading():
    case SessionError():
      return goTo(CoreRoutes.splash);
    case SignedOut():
      return goTo(CoreRoutes.welcome);
    case NeedsRegistration():
      return goTo(CoreRoutes.registration);
    case Suspended():
      return goTo(CoreRoutes.suspended);
    case SignedIn(:final user):
      // Cambio 1: el dueño sin nombre propio completa su perfil antes de
      // cualquier otra pantalla (desde ahí también puede cerrar sesión).
      if (user.needsProfileCompletion) return goTo(CoreRoutes.completeProfile);

      // Mientras un plugin decide si hay un paso obligatorio, se espera en el
      // splash para no mostrar un instante pantallas que luego se bloquean.
      if (pendingStep.isLoading && !pendingStep.hasValue) {
        return goTo(CoreRoutes.splash);
      }
      final step = pendingStep.hasValue ? pendingStep.value : null;
      if (step != null) {
        // Se permite /perfil para que siempre pueda cerrar sesión (RF-03).
        final allowed = PluginRegistry.isUnder(location, step) ||
            location == CoreRoutes.profile;
        return allowed ? null : goTo(step);
      }

      final home = registry.homeFor(user.role);
      if (CoreRoutes.outsideShell.contains(location)) return goTo(home);
      if (CoreRoutes.insideShell.contains(location)) return null;

      final plugin = registry.pluginForLocation(location);
      if (plugin == null || !plugin.roles.contains(user.role)) {
        return goTo(home);
      }
      return null;
  }
}
