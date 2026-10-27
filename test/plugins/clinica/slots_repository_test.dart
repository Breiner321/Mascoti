import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/core/domain/slot.dart';
import 'package:mascoti/plugins/clinica/data/slots_repository.dart';

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
}
