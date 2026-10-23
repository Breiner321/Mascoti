/// Rutas del lado dueño del plugin reservas (RF-14).
abstract final class OwnerBookingRoutes {
  /// Mis citas (pestaña "Citas").
  static const list = '/reservas';

  /// Agendar: `?clinicId=…` (desde el directorio) y `?categoria=…` (accesos
  /// "Servicios" del home). Sin clinicId se elige primero la clínica.
  static const newAppointment = '/reservas/nueva';

  static String newFor({String? clinicId, String? categoria}) => Uri(
        path: newAppointment,
        queryParameters: {
          if (clinicId != null) 'clinicId': clinicId,
          if (categoria != null) 'categoria': categoria,
        },
      ).toString();

  /// Detalle; es la ruta a la que llevan las notificaciones (RF-13).
  static const detailPattern = '/reservas/:id';
  static String detail(String appointmentId) => '/reservas/$appointmentId';

  /// Directorio con mapa (plugin directorio, por ruta).
  static const map = '/directorio';

  /// Registro de mascota (plugin mascotas, por ruta).
  static const newPet = '/mascotas/nueva';
}
