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

/// Datos del dueño (Cambio 1): nombre real y teléfono.
@immutable
class OwnerRegistration {
  const OwnerRegistration({required this.nombre, required this.telefono});

  final String nombre;
  final String telefono;

  Map<String, dynamic> toMap() => {
        'nombre': RegistrationValidators.normalizeName(nombre),
        'telefono': telefono.trim(),
      };
}

/// Payload de la Edge Function `completar-registro`.
@immutable
class RegistrationRequest {
  const RegistrationRequest.owner(OwnerRegistration data)
      : role = UserRole.dueno,
        owner = data,
        clinic = null;

  const RegistrationRequest.clinic(ClinicRegistration data)
      : role = UserRole.clinica,
        owner = null,
        clinic = data;

  final UserRole role;
  final OwnerRegistration? owner;
  final ClinicRegistration? clinic;

  Map<String, dynamic> toMap() {
    final ownerData = owner;
    final clinicData = clinic;
    return {
      'role': role.value,
      if (ownerData != null) 'dueno': ownerData.toMap(),
      if (clinicData != null) 'clinica': clinicData.toMap(),
    };
  }
}

/// Validaciones de RF-01 (paso 10). Devuelven el mensaje de error o null.
abstract final class RegistrationValidators {
  static final RegExp _phone = RegExp(r'^\d{10}$');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Largo del nombre completo del dueño (igual que firestore.rules y
  /// supabase/functions/_shared/validacion.ts).
  static const minOwnerName = 3;
  static const maxOwnerName = 60;

  /// Quita espacios de los extremos y deja uno solo entre palabras.
  static String normalizeName(String value) => value.trim().replaceAll(_spaces, ' ');

  static String? ownerName(String? value) {
    final text = normalizeName(value ?? '');
    if (text.isEmpty) return 'El nombre completo es obligatorio';
    if (text.length < minOwnerName) return 'Mínimo $minOwnerName caracteres';
    if (text.length > maxOwnerName) return 'Máximo $maxOwnerName caracteres';
    return null;
  }

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
