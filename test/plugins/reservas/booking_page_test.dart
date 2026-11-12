import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/data/appointments_providers.dart';
import 'package:mascoti/core/data/appointments_repository.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/domain/slot.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/reservas/presentation/dueno/booking_page.dart';
import 'package:mascoti/plugins/reservas/presentation/dueno/booking_providers.dart';
import 'package:mascoti/plugins/reservas/reservas_plugin.dart';
import 'package:mocktail/mocktail.dart';

import 'fakes.dart';

import '../../a11y.dart';

class _MockAppointments extends Mock implements AppointmentsRepository {}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  // 5 de noviembre de 2026, 8:00 a. m. en Bogotá.
  final now = BogotaTime.at(2026, 11, 5, 8);
  late StreamController<List<Slot>> slots;
  late _MockAppointments appointments;
  late int slotSubscriptions;

  Future<void> pumpBooking(
    WidgetTester tester, {
    List<Pet> pets = const [luna],
    String? categoria,
  }) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(owner),
          bookingClockProvider.overrideWithValue(() => now),
          pluginRegistryProvider.overrideWithValue(PluginRegistry([const ReservasPlugin()])),
          appointmentsRepositoryProvider.overrideWithValue(appointments),
          bookingClinicProvider.overrideWith((ref, id) => Stream.value(clinic)),
          bookingServicesProvider.overrideWith((ref, id) => Stream.value([consulta, vacuna])),
          ownerPetsProvider.overrideWith((ref) => Stream.value(pets)),
          monthSlotsProvider.overrideWith((ref, q) {
            slotSubscriptions++;
            return slots.stream;
          }),
          clinicExceptionsProvider.overrideWith((ref, q) => Stream.value(const [])),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: GoRouter(routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => BookingPage(clinicId: 'c1', categoria: categoria),
            ),
            GoRoute(
              path: '/reservas/:id',
              builder: (_, state) => Scaffold(body: Text('detalle ${state.pathParameters['id']}')),
            ),
          ]),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    slots = StreamController<List<Slot>>.broadcast();
    appointments = _MockAppointments();
    slotSubscriptions = 0;
  });

  tearDown(() => slots.close());

  // Cambio 2: sin citas, todo el horario del viernes 6 está libre.
  Future<void> pickDayAndHour(WidgetTester tester, String hour) async {
    slots.add(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(hour));
    await tester.pumpAndSettle();
  }

  FilledButton continueButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continuar'));

  testWidgets('muestra servicios con precio y la categoría preseleccionada', (tester) async {
    await pumpBooking(tester, categoria: 'vacunacion');
    slots.add(const []);
    await tester.pumpAndSettle();

    expect(find.text('Consulta · \$ 45.000'), findsOneWidget);
    expect(find.text('Vacuna · \$ 60.000'), findsOneWidget);
    final vacunaChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Vacuna · \$ 60.000'));
    expect(vacunaChip.selected, isTrue);
    // Cambio 2: cualquier servicio activo usa el horario de la clínica.
    expect(find.text('Elige un día resaltado en el calendario.'), findsOneWidget);
    // Una sola mascota: no se muestra el selector.
    expect(find.text('MASCOTA'), findsNothing);
  });

  testWidgets('con varias mascotas se elige cuál', (tester) async {
    await pumpBooking(tester, pets: const [luna, milo]);
    expect(find.text('MASCOTA'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Milo'), findsOneWidget);
  });

  testWidgets('sin mascotas lleva a registrarla', (tester) async {
    await pumpBooking(tester, pets: const []);
    expect(find.text('Para agendar una cita primero registra a tu mascota.'), findsOneWidget);
  });

  testWidgets('si otro usuario toma la hora mientras miras, desaparece en tiempo real',
      (tester) async {
    await pumpBooking(tester);
    await pickDayAndHour(tester, '9:00 a. m.');
    expect(continueButton(tester).onPressed, isNotNull);

    // Otro dueño la reservó: Firestore emite la franja como reservado_temporal.
    slots.add([slot('2026-11-06', '09:00', estado: SlotStatus.reservadoTemporal)]);
    await tester.pumpAndSettle();

    expect(find.text('9:00 a. m.'), findsNothing);
    expect(find.text('10:00 a. m.'), findsOneWidget);
    expect(continueButton(tester).onPressed, isNull);
  });

  testWidgets('si el servidor dice que el horario ya fue tomado, avisa y refresca el calendario',
      (tester) async {
    when(() => appointments.request(
          clinicId: any(named: 'clinicId'),
          serviceId: any(named: 'serviceId'),
          petId: any(named: 'petId'),
          slotId: any(named: 'slotId'),
          comentario: any(named: 'comentario'),
        )).thenThrow(AppointmentFailure.slotUnavailable);

    await pumpBooking(tester);
    await pickDayAndHour(tester, '10:00 a. m.');
    await tester.enterText(find.byType(TextField), 'Vómito desde ayer');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Al solicitar la cita, la clínica podrá ver el historial médico de Luna'),
      findsOneWidget,
    );
    expect(find.text('Vómito desde ayer'), findsWidgets);
    final subscriptionsBefore = slotSubscriptions;

    await tester.tap(find.text('Solicitar Cita'));
    await tester.pumpAndSettle();

    expect(find.text('Este horario ya no está disponible, por favor selecciona otro'), findsOneWidget);
    expect(find.text('Agendar cita'), findsOneWidget); // volvió al calendario
    expect(slotSubscriptions, greaterThan(subscriptionsBefore)); // se pidió de nuevo
    expect(continueButton(tester).onPressed, isNull);
    verify(() => appointments.request(
          clinicId: 'c1',
          serviceId: 's1',
          petId: 'p1',
          slotId: '2026-11-06_10:00',
          comentario: 'Vómito desde ayer',
        )).called(1);
  });

  testWidgets('al solicitar con éxito abre el detalle de la cita', (tester) async {
    when(() => appointments.request(
          clinicId: any(named: 'clinicId'),
          serviceId: any(named: 'serviceId'),
          petId: any(named: 'petId'),
          slotId: any(named: 'slotId'),
          comentario: any(named: 'comentario'),
        )).thenAnswer((_) async => 'cita1');

    await pumpBooking(tester);
    await pickDayAndHour(tester, '9:00 a. m.');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitar Cita'));
    await tester.pumpAndSettle();

    expect(find.text('detalle cita1'), findsOneWidget);
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await pumpBooking(tester);
      slots.add(const []);
      await tester.pumpAndSettle();
      await tester.tap(find.text('6'));
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      useLargeText(tester);
      await pumpBooking(tester);
      slots.add(const []);
      await tester.pumpAndSettle();
      await tester.tap(find.text('6'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
    });
  });
}
