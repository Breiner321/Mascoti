import 'package:flutter/foundation.dart';

enum AuthFailureKind {
  /// La cuenta está deshabilitada en Firebase Auth (RF-02, cuenta suspendida).
  suspended,

  /// Sin conexión o sin respuesta en 10 s.
  network,

  /// Cualquier otro error de Google Sign-In o Firebase Auth.
  unknown,
}

/// Error del inicio de sesión con el texto que la UI debe mostrar.
@immutable
class AuthFailure implements Exception {
  const AuthFailure(this.kind);

  final AuthFailureKind kind;

  String get message => switch (kind) {
        AuthFailureKind.suspended =>
          'Tu cuenta ha sido suspendida. Contacta a soporte',
        AuthFailureKind.network =>
          'No se pudo completar el inicio de sesión. Verifica tu conexión',
        AuthFailureKind.unknown =>
          'No se pudo iniciar sesión con Google. Intenta de nuevo',
      };

  /// Una cuenta suspendida no se arregla reintentando.
  bool get canRetry => kind != AuthFailureKind.suspended;

  @override
  String toString() => 'AuthFailure($kind)';
}
