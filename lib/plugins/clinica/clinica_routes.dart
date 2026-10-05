/// Rutas del plugin clinica.
abstract final class ClinicaRoutes {
  static const agenda = '/clinica';
  static const services = '/clinica/servicios';

  /// Perfil de atención (RF-04). Obligatorio mientras la clínica esté
  /// 'incompleto'.
  static const setup = '/clinica/perfil-atencion';
}
