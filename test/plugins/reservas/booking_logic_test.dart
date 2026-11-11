import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/schedule_exception.dart';
import 'package:mascoti/core/domain/slot.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/plugins/reservas/presentation/dueno/booking_logic.dart';

import 'fakes.dart';

void main() {
  group('regla de las 2 horas (hora de Colombia)', () {
    // Cita el 5 de noviembre a las 10:00 en Bogotá = 15:00 UTC.
    final inicio = BogotaTime.at(2026, 11, 5, 10);

    test('la cita empieza a las 10:00 de Bogotá aunque el teléfono esté en otra zona', () {
      expect(inicio, DateTime.utc(2026, 11, 5, 15));
    });

    test('se puede cancelar faltando exactamente 2 horas (8:00 en Bogotá)', () {
      final a = appointment('a1', inicio: inicio);
      final now = BogotaTime.at(2026, 11, 5, 8);
      expect(a.ownerCanCancel(now), isTrue);
      expect(BookingLogic.cancelBlockedReason(a, now), isNull);
    });

    test('no se puede cancelar faltando 1 h 59 min', () {
      final a = appointment('a1', inicio: inicio, estado: AppointmentStatus.confirmada);
      final now = BogotaTime.at(2026, 11, 5, 8, 1);
      expect(a.ownerCanCancel(now), isFalse);
      expect(BookingLogic.cancelBlockedReason(a, now), BookingLogic.cancelTooLate);
    });

    test('el mismo instante expresado en otra zona da el mismo resultado', () {
      final a = appointment('a1', inicio: inicio);
      // 8:30 a. m. en Bogotá = 13:30 UTC = 14:30 en Madrid (UTC+1 en noviembre).
      final now = DateTime.utc(2026, 11, 5, 13, 30);
      expect(BookingLogic.cancelBlockedReason(a, now), BookingLogic.cancelTooLate);
      expect(BookingLogic.cancelBlockedReason(a, now.subtract(const Duration(hours: 1))), isNull);
    });

    test('una cita terminada no muestra motivo (el botón no aparece)', () {
      for (final estado in [
        AppointmentStatus.cancelada,
        AppointmentStatus.rechazada,
        AppointmentStatus.completada,
        AppointmentStatus.noAsistio,
        AppointmentStatus.expirada,
      ]) {
        final a = appointment('a1', inicio: inicio, estado: estado);
        expect(BookingLogic.cancelBlockedReason(a, BogotaTime.at(2026, 11, 1)), isNull);
      }
    });
  });

  group('días y horas con disponibilidad (Cambio 2)', () {
    // Jueves 5 de noviembre, 12:00 m. La clínica atiende los viernes de 9 a 11.
    final now = BogotaTime.at(2026, 11, 5, 12);

    test('días del mes con horas libres: los viernes que no han pasado', () {
      expect(
        BookingLogic.availableDays(
          clinic: clinic, durationMin: 30, year: 2026, month: 11, slots: const [], now: now),
        {'2026-11-06', '2026-11-13', '2026-11-20', '2026-11-27'},
      );
    });

    test('horas del día: franjas apartadas por otras citas no se ofrecen', () {
      final slots = [
        slot('2026-11-06', '09:30', estado: SlotStatus.reservadoTemporal),
        slot('2026-11-06', '10:00'), // 'disponible' (liberada): sí se ofrece
        slot('2026-11-13', '09:00', estado: SlotStatus.ocupado), // otro día
      ];
      expect(
        BookingLogic.hoursOf(
            clinic: clinic, durationMin: 30, fecha: '2026-11-06', slots: slots, now: now),
        ['09:00', '10:00', '10:30'],
      );
      // Un servicio de 60 min necesita 2 franjas libres seguidas.
      expect(
        BookingLogic.hoursOf(
            clinic: clinic, durationMin: 60, fecha: '2026-11-06', slots: slots, now: now),
        ['10:00'],
      );
    });

    test('un bloqueo de la clínica quita el día', () {
      const vacaciones = ScheduleException(
          tipo: ExceptionType.bloqueo, fechaInicio: '2026-11-13', fechaFin: '2026-11-20');
      expect(
        BookingLogic.availableDays(clinic: clinic, durationMin: 30, year: 2026, month: 11,
            slots: const [], now: now, exceptions: const [vacaciones]),
        {'2026-11-06', '2026-11-27'},
      );
    });

    test('sin horario configurado no hay días', () {
      const sinHorario = Clinic(
          id: 'c2', ownerUid: 'v', nombre: 'X', telefono: '', direccion: '', lat: 0, lng: 0);
      expect(
        BookingLogic.availableDays(
            clinic: sinHorario, durationMin: 30, year: 2026, month: 11, slots: const [], now: now),
        isEmpty,
      );
    });
  });

  group('Mis citas', () {
    final now = BogotaTime.at(2026, 11, 5, 12);

    test('Próximas: activas por venir (la más cercana primero); el resto al Historial', () {
      final list = [
        appointment('lejana', inicio: BogotaTime.at(2026, 11, 20, 9)),
        appointment('cercana',
            inicio: BogotaTime.at(2026, 11, 6, 9), estado: AppointmentStatus.confirmada),
        appointment('rechazada',
            inicio: BogotaTime.at(2026, 11, 7, 9), estado: AppointmentStatus.rechazada),
        appointment('vieja',
            inicio: BogotaTime.at(2026, 10, 1, 9), estado: AppointmentStatus.completada),
        // Confirmada que empezó hace 30 min: sigue en Próximas (tolerancia de 60).
        appointment('en_curso',
            inicio: BogotaTime.at(2026, 11, 5, 11, 30), estado: AppointmentStatus.confirmada),
      ];
      final split = BookingLogic.split(list, now);
      expect(split.upcoming.map((a) => a.id), ['en_curso', 'cercana', 'lejana']);
      expect(split.history.map((a) => a.id), ['rechazada', 'vieja']);
    });

    test('Tus clínicas: sin repetir, la más reciente primero', () {
      final list = [
        appointment('a', inicio: BogotaTime.at(2026, 10, 1)),
        appointment('b', inicio: BogotaTime.at(2026, 10, 9), clinicId: 'c2', clinicNombre: 'Sur'),
        appointment('c', inicio: BogotaTime.at(2026, 10, 5)),
      ];
      expect(BookingLogic.recentClinics(list).map((c) => c.id), ['c2', 'c1']);
    });
  });
}
