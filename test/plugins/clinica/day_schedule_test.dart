import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/opening_hours.dart';
import 'package:mascoti/core/domain/slot.dart';
import 'package:mascoti/plugins/clinica/domain/day_schedule.dart';

const fecha = '2026-10-20';
const hours30 = OpeningHours(apertura: '08:00', cierre: '12:00', duracionSlotMin: 30);

/// Servicios de prueba: consulta 30 min, cirugía 60, baño 45, vacuna 15.
const durations = {'consulta': 30, 'cirugia': 60, 'bano': 45, 'vacuna': 15};

Slot available(String hora, String serviceId, {double precio = 45000}) => Slot.at(
      fecha: fecha,
      hora: hora,
      estado: SlotStatus.disponible,
      serviceId: serviceId,
      precio: precio,
    );

Slot unavailable(String hora) =>
    Slot.at(fecha: fecha, hora: hora, estado: SlotStatus.noDisponible);

Slot locked(String hora, {String serviceId = 'consulta', bool ocupado = true}) => Slot.at(
      fecha: fecha,
      hora: hora,
      estado: ocupado ? SlotStatus.ocupado : SlotStatus.reservadoTemporal,
      serviceId: serviceId,
      precio: 45000,
    );

Map<String, Slot> byHora(List<Slot> slots) => {for (final s in slots) s.hora: s};

Set<String> conflictsOf(List<Slot> slots, {OpeningHours hours = hours30}) =>
    DaySchedule.conflicts(slots: byHora(slots), hours: hours, serviceDurations: durations);

