enum AuthFailureKind {
  suspended,
  network,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.kind);

  final AuthFailureKind kind;

  String get message => switch (kind) {
        AuthFailureKind.suspended =>
          'Tu cuenta ha sido suspendida. Contacta a soporte',
        AuthFailureKind.network =>
          'No se pudo completar el inicio de sesión. Verifica tu conexión',
        AuthFailureKind.unknown =>
          'No se pudo completar el inicio de sesión. Inténtalo de nuevo',
      };

  bool get canRetry => kind != AuthFailureKind.suspended;

  @override
  String toString() => 'AuthFailure: $kind';
}
