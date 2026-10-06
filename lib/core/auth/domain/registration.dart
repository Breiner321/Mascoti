import 'package:flutter/foundation.dart';

import 'app_user.dart';

/// Datos adicionales cuando el rol es Clínica (RF-01, paso 9).
@immutable
class ClinicRegistration {
  const ClinicRegistration({
    required this.nombre,
    required this.telefono,
    required this.direccion,
    required this.lat,
    required this.lng,
  });

  final String nombre;
  final String telefono;
  final String direccion;

  /// Coordenadas de la dirección escogida en OpenStreetMap (obligatorias).
  final double lat;
  final double lng;

  Map<String, dynamic> toMap() => {
        'nombre': nombre.trim(),
        'telefono': telefono.trim(),
        'direccion': direccion.trim(),
        'lat': lat,
        'lng': lng,
      };
}

/// Payload de la Callable Function `completarRegistro`.
@immutable
class RegistrationRequest {
  const RegistrationRequest.owner()
      : role = UserRole.dueno,
        clinic = null;

  const RegistrationRequest.clinic(ClinicRegistration data)
      : role = UserRole.clinica,
        clinic = data;

  final UserRole role;
  final ClinicRegistration? clinic;

  Map<String, dynamic> toMap() {
    final clinicData = clinic;
    return {
      'role': role.value,
      if (clinicData != null) 'clinica': clinicData.toMap(),
    };
  }
}

/// Validaciones de RF-01 (paso 10). Devuelven el mensaje de error o null.
abstract final class RegistrationValidators {
  static final RegExp _phone = RegExp(r'^\d{10}$');

  static String? clinicName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'El nombre comercial es obligatorio';
    if (text.length < 3) return 'Mínimo 3 caracteres';
    return null;
  }

  static String? phone(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'El teléfono es obligatorio';
    if (!_phone.hasMatch(text)) return 'Debe tener 10 dígitos numéricos';
    return null;
  }

}
