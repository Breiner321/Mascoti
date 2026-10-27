import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notificaciones/push/push_providers.dart';
import '../supabase/supabase_providers.dart';
import 'data/auth_repository.dart';
import 'data/registration_api.dart';
import 'domain/app_user.dart';
import 'domain/session_state.dart';

// Tipo explícito: el cierre de sesión lee el push (RF-13), que depende del
// router y este de la sesión; sin él, Dart no puede inferir el ciclo.
final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    registrationApi: RegistrationApi(ref.watch(supabaseClientProvider)?.functions),
    // RF-13: se lee al cerrar sesión (no al crear el repositorio).
    beforeSignOut: () => ref.read(pushNotificationsControllerProvider).signedOut(),
  ),
);

/// Riverpod 3 reintenta solo los providers que fallan y, mientras tanto, los
/// deja en "cargando". En la sesión eso escondería el error: se desactiva para
/// que la SplashPage muestre el mensaje con "Reintentar".
Duration? _noRetry(int retryCount, Object error) => null;

final firebaseUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
  retry: _noRetry,
);

/// autoDispose: al cerrar sesión deja de observarse y el listener se cancela.
final userProfileProvider =
    StreamProvider.autoDispose.family<AppUser?, String>(
  (ref, uid) => ref.watch(authRepositoryProvider).watchUserProfile(uid),
  retry: _noRetry,
);

/// Estado de sesión combinado: Firebase Auth + documento users/{uid}.
final sessionProvider = Provider<SessionState>((ref) {
  final authState = ref.watch(firebaseUserProvider);

  switch (authState) {
    case AsyncData(value: final firebaseUser):
      if (firebaseUser == null) return const SignedOut();

      final profile = ref.watch(userProfileProvider(firebaseUser.uid));
      switch (profile) {
        case AsyncData(value: final appUser):
          if (appUser == null) {
            return NeedsRegistration(
              uid: firebaseUser.uid,
              email: firebaseUser.email ?? '',
              displayName: firebaseUser.displayName,
            );
          }
          if (appUser.estado == UserStatus.suspendido) {
            return const Suspended();
          }
          return SignedIn(appUser);
        case AsyncError(:final error):
          return SessionError('$error');
        default:
          return const SessionLoading();
      }

    case AsyncError(:final error):
      return SessionError('$error');
    default:
      return const SessionLoading();
  }
});

/// Usuario con sesión completa, o null. Útil para los plugins.
final currentUserProvider = Provider<AppUser?>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SignedIn ? session.user : null;
});

/// Nombre comercial de la clínica [clinicId], en tiempo real.
final clinicNameProvider = StreamProvider.autoDispose.family<String?, String>(
  (ref, clinicId) => ref.watch(authRepositoryProvider).watchClinicName(clinicId),
  retry: _noRetry,
);

/// Nombre visible del usuario con sesión (Cambio 1), la única fuente para
/// mostrar a la persona en la app:
/// - dueño: [AppUser.nombreVisible] (su nombre → nombre de Google → "Usuario");
/// - clínica: el nombre comercial de `clinics/{clinicId}`, nunca el de Google.
final displayNameProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return '';
  if (user.role != UserRole.clinica) return user.nombreVisible;
  final clinicId = user.clinicId;
  final name = clinicId == null ? null : ref.watch(clinicNameProvider(clinicId)).value;
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? 'Clínica' : trimmed;
});
