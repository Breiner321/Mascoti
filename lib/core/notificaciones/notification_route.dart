import '../auth/domain/app_user.dart';
import '../kernel/plugin_registry.dart';
import 'domain/app_notification.dart';

/// Pantalla que corresponde a una notificación (`data: {tipo, referenciaId}`),
/// o null si no hay una pantalla específica.
///
/// El core no importa plugins: las rutas se escriben aquí tal cual las
/// declaran los plugins reservas (`/reservas/:id`), mascotas
/// (`/mascotas/perfil/:petId`) y chat (`/chat/:chatId`).
String? notificationRoute(String? tipo, String? referenciaId) {
  final type = NotificationType.fromValue(tipo);
  final id = referenciaId ?? '';
  if (type == null || id.isEmpty || id.contains('/')) return null;
  if (type.isAppointment) return '/reservas/$id';
  if (type == NotificationType.vacuna) return '/mascotas/perfil/$id';
  if (type == NotificationType.mensaje) return '/chat/$id';
  return null;
}

/// Con la app abierta: el push de un mensaje no se muestra si esa
/// conversación ya está en pantalla ([location]); los mensajes llegan solos
/// y se marcan como leídos (RF-15).
bool isNotificationScreenOpen(Map<String, String> data, String location) {
  if (NotificationType.fromValue(data['tipo']) != NotificationType.mensaje) return false;
  final route = notificationRoute(data['tipo'], data['referenciaId']);
  return route != null && route == location;
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
