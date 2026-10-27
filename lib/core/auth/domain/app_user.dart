import 'package:flutter/foundation.dart';

enum UserRole {
  dueno('Dueño de Mascota'),
  clinica('Clínica Veterinaria');

  const UserRole(this.label);

  /// Texto para la UI.
  final String label;

  /// Valor guardado en Firestore (`users.role`).
  String get value => name;

  static UserRole? fromValue(String? value) => switch (value) {
        'dueno' => UserRole.dueno,
        'clinica' => UserRole.clinica,
        _ => null,
      };
}

enum UserStatus { activo, suspendido }

/// Documento `users/{uid}` (ver docs/modelo-datos.md).
@immutable
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.photoUrl,
    this.estado = UserStatus.activo,
    this.clinicId,
    this.onboardingVisto = false,
    this.nombre,
    this.telefono,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    final role = UserRole.fromValue(map['role'] as String?);
    if (role == null) {
      throw FormatException('users/$uid tiene un rol inválido: ${map['role']}');
    }
    return AppUser(
      uid: uid,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoURL'] as String?,
      role: role,
      estado: map['estado'] == 'suspendido'
          ? UserStatus.suspendido
          : UserStatus.activo,
      clinicId: map['clinicId'] as String?,
      onboardingVisto: map['onboardingVisto'] == true,
      nombre: _nonEmpty(map['nombre']),
      telefono: _nonEmpty(map['telefono']),
    );
  }

  static String? _nonEmpty(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  /// Texto cuando no hay ningún nombre (nunca se muestra el correo).
  static const fallbackName = 'Usuario';

  final String uid;

  /// Correo de Google: para identificar la cuenta, no para mostrar a la persona.
  final String email;

  /// Nombre de la cuenta de Google. Solo de respaldo: usa [nombreVisible].
  final String displayName;
  final String? photoUrl;
  final UserRole role;
  final UserStatus estado;
  final String? clinicId;

  /// El dueño ya vio el onboarding de 3 pasos (RF-01 paso 14).
  final bool onboardingVisto;

  /// Nombre completo que escribió el dueño (Cambio 1). null en clínicas y en
  /// dueños registrados antes del cambio (deben completar su perfil).
  final String? nombre;

  /// Teléfono de 10 dígitos del dueño.
  final String? telefono;

  /// ÚNICA fuente del nombre de una persona en la app: `nombre` → nombre de
  /// Google → "Usuario". Nunca el correo. Para una clínica, el nombre que se
  /// muestra es el comercial (`displayNameProvider`).
  String get nombreVisible {
    final n = nombre;
    if (n != null) return n;
    final google = displayName.trim();
    return google.isEmpty ? fallbackName : google;
  }

  /// Dueño sin nombre propio: debe pasar por "Completa tu perfil".
  bool get needsProfileCompletion => role == UserRole.dueno && nombre == null;
}
