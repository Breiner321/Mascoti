/// Rutas que pertenecen al kernel (no a un plugin).
abstract final class CoreRoutes {
  static const splash = '/cargando';
  static const welcome = '/bienvenida';
  static const registration = '/registro';
  static const suspended = '/cuenta-suspendida';

  /// Respaldo si un rol no tiene ninguna pestaña de plugin.
  static const home = '/inicio';
  static const profile = '/perfil';

  /// Centro de notificaciones (RF-13).
  static const notifications = '/notificaciones';

  /// Pantallas sin barra de navegación (antes de tener sesión completa).
  static const outsideShell = {splash, welcome, registration, suspended};

  /// Pantallas del core dentro del AppShell.
  static const insideShell = {home, profile, notifications};

  static const all = {...outsideShell, ...insideShell};
}
