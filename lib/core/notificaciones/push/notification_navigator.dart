import 'dart:async';

import 'package:go_router/go_router.dart';

import '../../auth/domain/app_user.dart';
import '../../kernel/plugin_registry.dart';
import '../../router/core_routes.dart';
import '../notification_route.dart';

/// Abre la pantalla de una notificación tocada (RF-13 paso 6).
///
/// Si la app se abrió desde la notificación, el toque llega antes de que
/// termine el inicio de sesión: se guarda y se navega cuando el usuario ya
/// está dentro de la app (fuera del splash, la bienvenida o el registro).
class NotificationNavigator {
  NotificationNavigator({
    required GoRouter router,
    required PluginRegistry registry,
    required AppUser? Function() currentUser,
  })  : _router = router,
        _registry = registry,
        _currentUser = currentUser {
    _router.routerDelegate.addListener(_onRouteChanged);
  }

  final GoRouter _router;
  final PluginRegistry _registry;
  final AppUser? Function() _currentUser;

  Map<String, String>? _pending;

  /// Toque pendiente (para pruebas).
  Map<String, String>? get pending => _pending;

  void open(Map<String, String> data) {
    _pending = data;
    flush();
  }

  /// Navega si hay un toque pendiente y el usuario ya entró a la app.
  void flush() {
    final data = _pending;
    final user = _currentUser();
    if (data == null || user == null) return;
    if (_router.routerDelegate.currentConfiguration.isEmpty) return;
    // Pantalla de arriba, también si se abrió con push.
    final location = _router.state.uri.path;
    if (CoreRoutes.outsideShell.contains(location)) return;

    _pending = null;
    final target = resolveNotificationTarget(
      route: notificationRoute(data['tipo'], data['referenciaId']),
      registry: _registry,
      role: user.role,
    );
    if (target != location) _router.push(target);
  }

  /// Fuera del aviso del router, para no navegar mientras notifica.
  void _onRouteChanged() => scheduleMicrotask(flush);

  void dispose() => _router.routerDelegate.removeListener(_onRouteChanged);
}
