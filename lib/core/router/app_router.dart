import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../auth/domain/session_state.dart';
import '../auth/presentation/complete_profile_page.dart';
import '../auth/presentation/edit_profile_page.dart';
import '../auth/presentation/profile_page.dart';
import '../auth/presentation/registration_page.dart';
import '../auth/presentation/splash_page.dart';
import '../auth/presentation/suspended_page.dart';
import '../auth/presentation/welcome_page.dart';
import '../kernel/plugin_registry.dart';
import '../notificaciones/presentation/notifications_page.dart';
import '../widgets/app_shell.dart';
import '../widgets/module_placeholder.dart';
import 'core_routes.dart';
import 'navigator_keys.dart';
import 'pending_step_provider.dart';
import 'redirect.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final registry = ref.watch(pluginRegistryProvider);

  // go_router vuelve a evaluar `redirect` cada vez que cambia la sesión o el
  // paso obligatorio pendiente.
  final session = ValueNotifier<SessionState>(ref.read(sessionProvider));
  final pendingStep = ValueNotifier<AsyncValue<String?>>(ref.read(pendingStepProvider));
  ref.listen<SessionState>(sessionProvider, (_, next) => session.value = next);
  ref.listen<AsyncValue<String?>>(
    pendingStepProvider,
    (_, next) => pendingStep.value = next,
  );

  // Las rutas de plugins con parentNavigatorKey = rootNavigatorKey son de
  // pantalla completa: go_router no permite declararlas dentro del ShellRoute,
  // así que se montan al primer nivel (sin encabezado ni barra inferior).
  bool isFullScreen(RouteBase route) =>
      route is GoRoute && route.parentNavigatorKey == rootNavigatorKey;
  final pluginRoutes = registry.routes;

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: CoreRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: Listenable.merge([session, pendingStep]),
    redirect: (context, state) => resolveRedirect(
      session: session.value,
      location: state.matchedLocation,
      registry: registry,
      pendingStep: pendingStep.value,
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
      GoRoute(
        path: CoreRoutes.completeProfile,
        builder: (context, state) => const CompleteProfilePage(),
      ),
      ...pluginRoutes.where(isFullScreen),
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
          GoRoute(
            path: CoreRoutes.editProfile,
            builder: (context, state) => const EditProfilePage(),
          ),
          GoRoute(
            path: CoreRoutes.notifications,
            builder: (context, state) => const NotificationsPage(),
          ),
          ...pluginRoutes.where((route) => !isFullScreen(route)),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    session.dispose();
    pendingStep.dispose();
  });
  return router;
});
