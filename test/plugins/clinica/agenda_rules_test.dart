import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/domain/schedule_exception.dart';
import 'package:mascoti/core/domain/weekly_schedule.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/plugins/clinica/domain/agenda_rules.dart';

void main() {
  test('franjas seleccionadas → rangos seguidos', () {
    expect(AgendaRules.contiguousRanges(['11:00', '09:30', '10:00'], 30),
        [('09:30', '10:30'), ('11:00', '11:30')]);
    expect(AgendaRules.contiguousRanges(['23:30'], 30), [('23:30', '23:59')]);
    expect(AgendaRules.contiguousRanges(const [], 30), isEmpty);
  });

  test('festivos sugeridos: solo en días de atención y no bloqueados', () {
    final weekdays = WeeklySchedule.standard; // domingo cerrado
    final sugeridos = AgendaRules.holidaySuggestions(
      desde: '2026-11-01',
      hasta: '2026-12-31',
      schedule: weekdays,
      exceptions: const [
        ScheduleException(
            tipo: ExceptionType.bloqueo, fechaInicio: '2026-12-24', fechaFin: '2026-12-26'),
      ],
    );
    // 8 dic es martes (abierto); 25 dic ya está bloqueado.
    expect(sugeridos.map((h) => h.fecha), ['2026-11-02', '2026-11-16', '2026-12-08']);
  });

  group('citas que chocan con un horario nuevo', () {
    final now = BogotaTime.at(2026, 11, 1, 9);
    Appointment cita(String id, String fecha, String hora,
            {AppointmentStatus estado = AppointmentStatus.confirmada, int? duracion = 30}) =>
        Appointment(
          id: id,
          clinicId: 'c1',
          clinicNombre: 'Vet',
          ownerUid: 'ana',
          petId: 'p1',
          petNombre: 'Luna',
          serviceId: 's1',
          serviceNombre: 'Consulta',
          precioAcordado: 1,
          slotId: '${fecha}_$hora',
          fecha: fecha,
          hora: hora,
          duracionMin: duracion,
          inicio: BogotaTime.tryParse(fecha, hora)!,
          estado: estado,
        );

    test('lista las activas por venir que quedan fuera, en orden', () {
      final list = [
        cita('domingo', '2026-11-08', '10:00'), // domingo cerrado
        cita('almuerzo', '2026-11-03', '12:30'), // en el descanso
        cita('larga', '2026-11-03', '11:30', duracion: 60), // cruza el descanso
        cita('bien', '2026-11-03', '09:00'),
        cita('cancelada', '2026-11-08', '09:00', estado: AppointmentStatus.cancelada),
        cita('pasada', '2026-10-25', '10:00'),
      ];
      final conflicts = AgendaRules.conflictsWith(
          appointments: list, schedule: WeeklySchedule.standard, slotMinutes: 30, now: now);
      expect(conflicts.map((a) => a.id), ['larga', 'almuerzo', 'domingo']);
    });
  });
}
