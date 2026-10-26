import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/appointments_providers.dart';
import 'package:mascoti/core/data/appointments_repository.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/reservas/presentation/clinica/clinic_appointment_detail_page.dart';
import 'package:mascoti/plugins/reservas/presentation/clinica/clinic_requests_providers.dart';
import 'package:mocktail/mocktail.dart';

import '../../core/fake_plugins.dart';

class _MockRepo extends Mock implements AppointmentsRepository {}

/// 3 nov 2026, 9:00 a. m. en Bogotá.
final _inicio = DateTime.utc(2026, 11, 3, 14);

Appointment _cita({AppointmentStatus estado = AppointmentStatus.pendiente}) => Appointment(
      id: 'a1',
      clinicId: 'c1',
      clinicNombre: 'Clínica Norte',
      ownerUid: 'ana',
      ownerNombre: 'Ana Pérez',
      petId: 'p1',
      petNombre: 'Luna',
      serviceId: 's1',
      serviceNombre: 'Consulta general',
      precioAcordado: 45000,
      duracionMin: 30,
      slotId: '2026-11-03_09:00',
      fecha: '2026-11-03',
      hora: '09:00',
      inicio: _inicio,
      comentario: 'Vómito desde ayer',
      estado: estado,
    );

const _luna = Pet(
  id: 'p1',
  ownerUid: 'ana',
  nombre: 'Luna',
  especie: PetSpecies.perro,
  alergias: ['Penicilina'],
);

void main() {
  late _MockRepo repo;
  late StreamController<Appointment?> stream;

  setUp(() {
    repo = _MockRepo();
    stream = StreamController<Appointment?>.broadcast();
    addTearDown(() {
      stream.close();
    });
  });

  /// [now] es la hora del "reloj" de la pantalla.
  Future<void> pump(WidgetTester tester, Appointment cita, {DateTime? now}) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/reservas/a1',
      routes: [
        GoRoute(
          path: '/reservas/:id',
          builder: (_, state) =>
              ClinicAppointmentDetailPage(appointmentId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/clinica/pacientes/:petId',
          builder: (_, state) => Text('historial ${state.pathParameters['petId']}'),
        ),
        GoRoute(
          path: '/clinica/pacientes/:petId/consulta',
          builder: (_, state) => Text(
            'consulta ${state.pathParameters['petId']} cita ${state.uri.queryParameters['appointmentId']}',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentsRepositoryProvider.overrideWithValue(repo),
          appointmentProvider('a1').overrideWith((ref) => stream.stream),
          clinicPetProvider('p1').overrideWith((ref) => Stream.value(_luna)),
          appointmentClockProvider.overrideWithValue(() => now ?? _inicio),
          pluginRegistryProvider.overrideWithValue(PluginRegistry([
            FakePlugin('clinica', roles: {UserRole.clinica}, paths: ['/clinica/pacientes/:petId']),
          ])),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    stream.add(cita);
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('muestra la solicitud completa, alergias en rojo y el historial', (tester) async {
    await pump(tester, _cita());

    expect(find.text('Luna'), findsOneWidget);
    expect(find.text('Consulta general'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('“Vómito desde ayer”'), findsOneWidget);
    expect(find.text('Penicilina'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);

    await tapButton(tester, 'Ver historial médico');
    expect(find.text('historial p1'), findsOneWidget);
  });

  testWidgets('aprobar llama al repositorio', (tester) async {
    when(() => repo.approve('a1')).thenAnswer((_) async {});
    await pump(tester, _cita());

    await tapButton(tester, 'Aprobar');

    verify(() => repo.approve('a1')).called(1);
    expect(find.text('Cita aprobada. Le avisamos al dueño.'), findsOneWidget);
  });

  testWidgets('rechazar sin motivo queda bloqueado; con motivo se envía', (tester) async {
    when(() => repo.reject(any(), any())).thenAnswer((_) async {});
    await pump(tester, _cita());

    await tapButton(tester, 'Rechazar');
    expect(find.text('Rechazar solicitud'), findsOneWidget);

    // Sin motivo el botón no se puede usar.
    final confirm = find.widgetWithText(FilledButton, 'Rechazar');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    verifyNever(() => repo.reject(any(), any()));

    await tester.enterText(find.byType(TextField), 'No hay veterinario ese día');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    verify(() => repo.reject('a1', 'No hay veterinario ese día')).called(1);
  });

  testWidgets('otra persona ya respondió: aviso y sin botones de respuesta', (tester) async {
    await pump(tester, _cita());

    stream.add(_cita(estado: AppointmentStatus.confirmada));
    await tester.pumpAndSettle();

    expect(find.textContaining(ClinicAppointmentDetailPage.alreadyAnswered), findsOneWidget);
    expect(find.text('Aprobar'), findsNothing);
  });

  testWidgets('si el servidor rechaza la acción se muestra su mensaje', (tester) async {
    when(() => repo.approve('a1'))
        .thenThrow(const AppointmentFailure('Esta solicitud ya fue respondida.'));
    await pump(tester, _cita());

    await tapButton(tester, 'Aprobar');

    expect(find.text('Esta solicitud ya fue respondida.'), findsOneWidget);
  });

  testWidgets('cancelar una cita confirmada pide motivo y avisa que se notificará',
      (tester) async {
    when(() => repo.cancel(any(), motivo: any(named: 'motivo'), byClinic: any(named: 'byClinic')))
        .thenAnswer((_) async {});
    await pump(
      tester,
      _cita(estado: AppointmentStatus.confirmada),
      now: _inicio.subtract(const Duration(days: 1)),
    );

    // Antes de la hora de inicio no se puede marcar como atendida.
    expect(find.text('Marcar como atendida'), findsNothing);

    await tapButton(tester, 'Cancelar cita');
    expect(find.text(ClinicAppointmentDetailPage.cancelWarning), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Cancelar cita');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'El veterinario está incapacitado');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    verify(() => repo.cancel('a1', motivo: 'El veterinario está incapacitado', byClinic: true))
        .called(1);
  });

  testWidgets('pasada la hora: "Marcar como atendida" y luego "Registrar consulta"',
      (tester) async {
    when(() => repo.complete('a1')).thenAnswer((_) async {});
    await pump(
      tester,
      _cita(estado: AppointmentStatus.confirmada),
      now: _inicio.add(const Duration(minutes: 10)),
    );

    await tapButton(tester, 'Marcar como atendida');

    verify(() => repo.complete('a1')).called(1);
    expect(find.text('Cita atendida'), findsOneWidget);

    await tester.tap(find.text('Registrar consulta'));
    await tester.pumpAndSettle();
    expect(find.text('consulta p1 cita a1'), findsOneWidget);
  });

  testWidgets('cita atendida: ofrece "Registrar consulta"', (tester) async {
    await pump(tester, _cita(estado: AppointmentStatus.completada));

    expect(find.text('Aprobar'), findsNothing);
    expect(find.text('Cancelar cita'), findsNothing);
    await tapButton(tester, 'Registrar consulta');
    expect(find.text('consulta p1 cita a1'), findsOneWidget);
  });
}
