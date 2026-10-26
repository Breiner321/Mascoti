import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/data/appointments_providers.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/reservas/presentation/dueno/booking_providers.dart';
import 'package:mascoti/plugins/reservas/presentation/dueno/my_appointments_page.dart';

import 'fakes.dart';

void main() {
  testWidgets('Próximas e Historial con el estado de cada cita', (tester) async {
    final now = BogotaTime.at(2026, 11, 5, 12);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(owner),
          bookingClockProvider.overrideWithValue(() => now),
          ownerAppointmentsProvider.overrideWith((ref, uid) => Stream.value([
                appointment('p', inicio: BogotaTime.at(2026, 11, 6, 9)),
                appointment('c',
                    inicio: BogotaTime.at(2026, 11, 7, 9), estado: AppointmentStatus.confirmada),
                appointment('r',
                    inicio: BogotaTime.at(2026, 11, 8, 9),
                    estado: AppointmentStatus.rechazada,
                    motivoRechazo: 'Agenda llena'),
              ])),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const MyAppointmentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Confirmada'), findsOneWidget);
    expect(find.text('Rechazada'), findsNothing);
    expect(find.text('6 nov · 9:00 a. m.'), findsOneWidget);

    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    expect(find.text('Rechazada'), findsOneWidget);
    expect(find.text('Motivo: Agenda llena'), findsOneWidget);
  });
}
