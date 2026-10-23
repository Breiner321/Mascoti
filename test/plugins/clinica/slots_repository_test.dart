import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/core/domain/slot.dart';
import 'package:mascoti/plugins/clinica/data/slots_repository.dart';
import 'package:mascoti/plugins/clinica/domain/day_schedule.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SlotsRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SlotsRepository(firestore: firestore);
  });

  Future<void> seed(String fecha, String hora, Map<String, dynamic> extra) =>
      firestore.doc('clinics/c1/slots/${fecha}_$hora').set({
        'fecha': fecha,
        'hora': hora,
        'inicio': Timestamp.fromDate(BogotaTime.tryParse(fecha, hora)!),
        ...extra,
      });

  test('watchDay: solo las franjas de esa fecha, por hora', () async {
    await seed('2026-10-20', '08:00', {'estado': 'disponible', 'serviceId': 's1', 'precio': 45000});
    await seed('2026-10-20', '09:00', {'estado': 'no_disponible'});
    await seed('2026-10-21', '08:00', {'estado': 'disponible', 'serviceId': 's1'});

    final day = await repo.watchDay('c1', '2026-10-20').first;
    expect(day.keys, unorderedEquals(['08:00', '09:00']));
    expect(day['08:00']!.estado, SlotStatus.disponible);
    expect(day['08:00']!.precio, 45000);
    expect(day['09:00']!.estado, SlotStatus.noDisponible);
  });

  test('watchConfiguredDays: fechas del mes con franjas', () async {
    await seed('2026-09-30', '08:00', {'estado': 'disponible', 'serviceId': 's1'});
    await seed('2026-10-01', '08:00', {'estado': 'disponible', 'serviceId': 's1'});
    await seed('2026-10-20', '08:00', {'estado': 'no_disponible'});
    await seed('2026-10-20', '09:00', {'estado': 'no_disponible'});
    await seed('2026-10-31', '17:00', {'estado': 'no_disponible'});
    await seed('2026-11-01', '08:00', {'estado': 'no_disponible'});

    final days = await repo.watchConfiguredDays('c1', DateTime(2026, 10)).first;
    expect(days, {'2026-10-01', '2026-10-20', '2026-10-31'});
  });

  test('saveDay: crea, reemplaza y borra en un solo lote', () async {
    await seed('2026-10-20', '08:00', {'estado': 'no_disponible'});
    await seed('2026-10-20', '09:00', {'estado': 'disponible', 'serviceId': 's1', 'precio': 1});

    await repo.saveDay(
      'c1',
      '2026-10-20',
      DayChanges(
        upserts: [
          Slot.at(
            fecha: '2026-10-20',
            hora: '08:00',
            estado: SlotStatus.disponible,
            serviceId: 's2',
            precio: 60000,
          ),
          Slot.at(fecha: '2026-10-20', hora: '10:30', estado: SlotStatus.noDisponible),
        ],
        deletes: const ['09:00'],
      ),
    );

    final docs = await firestore.collection('clinics/c1/slots').get();
    final byId = {for (final d in docs.docs) d.id: d.data()};
    expect(byId.keys, unorderedEquals(['2026-10-20_08:00', '2026-10-20_10:30']));

    final ocho = byId['2026-10-20_08:00']!;
    expect(ocho['estado'], 'disponible');
    expect(ocho['serviceId'], 's2');
    expect(ocho['precio'], 60000, reason: 'copia del precio del servicio');
    expect(ocho['fecha'], '2026-10-20');
    expect(ocho['hora'], '08:00');
    expect((ocho['inicio'] as Timestamp).toDate().toUtc(), BogotaTime.at(2026, 10, 20, 8));

    final bloqueo = byId['2026-10-20_10:30']!;
    expect(bloqueo['estado'], 'no_disponible');
    expect(bloqueo['serviceId'], isNull);
    expect(bloqueo['precio'], isNull);
  });

  test('saveDay sin cambios no escribe nada', () async {
    await repo.saveDay('c1', '2026-10-20', const DayChanges(upserts: [], deletes: []));
    expect((await firestore.collection('clinics/c1/slots').get()).size, 0);
  });
}
