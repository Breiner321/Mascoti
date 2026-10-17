import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/plugins/clinica/data/pet_link_api.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockFunctions extends Mock implements FunctionsClient {}

void main() {
  late _MockFunctions functions;
  late PetLinkApi api;

  setUp(() {
    functions = _MockFunctions();
    api = PetLinkApi(functions);
  });

  void answers(Future<FunctionResponse> Function() answer) {
    when(() => functions.invoke('vincular-mascota', body: any(named: 'body')))
        .thenAnswer((_) => answer());
  }

  FunctionException error(int status, String code, String message) => FunctionException(
        status: status,
        details: {
          'error': {'code': code, 'message': message},
        },
      );

  Future<PetLinkFailure> failure() async {
    try {
      await api.link('MSC-7K4P');
    } on PetLinkFailure catch (e) {
      return e;
    }
    fail('Se esperaba PetLinkFailure');
  }

  test('envía el código y devuelve la mascota vinculada', () async {
    answers(() async => const FunctionResponse(status: 200, data: {
          'petId': 'p1',
          'codigoPaciente': 'MSC-7K4P',
          'nombre': 'Luna',
          'especie': 'perro',
          'fotoPath': 'ana/p1/foto.jpg',
          'duenoNombre': 'Ana Pérez',
          'nueva': true,
        }));

    final pet = await api.link('MSC-7K4P');

    verify(() => functions.invoke('vincular-mascota', body: {'codigo': 'MSC-7K4P'})).called(1);
    expect(pet.petId, 'p1');
    expect(pet.nombre, 'Luna');
    expect(pet.duenoNombre, 'Ana Pérez');
    expect(pet.fotoPath, 'ana/p1/foto.jpg');
    expect(pet.nueva, isTrue);
  });

  test('cada código HTTP se convierte en un error con el mensaje del servidor', () async {
    final casos = {
      404: PetLinkFailureKind.notFound,
      400: PetLinkFailureKind.invalidCode,
      412: PetLinkFailureKind.clinicInactive,
      403: PetLinkFailureKind.notAllowed,
      429: PetLinkFailureKind.tooManyAttempts,
      500: PetLinkFailureKind.unknown,
    };
    for (final entry in casos.entries) {
      answers(() => throw error(entry.key, 'x', 'mensaje ${entry.key}'));
      final f = await failure();
      expect(f.kind, entry.value, reason: '${entry.key}');
      expect(f.message, 'mensaje ${entry.key}');
    }
  });

  test('sin mensaje del servidor usa el de respaldo', () async {
    answers(() => throw const FunctionException(status: 404));
    expect((await failure()).message, 'No existe una mascota con ese código.');
  });

  test('sin respuesta en 10 s → error de red con reintento', () {
    fakeAsync((async) {
      answers(() => Completer<FunctionResponse>().future);
      PetLinkFailure? error;
      api.link('MSC-7K4P').catchError((Object e) {
        error = e as PetLinkFailure;
        return const LinkedPet(
            petId: '', codigoPaciente: '', nombre: '', especie: '', duenoNombre: '', nueva: false);
      });
      async.elapse(const Duration(seconds: 11));
      expect(error?.kind, PetLinkFailureKind.network);
      expect(error?.canRetry, isTrue);
    });
  });

  test('sin Supabase configurado → notConfigured', () async {
    api = PetLinkApi(null);
    expect((await failure()).kind, PetLinkFailureKind.notConfigured);
  });
}
