import '../auth/domain/app_user.dart';
import '../kernel/plugin_registry.dart';
import 'domain/app_notification.dart';

/// Pantalla que corresponde a una notificación (`data: {tipo, referenciaId}`),
/// o null si no hay una pantalla específica.
///
/// El core no importa plugins: las rutas se escriben aquí tal cual las
/// declaran los plugins reservas (`/reservas/:id`) y mascotas
/// (`/mascotas/perfil/:petId`).
String? notificationRoute(String? tipo, String? referenciaId) {
  final type = NotificationType.fromValue(tipo);
  final id = referenciaId ?? '';
  if (type == null || id.isEmpty || id.contains('/')) return null;
  if (type.isAppointment) return '/reservas/$id';
  if (type == NotificationType.vacuna) return '/mascotas/perfil/$id';
  return null;
}

/// Dónde navegar al tocar una notificación: la pantalla de [route] si existe
/// y el rol la puede ver; si no, el inicio del rol.
String resolveNotificationTarget({
  required String? route,
  required PluginRegistry registry,
  required UserRole role,
}) {
  if (route != null && registry.hasRoute(route)) {
    final plugin = registry.pluginForLocation(route);
    if (plugin != null && plugin.roles.contains(role)) return route;
  }
  return registry.homeFor(role);
}
