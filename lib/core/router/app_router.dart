import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../auth/domain/session_state.dart';
import '../auth/presentation/profile_page.dart';
import '../auth/presentation/registration_page.dart';
import '../auth/presentation/splash_page.dart';
import '../auth/presentation/suspended_page.dart';
import '../auth/presentation/welcome_page.dart';
import '../kernel/plugin_registry.dart';
import '../widgets/app_shell.dart';
import '../widgets/module_placeholder.dart';
import 'core_routes.dart';
import 'redirect.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Navegador raíz: los plugins lo usan con `parentNavigatorKey` para abrir
/// pantallas a pantalla completa (sin barra inferior), p. ej. un chat.
GlobalKey<NavigatorState> get rootNavigatorKey => _rootNavigatorKey;

final routerProvider = Provider<GoRouter>((ref) {
  final registry = ref.watch(pluginRegistryProvider);

  // go_router vuelve a evaluar `redirect` cada vez que cambia la sesión.
  final session = ValueNotifier<SessionState>(ref.read(sessionProvider));
  ref.listen<SessionState>(sessionProvider, (_, next) => session.value = next);

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: CoreRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: session,
    redirect: (context, state) => resolveRedirect(
      session: session.value,
      location: state.matchedLocation,
      registry: registry,
    ),
    routes: [
      GoRoute(
        path: CoreRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: CoreRoutes.welcome,
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        path: CoreRoutes.registration,
        builder: (context, state) => const RegistrationPage(),
      ),
      GoRoute(
        path: CoreRoutes.suspended,
        builder: (context, state) => const SuspendedPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: CoreRoutes.home,
            builder: (context, state) => const ModulePlaceholder(
              title: 'Inicio',
              description: 'No hay módulos habilitados para tu rol.',
            ),
          ),
          GoRoute(
            path: CoreRoutes.profile,
            builder: (context, state) => const ProfilePage(),
          ),
          ...registry.routes,
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    session.dispose();
  });
  return router;
});
