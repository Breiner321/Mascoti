import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mascoti/core/auth/data/auth_repository.dart';
import 'package:mascoti/core/auth/data/registration_api.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/auth/domain/auth_failure.dart';
import 'package:mascoti/core/auth/domain/registration.dart';
import 'package:mascoti/core/auth/domain/registration_failure.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockAccount extends Mock implements GoogleSignInAccount {}

class _MockRegistrationApi extends Mock implements RegistrationApi {}

// Las clases de cloud_firestore están marcadas @sealed, pero simularlas es la
// única forma de producir un snapshot "desde caché" en una prueba.
class _MockFirestore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class
class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockDocSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockMetadata extends Mock implements SnapshotMetadata {}

void main() {
  late _MockAuth auth;
  late _MockGoogleSignIn google;
  late _MockRegistrationApi registrationApi;
  late FakeFirebaseFirestore firestore;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(GoogleAuthProvider.credential(idToken: 'x'));
    registerFallbackValue(const RegistrationRequest.owner());
  });

  setUp(() {
    auth = _MockAuth();
    google = _MockGoogleSignIn();
    registrationApi = _MockRegistrationApi();
    firestore = FakeFirebaseFirestore();
    repository = AuthRepository(
      auth: auth,
      firestore: firestore,
      registrationApi: registrationApi,
      googleSignIn: google,
    );
  });

  void googleReturnsAccount({String? idToken = 'google-token'}) {
    final account = _MockAccount();
    when(() => account.authentication)
        .thenReturn(GoogleSignInAuthentication(idToken: idToken));
    when(() => google.authenticate()).thenAnswer((_) async => account);
  }

  group('signInWithGoogle (RF-01, RF-02)', () {
    test('devuelve false y no toca Firebase si el usuario cierra el selector',
        () async {
      when(() => google.authenticate()).thenThrow(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );

      expect(await repository.signInWithGoogle(), isFalse);
      verifyNever(() => auth.signInWithCredential(any()));
    });

    test('inicia sesión y actualiza lastLoginAt', () async {
      googleReturnsAccount();
      final user = _MockUser();
      when(() => user.uid).thenReturn('u1');
      when(() => auth.currentUser).thenReturn(user);
      when(() => auth.signInWithCredential(any()))
          .thenAnswer((_) async => _MockUserCredential());
      await firestore.doc('users/u1').set({'role': 'dueno'});

      expect(await repository.signInWithGoogle(), isTrue);
      await pumpEventQueue();

      final doc = await firestore.doc('users/u1').get();
      expect(doc.data()!['lastLoginAt'], isNotNull);
    });

    test('usuario nuevo: no falla aunque users/{uid} no exista', () async {
      googleReturnsAccount();
      final user = _MockUser();
      when(() => user.uid).thenReturn('nuevo');
      when(() => auth.currentUser).thenReturn(user);
      when(() => auth.signInWithCredential(any()))
          .thenAnswer((_) async => _MockUserCredential());

      expect(await repository.signInWithGoogle(), isTrue);
      await pumpEventQueue();
      expect((await firestore.doc('users/nuevo').get()).exists, isFalse);
    });

    Future<void> expectFailure(Object error, AuthFailureKind kind) async {
      googleReturnsAccount();
      when(() => auth.signInWithCredential(any())).thenThrow(error);
      await expectLater(
        repository.signInWithGoogle(),
        throwsA(isA<AuthFailure>().having((f) => f.kind, 'kind', kind)),
      );
    }

    test('cuenta deshabilitada → suspended (RF-02)', () async {
      await expectFailure(
        FirebaseAuthException(code: 'user-disabled'),
        AuthFailureKind.suspended,
      );
    });

    test('sin red → network', () async {
      await expectFailure(
        FirebaseAuthException(code: 'network-request-failed'),
        AuthFailureKind.network,
      );
    });

    test('sin respuesta en 10 s → network', () {
      fakeAsync((async) {
        googleReturnsAccount();
        when(() => auth.signInWithCredential(any()))
            .thenAnswer((_) => Completer<UserCredential>().future);

        Object? error;
        repository.signInWithGoogle().catchError((Object e) {
          error = e;
          return false;
        });
        async.elapse(const Duration(seconds: 11));

        expect(
          error,
          isA<AuthFailure>()
              .having((f) => f.kind, 'kind', AuthFailureKind.network),
        );
      });
    });

    test('otros errores de Google → unknown', () async {
      when(() => google.authenticate()).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        ),
      );
      await expectLater(
        repository.signInWithGoogle(),
        throwsA(isA<AuthFailure>()
            .having((f) => f.kind, 'kind', AuthFailureKind.unknown)),
      );
    });

    test('Google sin idToken → unknown', () async {
      googleReturnsAccount(idToken: null);
      await expectLater(
        repository.signInWithGoogle(),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('signOut (RF-03)', () {
    test('cierra Firebase aunque Google falle (sin conexión)', () async {
      when(() => google.signOut()).thenThrow(Exception('sin red'));
      when(() => auth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => auth.signOut()).called(1);
    });

    test('cierra Firebase aunque Google no responda', () {
      fakeAsync((async) {
        when(() => google.signOut())
            .thenAnswer((_) => Completer<void>().future);
        when(() => auth.signOut()).thenAnswer((_) async {});

        var done = false;
        repository.signOut().then((_) => done = true);
        async.elapse(const Duration(seconds: 6));

        expect(done, isTrue);
        verify(() => auth.signOut()).called(1);
      });
    });
  });

  group('watchUserProfile', () {
    test('emite el perfil y null si no está registrado', () async {
      await firestore.doc('users/u1').set({
        'email': 'ana@correo.co',
        'displayName': 'Ana',
        'role': 'dueno',
        'estado': 'suspendido',
      });

      final user = await repository.watchUserProfile('u1').first;
      expect(user?.role, UserRole.dueno);
      expect(user?.estado, UserStatus.suspendido);

      expect(await repository.watchUserProfile('otro').first, isNull);
    });

    test('ignora un documento vacío que viene de la caché (sin conexión)',
        () async {
      final mockFirestore = _MockFirestore();
      final collection = _MockCollection();
      final docRef = _MockDocRef();
      when(() => mockFirestore.collection('users')).thenReturn(collection);
      when(() => collection.doc('u1')).thenReturn(docRef);

      _MockDocSnapshot snapshot({
        required bool exists,
        required bool fromCache,
      }) {
        final snap = _MockDocSnapshot();
        final metadata = _MockMetadata();
        when(() => metadata.isFromCache).thenReturn(fromCache);
        when(() => snap.exists).thenReturn(exists);
        when(() => snap.metadata).thenReturn(metadata);
        when(() => snap.id).thenReturn('u1');
        when(() => snap.data()).thenReturn(
          exists ? {'role': 'clinica', 'displayName': 'Vet'} : null,
        );
        return snap;
      }

      when(() => docRef.snapshots(includeMetadataChanges: true))
          .thenAnswer((_) => Stream.fromIterable([
                snapshot(exists: false, fromCache: true),
                snapshot(exists: true, fromCache: false),
              ]));

      final emitted = await AuthRepository(
        auth: auth,
        firestore: mockFirestore,
        registrationApi: registrationApi,
        googleSignIn: google,
      ).watchUserProfile('u1').toList();

      expect(emitted, hasLength(1));
      expect(emitted.single?.role, UserRole.clinica);
    });
  });

  test('completeRegistration llama a la Edge Function y renueva el token',
      () async {
    final user = _MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.getIdToken(true)).thenAnswer((_) async => 'nuevo-token');
    when(() => registrationApi.complete(any())).thenAnswer((_) async {});

    await repository.completeRegistration(const RegistrationRequest.owner());

    verify(() => registrationApi.complete(any())).called(1);
    verify(() => user.getIdToken(true)).called(1);
  });

  test('completeRegistration no renueva el token si el registro falla',
      () async {
    final user = _MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => registrationApi.complete(any())).thenThrow(
      const RegistrationFailure(RegistrationFailureKind.alreadyExists),
    );

    await expectLater(
      repository.completeRegistration(const RegistrationRequest.owner()),
      throwsA(isA<RegistrationFailure>()),
    );
    verifyNever(() => user.getIdToken(any()));
  });
}
