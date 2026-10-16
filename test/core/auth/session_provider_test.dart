import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/auth/domain/session_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockUser extends Mock implements User {}

void main() {
  late _MockUser firebaseUser;

  setUp(() {
    firebaseUser = _MockUser();
    when(() => firebaseUser.uid).thenReturn('u1');
    when(() => firebaseUser.email).thenReturn('ana@correo.co');
    when(() => firebaseUser.displayName).thenReturn('Ana');
  });

  /// Crea un contenedor con la sesión de Firebase y el perfil simulados y
  /// espera a que ambos streams emitan.
  Future<SessionState> sessionWith({
    required Stream<User?> auth,
    Stream<AppUser?> Function(String uid)? profile,
  }) async {
    final container = ProviderContainer(
      overrides: [
        firebaseUserProvider.overrideWith((ref) => auth),
        userProfileProvider.overrideWith(
          (ref, uid) => profile?.call(uid) ?? const Stream.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(sessionProvider, (_, __) {});
    await pumpEventQueue();
    return container.read(sessionProvider);
  }

  AppUser user({UserStatus estado = UserStatus.activo}) => AppUser(
        uid: 'u1',
        email: 'ana@correo.co',
        displayName: 'Ana',
        role: UserRole.dueno,
        estado: estado,
      );

  test('mientras Firebase Auth no responde → cargando', () async {
    final session = await sessionWith(auth: const Stream.empty());
    expect(session, isA<SessionLoading>());
  });

  test('sin sesión → SignedOut', () async {
    final session = await sessionWith(auth: Stream.value(null));
    expect(session, isA<SignedOut>());
  });

  test('con sesión pero sin perfil → NeedsRegistration con el correo', () async {
    final session = await sessionWith(
      auth: Stream.value(firebaseUser),
      profile: (_) => Stream.value(null),
    );
    expect(
      session,
      isA<NeedsRegistration>()
          .having((s) => s.uid, 'uid', 'u1')
          .having((s) => s.email, 'email', 'ana@correo.co'),
    );
  });

  test('perfil aún cargando → cargando (no se asume "sin registro")',
      () async {
    final session = await sessionWith(
      auth: Stream.value(firebaseUser),
      profile: (_) => const Stream.empty(),
    );
    expect(session, isA<SessionLoading>());
  });

  test('perfil suspendido → Suspended', () async {
    final session = await sessionWith(
      auth: Stream.value(firebaseUser),
      profile: (_) => Stream.value(user(estado: UserStatus.suspendido)),
    );
    expect(session, isA<Suspended>());
  });

  test('perfil activo → SignedIn', () async {
    final session = await sessionWith(
      auth: Stream.value(firebaseUser),
      profile: (_) => Stream.value(user()),
    );
    expect(session, isA<SignedIn>().having((s) => s.user.uid, 'uid', 'u1'));
  });

  test('error leyendo el perfil → SessionError', () async {
    final session = await sessionWith(
      auth: Stream.value(firebaseUser),
      profile: (_) => Stream.error(Exception('permission-denied')),
    );
    expect(session, isA<SessionError>());
  });
}