void main() {
  group('generación de franjas', () {
    test('08:00-12:00 cada 30 min → 8 franjas', () {
      expect(DaySchedule.times(hours30, const []), [
        '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
      ]);
    });

    test('cada 15 y cada 60 min', () {
      const h15 = OpeningHours(apertura: '08:00', cierre: '09:00', duracionSlotMin: 15);
      expect(DaySchedule.times(h15, const []), ['08:00', '08:15', '08:30', '08:45']);
      const h60 = OpeningHours(apertura: '14:00', cierre: '18:00', duracionSlotMin: 60);
      expect(DaySchedule.times(h60, const []), ['14:00', '15:00', '16:00', '17:00']);
    });

    test('si el cierre no cae justo, la última franja termina antes del cierre', () {
      const h = OpeningHours(apertura: '08:00', cierre: '09:40', duracionSlotMin: 30);
      expect(DaySchedule.times(h, const []), ['08:00', '08:30', '09:00']);
    });

    test('horario inválido o sin espacio para una franja → ninguna', () {
      const reversed = OpeningHours(apertura: '18:00', cierre: '08:00', duracionSlotMin: 30);
      expect(DaySchedule.times(reversed, const []), isEmpty);
      const tooShort = OpeningHours(apertura: '08:00', cierre: '08:20', duracionSlotMin: 30);
      expect(DaySchedule.times(tooShort, const []), isEmpty);
    });

    test('incluye franjas guardadas fuera del horario actual, en orden', () {
      expect(DaySchedule.times(hours30, ['07:15', '12:30', '09:00']), [
        '07:15', '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
        '12:30',
      ]);
    });

    test('ordena por minutos, no como texto', () {
      const h = OpeningHours(apertura: '08:00', cierre: '11:00', duracionSlotMin: 60);
      expect(DaySchedule.times(h, ['09:45']),
          ['08:00', '09:00', '09:45', '10:00']);
    });
  });

  group('borradores', () {
    test('marcar disponible, no disponible y quitar', () {
      final saved = byHora([available('08:00', 'consulta'), unavailable('09:00')]);
      final result = DaySchedule.effective(fecha: fecha, saved: saved, edits: const {
        '08:00': ClearSlot(),
        '08:30': MarkAvailable(serviceId: 'vacuna', precio: 30000),
        '09:00': MarkAvailable(serviceId: 'consulta', precio: 45000),
        '10:00': MarkUnavailable(),
      });

      expect(result.keys, unorderedEquals(['08:30', '09:00', '10:00']));
      expect(result['08:30']!.estado, SlotStatus.disponible);
      expect(result['08:30']!.serviceId, 'vacuna');
      expect(result['08:30']!.precio, 30000);
      expect(result['08:30']!.inicio, DateTime(2026, 10, 20, 8, 30));
      expect(result['09:00']!.serviceId, 'consulta');
      expect(result['10:00']!.estado, SlotStatus.noDisponible);
      expect(result['10:00']!.serviceId, isNull);
    });

    test('las franjas ocupadas o reservadas ignoran los borradores', () {
      final saved = byHora([locked('08:00'), locked('09:00', ocupado: false)]);
      final result = DaySchedule.effective(fecha: fecha, saved: saved, edits: const {
        '08:00': ClearSlot(),
        '09:00': MarkUnavailable(),
      });
      expect(result, saved);
    });

    test('changes: solo lo que cambió, con sets y deletes ordenados', () {
      final saved = byHora([
        available('08:00', 'consulta'),
        unavailable('09:00'),
        available('10:00', 'consulta'),
      ]);
      final changes = DaySchedule.changes(fecha: fecha, saved: saved, edits: const {
        '10:00': MarkAvailable(serviceId: 'consulta', precio: 45000), // igual: no cuenta
        '09:00': ClearSlot(),
        '11:00': MarkUnavailable(),
        '08:30': MarkAvailable(serviceId: 'vacuna', precio: 30000),
        '11:30': ClearSlot(), // no existía: no cuenta
      });

      expect(changes.upserts.map((s) => s.hora), ['08:30', '11:00']);
      expect(changes.deletes, ['09:00']);
      expect(changes.length, 3);
    });

    test('changes: cambiar solo el servicio o el precio cuenta como cambio', () {
      final saved = byHora([available('08:00', 'consulta', precio: 45000)]);
      expect(
        DaySchedule.changes(fecha: fecha, saved: saved, edits: const {
          '08:00': MarkAvailable(serviceId: 'consulta', precio: 50000),
        }).length,
        1,
      );
      expect(
        DaySchedule.changes(fecha: fecha, saved: saved, edits: const {
          '08:00': MarkAvailable(serviceId: 'vacuna', precio: 45000),
        }).length,
        1,
      );
    });

    test('changes vacío sin borradores', () {
      expect(
        DaySchedule.changes(fecha: fecha, saved: byHora([unavailable('08:00')]), edits: const {})
            .isEmpty,
        isTrue,
      );
    });
  });

  group('solapamientos', () {
    test('servicio igual al tamaño de la franja, franjas contiguas → sin conflicto', () {
      expect(
        conflictsOf([
          available('08:00', 'consulta'),
          available('08:30', 'consulta'),
          available('09:00', 'consulta'),
        ]),
        isEmpty,
      );
    });

    test('servicio de 60 min pisa la franja siguiente con servicio', () {
      expect(
        conflictsOf([available('08:00', 'cirugia'), available('08:30', 'consulta')]),
        {'08:00', '08:30'},
      );
    });

    test('servicio de 60 min seguido de una franja libre y luego otra → válido', () {
      expect(
        conflictsOf([available('08:00', 'cirugia'), available('09:00', 'consulta')]),
        isEmpty,
      );
    });

    test('pisa una franja "No disponible"', () {
      expect(
        conflictsOf([available('08:00', 'cirugia'), unavailable('08:30')]),
        {'08:00', '08:30'},
      );
    });

    test('pisa una franja ocupada o reservada', () {
      expect(conflictsOf([available('08:00', 'cirugia'), locked('08:30')]),
          {'08:00', '08:30'});
      expect(conflictsOf([available('08:00', 'cirugia'), locked('08:30', ocupado: false)]),
          {'08:00', '08:30'});
    });

    test('una franja ocupada larga cubre la siguiente que se quiere usar', () {
      expect(
        conflictsOf([locked('08:00', serviceId: 'cirugia'), available('08:30', 'consulta')]),
        {'08:00', '08:30'},
      );
    });

    test('dos franjas bloqueadas que se pisan no cuentan (no se pueden corregir)', () {
      expect(
        conflictsOf([locked('08:00', serviceId: 'cirugia'), locked('08:30')]),
        isEmpty,
      );
    });

    test('duración que no es múltiplo de la franja (45 min sobre franjas de 30)', () {
      expect(conflictsOf([available('08:00', 'bano'), available('08:30', 'consulta')]),
          {'08:00', '08:30'});
      expect(conflictsOf([available('08:00', 'bano'), available('09:00', 'consulta')]),
          isEmpty);
    });

    test('servicio más corto que la franja (15 min sobre 30) no pisa nada', () {
      expect(conflictsOf([available('08:00', 'vacuna'), available('08:30', 'vacuna')]),
          isEmpty);
    });

    test('termina después del cierre', () {
      expect(conflictsOf([available('11:30', 'cirugia')]), {'11:30'});
      expect(conflictsOf([available('11:00', 'cirugia')]), isEmpty, reason: 'termina 12:00');
      expect(conflictsOf([available('11:30', 'consulta')]), isEmpty);
    });

    test('una franja ocupada que pasa del cierre no bloquea el guardado', () {
      expect(conflictsOf([locked('11:30', serviceId: 'cirugia')]), isEmpty);
    });

    test('"No disponible" no tiene duración propia: no pisa a la siguiente', () {
      expect(conflictsOf([unavailable('08:00'), available('08:30', 'consulta')]), isEmpty);
      expect(conflictsOf([unavailable('11:30')]), isEmpty);
    });

    test('servicio desconocido (desactivado) dura lo que una franja', () {
      expect(conflictsOf([available('08:00', 'borrado'), available('08:30', 'consulta')]),
          isEmpty);
      expect(
        DaySchedule.durationOf(available('08:00', 'borrado'), durations, 30),
        30,
      );
    });

    test('una franja fuera del horario también se valida', () {
      expect(conflictsOf([available('07:45', 'consulta'), available('08:00', 'consulta')]),
          {'07:45', '08:00'});
    });

    test('varios conflictos a la vez', () {
      expect(
        conflictsOf([
          available('08:00', 'cirugia'),
          available('08:30', 'consulta'),
          available('10:00', 'consulta'),
          available('11:30', 'cirugia'),
        ]),
        {'08:00', '08:30', '11:30'},
      );
    });
  });

  group('vista del día (build)', () {
    test('clasifica cada franja y marca las cubiertas', () {
      final plan = DaySchedule.build(
        fecha: fecha,
        hours: hours30,
        saved: byHora([
          available('08:00', 'cirugia'),
          unavailable('09:00'),
          locked('10:00'),
        ]),
        edits: const {},
        serviceDurations: durations,
      );
      final kinds = {for (final f in plan.franjas) f.hora: f.kind};

      expect(kinds, {
        '08:00': FranjaKind.available,
        '08:30': FranjaKind.covered,
        '09:00': FranjaKind.unavailable,
        '09:30': FranjaKind.empty,
        '10:00': FranjaKind.locked,
        '10:30': FranjaKind.empty,
        '11:00': FranjaKind.empty,
        '11:30': FranjaKind.empty,
      });
      expect(plan.franjas[1].coveredBy, '08:00');
      expect(plan.hasConflicts, isFalse);
    });

    test('marca editadas y en conflicto según los borradores', () {
      final plan = DaySchedule.build(
        fecha: fecha,
        hours: hours30,
        saved: byHora([available('08:30', 'consulta')]),
        edits: const {'08:00': MarkAvailable(serviceId: 'cirugia', precio: 200000)},
        serviceDurations: durations,
      );
      final f = {for (final f in plan.franjas) f.hora: f};

      expect(f['08:00']!.edited, isTrue);
      expect(f['08:30']!.edited, isFalse);
      expect(f['08:00']!.conflict, isTrue);
      expect(f['08:30']!.conflict, isTrue);
      expect(plan.conflicts, {'08:00', '08:30'});
    });

    test('quitar una franja guardada la deja vacía y editada', () {
      final plan = DaySchedule.build(
        fecha: fecha,
        hours: hours30,
        saved: byHora([unavailable('08:00')]),
        edits: const {'08:00': ClearSlot()},
        serviceDurations: durations,
      );
      expect(plan.franjas.first.kind, FranjaKind.empty);
      expect(plan.franjas.first.edited, isTrue);
    });
  });

  group('franjas pasadas', () {
    final now = DateTime(2026, 10, 20, 9, 15);

    test('ayer y las de hoy que ya empezaron son pasadas', () {
      expect(DaySchedule.isPast('2026-10-19', '17:00', now), isTrue);
      expect(DaySchedule.isPast(fecha, '09:00', now), isTrue);
      expect(DaySchedule.isPast(fecha, '09:15', now), isTrue);
    });

    test('las que no han empezado y los días siguientes no', () {
      expect(DaySchedule.isPast(fecha, '09:30', now), isFalse);
      expect(DaySchedule.isPast('2026-10-21', '08:00', now), isFalse);
    });
  });
}
