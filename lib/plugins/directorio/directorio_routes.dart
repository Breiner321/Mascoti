/// Rutas del plugin directorio (RF-09).
abstract final class DirectorioRoutes {
  static const map = '/directorio';

  static const clinicPattern = '/directorio/clinica/:id';
  static String clinic(String id) => '/directorio/clinica/$id';

  /// Agendamiento (RF-14, plugin reservas). Se navega por ruta, sin importar
  /// el plugin; mientras no exista se muestra "Próximamente".
  static String schedule(String clinicId) =>
      '/reservas/nueva?clinicId=$clinicId';
}
