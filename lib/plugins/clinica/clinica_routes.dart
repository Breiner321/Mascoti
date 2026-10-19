/// Rutas del plugin clinica.
abstract final class ClinicaRoutes {
  static const agenda = '/clinica';
  static const services = '/clinica/servicios';

  /// Perfil de atención (RF-04). Obligatorio mientras la clínica esté
  /// 'incompleto'.
  static const setup = '/clinica/perfil-atencion';

  /// Mascotas vinculadas (registros médicos).
  static const patients = '/clinica/pacientes';
  static const patientPattern = '/clinica/pacientes/:petId';
  static const newRecordPattern = '/clinica/pacientes/:petId/consulta';
  static const recordPattern = '/clinica/pacientes/:petId/consulta/:recordId';

  static String patient(String petId) => '$patients/$petId';
  static String newRecord(String petId) => '$patients/$petId/consulta';
  static String record(String petId, String recordId) => '$patients/$petId/consulta/$recordId';
}
