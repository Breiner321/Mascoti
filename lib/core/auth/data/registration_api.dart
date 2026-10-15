import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/registration.dart';
import '../domain/registration_failure.dart';

/// Llama a la Edge Function `completar-registro` de Supabase (RF-01), que crea
/// users/{uid} (y clinics/{id}) en Firestore de forma atómica. El ID token de
/// Firebase viaja solo: el cliente de Supabase se configuró con `accessToken`.
class RegistrationApi {
  RegistrationApi(this._functions);

  /// null = Supabase no está configurado en este equipo.
  final FunctionsClient? _functions;

  static const _timeout = Duration(seconds: 10);

  /// Lanza [RegistrationFailure] con el mensaje que debe ver el usuario.
  Future<void> complete(RegistrationRequest request) async {
    final functions = _functions;
    if (functions == null) {
      throw const RegistrationFailure(RegistrationFailureKind.notConfigured);
    }
    try {
      await functions
          .invoke('completar-registro', body: request.toMap())
          .timeout(_timeout);
    } on TimeoutException {
      throw const RegistrationFailure(RegistrationFailureKind.network);
    } on SocketException {
      throw const RegistrationFailure(RegistrationFailureKind.network);
    } on http.ClientException {
      throw const RegistrationFailure(RegistrationFailureKind.network);
    } on FunctionException catch (e) {
      final error = e.details is Map ? (e.details as Map)['error'] : null;
      final message = error is Map ? error['message'] as String? : null;
      throw RegistrationFailure(
        switch (e.status) {
          409 => RegistrationFailureKind.alreadyExists,
          400 => RegistrationFailureKind.invalid,
          _ => RegistrationFailureKind.unknown,
        },
        serverMessage: message,
      );
    }
  }
}
