import '../auth/domain/session_state.dart';
import '../kernel/plugin_registry.dart';
import 'core_routes.dart';

/// Decide a dónde debe ir el usuario según su sesión.
/// Devuelve null si puede quedarse en [location]. Función pura: ver test/core/redirect_test.dart.
String? resolveRedirect({
  required SessionState session,
  required String location,
  required PluginRegistry registry,
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
