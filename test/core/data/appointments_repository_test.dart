import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/appointments_repository.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockFunctions extends Mock implements FunctionsClient {}

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockFunctions functions;
  late AppointmentsRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    functions = _MockFunctions();
    repository = AppointmentsRepository(firestore: firestore, functions: functions);
  });

  Future<void> seed(String id, {
    String ownerUid = 'ana',
    String clinicId = 'c1',
    String estado = 'pendiente',
    required DateTime inicio,
  }) =>
      firestore.doc('appointments/$id').set({
        'clinicId': clinicId,
        'ownerUid': ownerUid,
        'petNombre': 'Luna',
        'estado': estado,
        'inicio': Timestamp.fromDate(inicio),
      });

  void answer(Future<FunctionResponse> Function() response) {
    when(() => functions.invoke('citas', body: any(named: 'body'))).thenAnswer((_) => response());
  }

  void failWith(int status, String code, String message) {
    when(() => functions.invoke('citas', body: any(named: 'body'))).thenThrow(
      FunctionException(status: status, details: {
        'error': {'code': code, 'message': message},
      }),
    );
  }

  Map<String, dynamic> sentBody() =>
      verify(() => functions.invoke('citas', body: captureAny(named: 'body'))).captured.single
          as Map<String, dynamic>;

  group('lectura', () {
    test('mis citas: solo las del dueño, de la más lejana a la más antigua', () async {
      await seed('a1', inicio: BogotaTime.at(2026, 11, 5, 9));
      await seed('a2', inicio: BogotaTime.at(2026, 11, 20, 9), estado: 'confirmada');
      await seed('a3', ownerUid: 'beto', inicio: BogotaTime.at(2026, 11, 6, 9));

      final mine = await repository.watchOwnerAppointments('ana').first;
      expect(mine.map((a) => a.id), ['a2', 'a1']);
      expect(mine.first.estado, AppointmentStatus.confirmada);
    });

    test('solicitudes pendientes de la clínica, la más próxima primero', () async {
      await seed('a1', inicio: BogotaTime.at(2026, 11, 7, 9));
      await seed('a2', inicio: BogotaTime.at(2026, 11, 5, 9));
      await seed('a3', inicio: BogotaTime.at(2026, 11, 4, 9), estado: 'confirmada');
      await seed('a4', clinicId: 'c2', inicio: BogotaTime.at(2026, 11, 4, 9));

      final pending = await repository.watchPendingRequests('c1').first;
      expect(pending.map((a) => a.id), ['a2', 'a1']);
    });

    test('tiempo real: una solicitud nueva aparece en la bandeja', () async {
      final emissions = <List<String>>[];
      final sub = repository
          .watchPendingRequests('c1')
          .listen((list) => emissions.add([for (final a in list) a.id]));
      await pumpEventQueue();
      await seed('a1', inicio: BogotaTime.at(2026, 11, 5, 9));
      await pumpEventQueue();
      await sub.cancel();
      expect(emissions.first, isEmpty);
      expect(emissions.last, ['a1']);
    });

    test('agenda del día: de 00:00 a 24:00 en hora de Bogotá', () async {
      await seed('temprano', inicio: BogotaTime.at(2026, 11, 5, 0));
      await seed('noche', inicio: BogotaTime.at(2026, 11, 5, 23, 30), estado: 'confirmada');
      await seed('ayer', inicio: BogotaTime.at(2026, 11, 4, 23, 59));
      await seed('manana', inicio: BogotaTime.at(2026, 11, 6, 0));
      await seed('otra', clinicId: 'c2', inicio: BogotaTime.at(2026, 11, 5, 10));

      final day = await repository.watchDay('c1', DateTime(2026, 11, 5)).first;
      expect(day.map((a) => a.id), ['temprano', 'noche']);
    });

    test('una cita, o null si no existe', () async {
      await seed('a1', inicio: BogotaTime.at(2026, 11, 5, 9));
      expect((await repository.watchAppointment('a1').first)?.petNombre, 'Luna');
      expect(await repository.watchAppointment('nada').first, isNull);
    });
  });

  group('acciones (Edge Function citas)', () {
    test('solicitar envía los datos y devuelve el id', () async {
      answer(() async => const FunctionResponse(status: 200, data: {'appointmentId': 'a9'}));

      final id = await repository.request(
        clinicId: 'c1',
        serviceId: 's1',
        petId: 'p1',
        slotId: '2026-11-05_09:30',
        comentario: ' Vómito desde ayer ',
      );

      expect(id, 'a9');
      expect(sentBody(), {
        'accion': 'solicitar',
        'clinicId': 'c1',
        'serviceId': 's1',
        'petId': 'p1',
        'slotId': '2026-11-05_09:30',
        'comentario': 'Vómito desde ayer',
      });
    });

    test('horario tomado → slotTaken con el mensaje del RF', () async {
      failWith(409, 'aborted', 'Este horario ya no está disponible, por favor selecciona otro');
      await expectLater(
        repository.request(clinicId: 'c1', serviceId: 's1', petId: 'p1', slotId: 'x'),
        throwsA(same(AppointmentFailure.slotUnavailable)),
      );
    });

    test('aprobar, rechazar, cancelar y completar', () async {
      answer(() async => const FunctionResponse(status: 200, data: {'ok': true}));

      await repository.approve('a1');
      expect(sentBody(), {'accion': 'responder', 'appointmentId': 'a1', 'aprobar': true});

      await repository.reject('a1', ' Sin veterinario ');
      expect(sentBody(), {
        'accion': 'responder', 'appointmentId': 'a1', 'aprobar': false, 'motivo': 'Sin veterinario',
      });

      await repository.cancel('a1');
      expect(sentBody(), {'accion': 'cancelar', 'appointmentId': 'a1'});

      await repository.cancel('a1', motivo: 'Imprevisto', byClinic: true);
      expect(sentBody(), {'accion': 'cancelar', 'appointmentId': 'a1', 'motivo': 'Imprevisto'});

      await repository.complete('a1');
      expect(sentBody(), {'accion': 'completar', 'appointmentId': 'a1'});
    });

    test('motivos obligatorios y largos se validan sin llamar al servidor', () async {
      await expectLater(repository.reject('a1', '  '),
          throwsA(isA<AppointmentFailure>().having((f) => f.message, 'message', 'Indica el motivo del rechazo.')));
      await expectLater(repository.cancel('a1', byClinic: true),
          throwsA(isA<AppointmentFailure>()
              .having((f) => f.message, 'message', 'Indica el motivo de la cancelación.')));
      await expectLater(repository.cancel('a1', motivo: 'x' * 301), throwsA(isA<AppointmentFailure>()));
      await expectLater(
        repository.request(clinicId: 'c1', serviceId: 's1', petId: 'p1', slotId: 'x', comentario: 'x' * 501),
        throwsA(isA<AppointmentFailure>()),
      );
      verifyNever(() => functions.invoke(any(), body: any(named: 'body')));
    });

    test('errores del servidor se muestran tal cual', () async {
      failWith(412, 'failed-precondition',
          'Solo puedes cancelar hasta 2 horas antes de la cita. Comunícate con la clínica.');
      await expectLater(
        repository.cancel('a1'),
        throwsA(isA<AppointmentFailure>()
            .having((f) => f.message, 'message', startsWith('Solo puedes cancelar hasta 2 horas'))
            .having((f) => f.canRetry, 'canRetry', isFalse)
            .having((f) => f.slotTaken, 'slotTaken', isFalse)),
      );
    });

    test('sin conexión → mensaje de red con reintento', () async {
      when(() => functions.invoke('citas', body: any(named: 'body')))
          .thenThrow(const SocketException('sin red'));
      await expectLater(repository.approve('a1'), throwsA(same(AppointmentFailure.network)));
    });

    test('sin Supabase configurado avisa', () async {
      repository = AppointmentsRepository(firestore: firestore);
      await expectLater(repository.complete('a1'), throwsA(same(AppointmentFailure.notConfigured)));
    });
  });
}
