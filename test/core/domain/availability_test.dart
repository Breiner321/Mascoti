import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/availability.dart';
import 'package:mascoti/core/domain/opening_hours.dart';
import 'package:mascoti/core/domain/schedule_exception.dart';
import 'package:mascoti/core/domain/weekly_schedule.dart';

/// Casos compartidos con functions/test/disponibilidad.test.ts.
Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/disponibilidad.json').readAsStringSync())
        as Map<String, dynamic>;

List<ScheduleException> _exceptions(Object? list) => [
      for (final (i, e) in (list as List).indexed)
        ScheduleException.tryFromMap('e$i', Map<String, dynamic>.from(e as Map))!,
    ];

void main() {
  final fixture = _fixture();
  final base = fixture['base'] as Map<String, dynamic>;

  group('casos compartidos (Dart = TypeScript)', () {
    for (final raw in fixture['casos'] as List) {
      final c = {...base, ...(raw as Map<String, dynamic>)};
      test(c['nombre'] as String, () {
        final result = Availability.startTimes(
          fecha: c['fecha'] as String,
          durationMin: c['duracionMin'] as int,
          schedule: WeeklySchedule.fromMap(Map<String, dynamic>.from(c['horario'] as Map)),
          settings: BookingSettings.fromMap(Map<String, dynamic>.from(c['reservas'] as Map)),
          now: DateTime.parse(c['ahora'] as String),
          exceptions: _exceptions(c['excepciones']),
          slotStates: Map<String, String>.from(c['franjas'] as Map),
        );
        expect(result, c['esperado']);
      });
    }
  });

  final schedule = WeeklySchedule.fromMap(Map<String, dynamic>.from(base['horario'] as Map));

  test('cellsFor: franjas que aparta un servicio', () {
    expect(Availability.cellsFor('09:00', 60, 30), ['09:00', '09:30']);
    expect(Availability.cellsFor('09:00', 45, 30), ['09:00', '09:30']);
    expect(Availability.cellsFor('09:00', 30, 30), ['09:00']);
    expect(Availability.cellsFor('09:00', 30, 15), ['09:00', '09:15']);
    expect(Availability.cellsFor('09:00', 0, 30), ['09:00']);
  });

  test('fitsSchedule: aviso al cambiar el horario', () {
    expect(Availability.fitsSchedule(
        fecha: '2026-11-02', hora: '09:00', durationMin: 60, schedule: schedule, slotMinutes: 30),
        isTrue);
    // Cruza el descanso.
    expect(Availability.fitsSchedule(
        fecha: '2026-11-02', hora: '09:30', durationMin: 60, schedule: schedule, slotMinutes: 30),
        isFalse);
    // Domingo cerrado.
    expect(Availability.fitsSchedule(
        fecha: '2026-11-01', hora: '09:00', durationMin: 30, schedule: schedule, slotMinutes: 30),
        isFalse);
  });

  test('dayCells: estados de la agenda de la clínica', () {
    final cells = Availability.dayCells(
      fecha: '2026-11-02',
      schedule: schedule,
      slotMinutes: 30,
      exceptions: [
        const ScheduleException(
          id: 'b1',
          tipo: ExceptionType.bloqueo,
          fechaInicio: '2026-11-02',
          fechaFin: '2026-11-02',
          desde: '11:00',
          hasta: '12:00',
          motivo: 'Capacitación',
        ),
      ],
      slotStates: {'08:30': 'ocupado', '09:00': 'disponible', '17:00': 'no_disponible'},
    );
    final byHour = {for (final c in cells) c.hora: c};
    expect(byHour.keys, ['08:00', '08:30', '09:00', '09:30', '10:30', '11:00', '11:30', '17:00']);
    expect(byHour['08:00']!.status, CellStatus.libre);
    expect(byHour['08:30']!.status, CellStatus.ocupada);
    expect(byHour['09:00']!.status, CellStatus.libre);
    expect(byHour['11:00']!.status, CellStatus.bloqueada);
    expect(byHour['11:00']!.exception?.motivo, 'Capacitación');
    // Franja antigua "No disponible" fuera del horario: se sigue mostrando.
    expect(byHour['17:00']!.status, CellStatus.bloqueada);
  });

  group('horario semanal', () {
    test('migración de horarioBase: todos los días abiertos igual', () {
      final migrated = WeeklySchedule.fromOpeningHours(
          const OpeningHours(apertura: '07:00', cierre: '19:00', duracionSlotMin: 30));
      for (final d in Weekday.values) {
        expect(migrated[d], const DayHours(abierto: true, apertura: '07:00', cierre: '19:00'));
      }
      expect(WeeklySchedule.fromMap(migrated.toMap()), migrated);
    });

    test('validaciones', () {
      expect(WeeklySchedule.standard.validate(30), isNull);
      expect(WeeklySchedule.standard.validate(60), isNull);
      final closed = WeeklySchedule({for (final d in Weekday.values) d: const DayHours.closed()});
      expect(closed.validate(30), 'Abre al menos un día de la semana');
      expect(const DayHours(abierto: true, apertura: '10:00', cierre: '09:00').validate(30),
          'La apertura debe ser antes del cierre');
      expect(const DayHours(abierto: true, descansoInicio: '07:00', descansoFin: '08:30').validate(30),
          'El descanso debe estar dentro del horario');
      expect(const DayHours(abierto: true, descansoInicio: '12:00').validate(30),
          'Indica el inicio y el fin del descanso');
      expect(const DayHours(abierto: true, apertura: '08:15').validate(30),
          'Usa horas en bloques de 30 minutos');
      expect(const DayHours(abierto: true, apertura: '08:15').validate(15), isNull);
      expect(Weekday.ofDate('2026-11-02'), Weekday.lun);
      expect(Weekday.ofDate('2026-11-01'), Weekday.dom);
    });
  });
}
