import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/env.dart';
import '../domain/app_user.dart';
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

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Perfil `users/{uid}` en tiempo real. Emite null si aún no existe.
  Stream<AppUser?> watchUserProfile(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) {
        final data = snap.data();
        return data == null ? null : AppUser.fromMap(snap.id, data);
      });

  /// Abre el selector de cuentas de Google e inicia sesión en Firebase.
  /// Devuelve false si el usuario cerró el selector (RF-01, flujo alterno).
  Future<bool> signInWithGoogle() async {
    final GoogleSignInAccount account;
    try {
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google no devolvió un idToken');
    }

    await _auth
        .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken))
        .timeout(_timeout);
    await _touchLastLogin();
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
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Si Google falla (sin red), igual se cierra la sesión de Firebase.
    }
    await _auth.signOut();
  }

  Future<void> _touchLastLogin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .update({'lastLoginAt': FieldValue.serverTimestamp()});
    } on FirebaseException {
      // Usuario nuevo: users/{uid} todavía no existe. No es un error.
    }
  }
}
