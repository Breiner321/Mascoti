import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/data/registration_api.dart';
import 'package:mascoti/core/auth/domain/registration.dart';
import 'package:mascoti/core/auth/domain/registration_failure.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockFunctions extends Mock implements FunctionsClient {}

void main() {
  late _MockFunctions functions;
  late RegistrationApi api;

  setUp(() {
    functions = _MockFunctions();
    api = RegistrationApi(functions);
  });

  void edgeFunctionAnswers(Future<FunctionResponse> Function() answer) {
    when(() => functions.invoke('completar-registro', body: any(named: 'body')))
        .thenAnswer((_) => answer());
  }

  Future<RegistrationFailure> failure() async {
    try {
      await api.complete(const RegistrationRequest.owner(OwnerRegistration(nombre: 'Ana Pérez', telefono: '3001234567')));
    } on RegistrationFailure catch (e) {
      return e;
    }
    fail('Se esperaba RegistrationFailure');
  }

  test('envía el payload a completar-registro', () async {
    edgeFunctionAnswers(() async => const FunctionResponse(status: 200, data: {}));

    await api.complete(const RegistrationRequest.owner(OwnerRegistration(nombre: 'Ana Pérez', telefono: '3001234567')));

    verify(() => functions.invoke('completar-registro', body: {
          'role': 'dueno',
          'dueno': {'nombre': 'Ana Pérez', 'telefono': '3001234567'},
        })).called(1);
  });

  test('409 → cuenta ya registrada (mensaje del RF)', () async {
    edgeFunctionAnswers(() => throw const FunctionException(
          status: 409,
          details: {
            'error': {'code': 'already-exists', 'message': 'ya'},
          },
        ));
    final f = await failure();
    expect(f.kind, RegistrationFailureKind.alreadyExists);
    expect(f.message, 'Esta cuenta ya está registrada. Iniciando sesión...');
    expect(f.canRetry, isFalse);
  });

  test('400 → muestra el mensaje del servidor', () async {
    edgeFunctionAnswers(() => throw const FunctionException(
          status: 400,
          details: {
            'error': {
              'code': 'invalid-argument',
              'message': 'Selecciona una dirección válida de la lista',
            },
          },
        ));
    final f = await failure();
    expect(f.kind, RegistrationFailureKind.invalid);
    expect(f.message, 'Selecciona una dirección válida de la lista');
  });

  test('sin respuesta en 10 s → error de red con reintento', () {
    fakeAsync((async) {
      edgeFunctionAnswers(() => Completer<FunctionResponse>().future);
      RegistrationFailure? error;
      api.complete(const RegistrationRequest.owner(OwnerRegistration(nombre: 'Ana Pérez', telefono: '3001234567'))).catchError((Object e) {
        error = e as RegistrationFailure;
      });
      async.elapse(const Duration(seconds: 11));

      expect(error?.kind, RegistrationFailureKind.network);
      expect(error?.message, 'No se pudo completar el registro. Verifica tu conexión');
      expect(error?.canRetry, isTrue);
    });
  });

  test('500 → error genérico con reintento', () async {
    edgeFunctionAnswers(() => throw const FunctionException(status: 500));
    final f = await failure();
    expect(f.kind, RegistrationFailureKind.unknown);
    expect(f.canRetry, isTrue);
  });

  test('sin Supabase configurado → notConfigured', () async {
    api = RegistrationApi(null);
    expect((await failure()).kind, RegistrationFailureKind.notConfigured);
  });
}
