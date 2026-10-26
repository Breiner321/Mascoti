/// Rutas que usan las pantallas de la clínica en RF-14. Las del plugin
/// clinica se usan por texto (sin importar ese plugin).
abstract final class ClinicAppointmentRoutes {
  /// Detalle de la cita (el plugin decide la pantalla según el rol).
  static String detail(String appointmentId) => '/reservas/$appointmentId';

  /// Perfil del paciente con su historial médico (plugin clinica).
  static String patient(String petId) => '/clinica/pacientes/$petId';

  /// Formulario de consulta del plugin clinica, con la cita prellenada.
  static String newRecord(String petId, String appointmentId) =>
      '/clinica/pacientes/$petId/consulta?appointmentId=$appointmentId';
}
