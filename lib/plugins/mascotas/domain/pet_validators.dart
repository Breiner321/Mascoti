/// Formato de imagen aceptado para la foto de la mascota.
enum PetImageType { jpg, png }

/// Validaciones del formulario de mascota. Los límites son los mismos de
/// `validPet` en firestore.rules. Devuelven el mensaje de error o null si el
/// valor es válido.
abstract final class PetValidators {
  static const maxNombre = 40;
  static const maxRaza = 60;
  static const maxSexoDetalle = 30;
  static const maxContactoNombre = 60;
  static const maxTags = 30;
  static const maxTagLength = 40;

  static String? nombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El nombre es obligatorio';
    if (v.length > maxNombre) {
      return 'El nombre no puede superar $maxNombre caracteres';
    }
    return null;
  }

  static String? especie(Object? value) =>
      value == null ? 'Selecciona la especie' : null;

  static String? raza(String? value) => (value?.trim().length ?? 0) > maxRaza
      ? 'La raza no puede superar $maxRaza caracteres'
      : null;

  /// Con sexo "Otro (especifique)" el detalle es obligatorio.
  static String? sexoDetalle(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Especifica el sexo';
    if (v.length > maxSexoDetalle) {
      return 'Máximo $maxSexoDetalle caracteres';
    }
    return null;
  }

  static String? fechaNacimiento(DateTime? value, DateTime now) =>
      value != null && value.isAfter(now)
          ? 'La fecha de nacimiento no puede ser futura'
          : null;

  /// Valor nuevo para una lista de alergias o condiciones.
  static String? tag(String value, List<String> current) {
    final v = value.trim();
    if (v.isEmpty) return 'Escribe un valor para agregarlo';
    if (v.length > maxTagLength) {
      return 'Máximo $maxTagLength caracteres';
    }
    if (current.any((t) => t.toLowerCase() == v.toLowerCase())) {
      return 'Ya está en la lista';
    }
    if (current.length >= maxTags) return 'Máximo $maxTags elementos';
    return null;
  }

  /// El contacto de emergencia es opcional, pero si se llena un campo el
  /// otro es obligatorio.
  static String? contactoNombre(String? nombre, String? telefono) {
    final n = nombre?.trim() ?? '';
    final t = telefono?.trim() ?? '';
    if (n.isEmpty && t.isNotEmpty) return 'Escribe el nombre del contacto';
    if (n.length > maxContactoNombre) {
      return 'El nombre no puede superar $maxContactoNombre caracteres';
    }
    return null;
  }

  static String? contactoTelefono(String? telefono, String? nombre) {
    final t = telefono?.trim() ?? '';
    final n = nombre?.trim() ?? '';
    if (t.isEmpty) {
      return n.isEmpty ? null : 'Escribe el teléfono del contacto';
    }
    if (!RegExp(r'^\d{10}$').hasMatch(t)) {
      return 'El teléfono debe tener 10 dígitos';
    }
    return null;
  }

  /// Tipo de la imagen elegida, o null si no es JPG ni PNG.
  static PetImageType? imageType(String fileName, String? mimeType) {
    final mime = mimeType?.toLowerCase();
    if (mime == 'image/jpeg' || mime == 'image/jpg') return PetImageType.jpg;
    if (mime == 'image/png') return PetImageType.png;
    final name = fileName.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return PetImageType.jpg;
    if (name.endsWith('.png')) return PetImageType.png;
    return null;
  }
}
