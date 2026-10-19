import '../../../core/domain/medical_record.dart';

/// Validaciones del formulario de consulta (registros médicos). Los límites
/// son los de firestore.rules ([MedicalRecordLimits]). Devuelven el mensaje
/// de error o null si el valor es válido.
abstract final class MedicalRecordValidators {
  static const allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

  static String? diagnostico(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El diagnóstico es obligatorio';
    if (v.length > MedicalRecordLimits.maxDiagnostico) {
      return 'El diagnóstico no puede superar ${MedicalRecordLimits.maxDiagnostico} caracteres';
    }
    return null;
  }

  static String? tratamiento(String? value) =>
      (value?.trim().length ?? 0) > MedicalRecordLimits.maxTratamiento
          ? 'El tratamiento no puede superar ${MedicalRecordLimits.maxTratamiento} caracteres'
          : null;

  /// La fecha de la consulta no puede ser futura.
  static String? fecha(DateTime? value, DateTime now) {
    if (value == null) return 'Selecciona la fecha de la consulta';
    if (_day(value).isAfter(_day(now))) return 'La fecha no puede ser futura';
    return null;
  }

  static String? vacunaNombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El nombre de la vacuna es obligatorio';
    if (v.length > MedicalRecordLimits.maxVacunaNombre) {
      return 'Máximo ${MedicalRecordLimits.maxVacunaNombre} caracteres';
    }
    return null;
  }

  static String? lote(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El lote es obligatorio';
    if (v.length > MedicalRecordLimits.maxLote) {
      return 'Máximo ${MedicalRecordLimits.maxLote} caracteres';
    }
    return null;
  }

  static String? fechaAplicacion(DateTime? value, DateTime now) {
    if (value == null) return 'Selecciona la fecha de aplicación';
    if (_day(value).isAfter(_day(now))) return 'La fecha de aplicación no puede ser futura';
    return null;
  }

  /// Opcional; si se indica, debe ser posterior a la aplicación.
  static String? fechaProximaDosis(DateTime? value, DateTime? aplicacion) {
    if (value == null || aplicacion == null) return null;
    if (!_day(value).isAfter(_day(aplicacion))) {
      return 'La próxima dosis debe ser posterior a la aplicación';
    }
    return null;
  }

  /// Archivo adjunto antes de subirlo: tipo y tamaño.
  static String? adjunto({required String fileName, required int bytes}) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    if (!allowedExtensions.contains(ext)) {
      return 'Solo se permiten imágenes JPG o PNG y archivos PDF.';
    }
    if (bytes > MedicalRecordLimits.maxAdjuntoBytes) {
      return 'El archivo supera el máximo de 10 MB.';
    }
    return null;
  }

  static AttachmentType attachmentType(String fileName) =>
      fileName.toLowerCase().endsWith('.pdf') ? AttachmentType.pdf : AttachmentType.imagen;

  /// Nombre para guardar en el registro (máx. 120 caracteres, conserva la
  /// extensión).
  static String displayName(String fileName) {
    const max = MedicalRecordLimits.maxAdjuntoNombre;
    if (fileName.length <= max) return fileName;
    final dot = fileName.lastIndexOf('.');
    final ext = dot > 0 ? fileName.substring(dot) : '';
    return '${fileName.substring(0, max - ext.length)}$ext';
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
