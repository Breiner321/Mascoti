import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/appointments_providers.dart';
import 'package:mascoti/core/data/appointments_repository.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/reservas/presentation/dueno/appointment_detail_page.dart';
import 'package:mascoti/plugins/reservas/presentation/dueno/booking_logic.dart';
import 'package:mascoti/plugins/reservas/presentation/dueno/booking_providers.dart';
import 'package:mocktail/mocktail.dart';

import 'fakes.dart';

class _MockAppointments extends Mock implements AppointmentsRepository {}

void main() {
  // Cita el 6 de noviembre a las 9:00 en Bogotá.
  final inicio = BogotaTime.at(2026, 11, 6, 9);
  late _MockAppointments repo;
  late List<Uri> opened;

  setUp(() {
    repo = _MockAppointments();
    opened = [];
  });

  Future<void> pumpDetail(WidgetTester tester, Appointment a, {required DateTime now}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentsRepositoryProvider.overrideWithValue(repo),
          appointmentProvider.overrideWith((ref, id) => Stream.value(a)),
          bookingClinicProvider.overrideWith((ref, id) => Stream.value(clinic)),
          bookingClockProvider.overrideWithValue(() => now),
          bookingUrlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AppointmentDetailPage(appointmentId: a.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ButtonStyleButton cancelButton(WidgetTester tester) =>
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancelar cita'));

  testWidgets('faltando más de 2 horas se puede cancelar', (tester) async {
    when(() => repo.cancel('a1')).thenAnswer((_) async {});
    await pumpDetail(
      tester,
      appointment('a1', inicio: inicio, estado: AppointmentStatus.confirmada),
      now: BogotaTime.at(2026, 11, 5, 18),
    );

    expect(find.text('Confirmada'), findsOneWidget);
    expect(find.text('Calle 10 # 20-30'), findsOneWidget);
    expect(cancelButton(tester).onPressed, isNotNull);
    expect(find.text(BookingLogic.cancelTooLate), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar cita'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cancelar la cita?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar cita'));
    await tester.pumpAndSettle();

    verify(() => repo.cancel('a1')).called(1);
    expect(find.text('Cita cancelada'), findsOneWidget);
  });

  testWidgets('faltando menos de 2 horas el botón queda deshabilitado con la explicación',
      (tester) async {
    await pumpDetail(
      tester,
      appointment('a1', inicio: inicio),
      now: BogotaTime.at(2026, 11, 6, 7, 30),
    );

    expect(cancelButton(tester).onPressed, isNull);
    expect(find.text(BookingLogic.cancelTooLate), findsOneWidget);
    verifyNever(() => repo.cancel(any()));
  });

  testWidgets('rechazada: muestra el motivo y no ofrece cancelar', (tester) async {
    await pumpDetail(
      tester,
      appointment('a1',
          inicio: inicio, estado: AppointmentStatus.rechazada, motivoRechazo: 'Sin veterinario'),
      now: BogotaTime.at(2026, 11, 1),
    );

    expect(find.text('Rechazada'), findsOneWidget);
    expect(find.text('Motivo: Sin veterinario'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancelar cita'), findsNothing);
  });

  testWidgets('"Llamar a la clínica" y "Cómo llegar" abren el teléfono y el mapa', (tester) async {
    await pumpDetail(tester, appointment('a1', inicio: inicio), now: BogotaTime.at(2026, 11, 1));

    await tester.tap(find.text('Llamar a la clínica'));
    await tester.tap(find.text('Cómo llegar'));
    await tester.pumpAndSettle();

    expect(opened.map((u) => u.scheme), ['tel', 'geo']);
  });
}
