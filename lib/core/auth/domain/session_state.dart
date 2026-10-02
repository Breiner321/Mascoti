import 'app_user.dart';

/// Estado de sesión que decide a qué pantalla va el usuario (ver app_router).
sealed class SessionState {
  const SessionState();
}

/// Esperando a Firebase Auth o al perfil en Firestore.
final class SessionLoading extends SessionState {
  const SessionLoading();
}

/// Error al leer la sesión o el perfil.
final class SessionError extends SessionState {
  const SessionError(this.message);
  final String message;
}

/// Sin sesión de Firebase.
final class SignedOut extends SessionState {
  const SignedOut();
}

/// Autenticado con Google pero sin documento `users/{uid}` (RF-01).
final class NeedsRegistration extends SessionState {
  const NeedsRegistration({
    required this.uid,
    required this.email,
    this.displayName,
  });

  final String uid;
  final String email;
  final String? displayName;
}

/// Cuenta con `estado: 'suspendido'` (RF-02).
final class Suspended extends SessionState {
  const Suspended();
}

/// Sesión completa con perfil.
final class SignedIn extends SessionState {
  const SignedIn(this.user);
  final AppUser user;
}
