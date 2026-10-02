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
    );
  }

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final UserRole role;
  final UserStatus estado;
  final String? clinicId;
}
