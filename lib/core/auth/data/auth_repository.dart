import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/env.dart';
import '../domain/app_user.dart';
import '../domain/auth_failure.dart';
import '../domain/registration.dart';

/// Única clase que habla con Firebase Auth / Google Sign-In (RF-01..03).
class AuthRepository {
  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: Env.functionsRegion),
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final GoogleSignIn _googleSignIn;

  static const _timeout = Duration(seconds: 10);
  static const _signOutTimeout = Duration(seconds: 5);

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Perfil `users/{uid}` en tiempo real. Emite null si aún no existe.
  ///
  /// Un documento vacío que viene de la caché local no prueba que el usuario
  /// no esté registrado (p. ej. primer arranque sin conexión): se ignora hasta
  /// que responda el servidor, para no enviar a un usuario registrado al
  /// flujo de registro.
  Stream<AppUser?> watchUserProfile(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .where((snap) => snap.exists || !snap.metadata.isFromCache)
      .map((snap) {
        final data = snap.data();
        return data == null ? null : AppUser.fromMap(snap.id, data);
      });

  /// Abre el selector de cuentas de Google e inicia sesión en Firebase.
  /// Devuelve false si el usuario cerró el selector (RF-01, flujo alterno).
  /// Lanza [AuthFailure] si la cuenta está suspendida, no hay red u otro error.
  Future<bool> signInWithGoogle() async {
    final GoogleSignInAccount account;
    try {
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw const AuthFailure(AuthFailureKind.unknown);
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) throw const AuthFailure(AuthFailureKind.unknown);

    try {
      await _auth
          .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken))
          .timeout(_timeout);
    } on TimeoutException {
      throw const AuthFailure(AuthFailureKind.network);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        // La Function sincronizarSuspension deshabilita la cuenta (RF-02).
        'user-disabled' => AuthFailureKind.suspended,
        'network-request-failed' => AuthFailureKind.network,
        _ => AuthFailureKind.unknown,
      });
    }
    _touchLastLogin();
    return true;
  }

  /// Crea `users/{uid}` (y `clinics/{id}` si es clínica) en una transacción
  /// del servidor. Lanza [FirebaseFunctionsException]:
  /// - `already-exists` si la cuenta ya estaba registrada;
  /// - `deadline-exceeded` si no hubo respuesta en 10 s.
  Future<void> completeRegistration(RegistrationRequest request) async {
    final callable = _functions.httpsCallable(
      'completarRegistro',
      options: HttpsCallableOptions(timeout: _timeout),
    );
    await callable.call(request.toMap());
  }

  /// RF-03: cierra la sesión local. Los listeners de Firestore se cancelan
  /// solos porque los providers dependen de la sesión.
  ///
  /// Sin conexión, Google puede fallar o no responder: igual se cierra la
  /// sesión de Firebase (el logout local tiene prioridad).
  // TODO(RF-13): borrar el token FCM de users/{uid}/devices antes de salir.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut().timeout(_signOutTimeout);
    } catch (_) {
      // Se ignora: Google se desconecta en el próximo inicio de sesión.
    }
    await _auth.signOut();
  }

  /// No se espera la confirmación del servidor: con red inestable el login no
  /// debe quedarse cargando por un dato informativo. Si users/{uid} aún no
  /// existe (usuario nuevo), la escritura falla y se ignora.
  void _touchLastLogin() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    unawaited(
      _firestore
          .collection('users')
          .doc(uid)
          .update({'lastLoginAt': FieldValue.serverTimestamp()})
          .catchError((Object _) {}),
    );
  }
}
