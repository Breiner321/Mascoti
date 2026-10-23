import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/slot.dart';
import 'package:mascoti/core/format/bogota_time.dart';

void main() {
  test('Slot.at calcula inicio e id determinístico', () {
    final slot = Slot.at(
      fecha: '2026-10-15',
      hora: '09:30',
      estado: SlotStatus.disponible,
      serviceId: 's1',
      precio: 45000,
    );
    // 9:30 a. m. en Bogotá = 14:30 UTC, sin importar la zona del teléfono.
    expect(slot.inicio, DateTime.utc(2026, 10, 15, 14, 30));
    expect(slot.inicio, BogotaTime.at(2026, 10, 15, 9, 30));
    expect(() => Slot.at(fecha: '2026-02-30', hora: '09:00', estado: SlotStatus.disponible),
        throwsFormatException);
    expect(slot.id, '2026-10-15_09:30');
    expect(Slot.idFor('2026-10-15', '09:30'), slot.id);
  });

  test('toMap → fromMap conserva los datos (estado en español)', () {
    final slot = Slot.at(
      fecha: '2026-10-15',
      hora: '09:30',
      estado: SlotStatus.reservadoTemporal,
      serviceId: 's1',
      precio: 45000,
    );
    final map = slot.toMap();
    expect(map['estado'], 'reservado_temporal');
    expect(map['inicio'], isA<Timestamp>());
    expect(Slot.fromMap(map), slot);
  });

  test('franja "No disponible" sin servicio ni precio', () {
    final slot = Slot.fromMap({
      'fecha': '2026-10-15',
      'hora': '12:00',
      'estado': 'no_disponible',
    });
    expect(slot.estado, SlotStatus.noDisponible);
    expect(slot.serviceId, isNull);
    expect(slot.precio, isNull);
    // Sin `inicio` guardado, se calcula de fecha + hora.
    expect(slot.inicio, BogotaTime.at(2026, 10, 15, 12));
  });

  test('estados: valores de Firestore y bloqueo de edición (RF-06)', () {
    expect(SlotStatus.values.map((s) => s.value),
        ['disponible', 'no_disponible', 'reservado_temporal', 'ocupado']);
    expect(SlotStatus.ocupado.isLocked, isTrue);
    expect(SlotStatus.reservadoTemporal.isLocked, isTrue);
    expect(SlotStatus.disponible.isLocked, isFalse);
    expect(SlotStatus.noDisponible.isLocked, isFalse);
    expect(SlotStatus.fromValue('raro'), SlotStatus.noDisponible);
  });

  test('copyWith y dateKey', () {
    final slot = Slot.at(fecha: '2026-10-15', hora: '09:30', estado: SlotStatus.disponible);
    expect(slot.copyWith(estado: SlotStatus.noDisponible).estado, SlotStatus.noDisponible);
    expect(slot.copyWith(estado: SlotStatus.noDisponible).id, slot.id);
    expect(Slot.dateKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
  });
}
