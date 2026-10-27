/// Rutas que pertenecen al kernel (no a un plugin).
abstract final class CoreRoutes {
  static const splash = '/cargando';
  static const welcome = '/bienvenida';
  static const registration = '/registro';
  static const suspended = '/cuenta-suspendida';

  /// Dueño sin nombre propio (registrado antes del Cambio 1): obligatoria.
  static const completeProfile = '/completar-perfil';

  /// Respaldo si un rol no tiene ninguna pestaña de plugin.
  static const home = '/inicio';
  static const profile = '/perfil';

  /// El dueño edita su nombre y teléfono (Cambio 1).
  static const editProfile = '/perfil/editar';

  /// Tema, alto contraste, tamaño de texto y animaciones (Cambio 3).
  static const accessibility = '/perfil/accesibilidad';

  /// Centro de notificaciones (RF-13).
  static const notifications = '/notificaciones';

  /// Pantallas sin barra de navegación (antes de tener sesión completa).
  static const outsideShell = {splash, welcome, registration, suspended, completeProfile};

  /// Pantallas del core dentro del AppShell.
  static const insideShell = {home, profile, editProfile, accessibility, notifications};

  static const all = {...outsideShell, ...insideShell};
}
