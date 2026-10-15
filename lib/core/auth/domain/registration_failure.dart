import 'package:flutter/foundation.dart';

enum RegistrationFailureKind {
  /// La cuenta ya tenía users/{uid} (RF-01, flujo alterno).
  alreadyExists,

  /// Sin respuesta en 10 s o sin conexión (RF-01, flujo alterno).
  network,

  /// El servidor rechazó los datos; [RegistrationFailure.serverMessage] dice por qué.
  invalid,

  /// Falta configurar Supabase en este equipo (env/dev.json).
  notConfigured,

  unknown,
}

/// Error de `completar-registro` con el texto que la UI debe mostrar.
@immutable
class RegistrationFailure implements Exception {
  const RegistrationFailure(this.kind, {this.serverMessage});

  final RegistrationFailureKind kind;
  final String? serverMessage;

  String get message => switch (kind) {
        RegistrationFailureKind.alreadyExists =>
          'Esta cuenta ya está registrada. Iniciando sesión...',
        RegistrationFailureKind.network =>
          'No se pudo completar el registro. Verifica tu conexión',
        RegistrationFailureKind.invalid =>
          serverMessage ?? 'Revisa los datos del formulario',
        RegistrationFailureKind.notConfigured =>
          'El registro no está disponible en esta versión de la app',
        RegistrationFailureKind.unknown => 'No se pudo completar el registro',
      };

  bool get canRetry =>
      kind == RegistrationFailureKind.network || kind == RegistrationFailureKind.unknown;

  @override
  String toString() => 'RegistrationFailure($kind, $serverMessage)';
}
