import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/plugins/reservas/data/dueno/booking_repository.dart';

import 'fakes.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late BookingRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = BookingRepository(firestore: firestore);
  });

  test('franjas del mes: solo las fechas de ese mes', () async {
    final slots = firestore.collection('clinics/c1/slots');
    for (final s in [
      slot('2026-10-31', '09:00'),
      slot('2026-11-01', '09:00'),
      slot('2026-11-30', '17:00'),
      slot('2026-12-01', '09:00'),
    ]) {
      await slots.doc(s.id).set(s.toMap());
    }

    final month = await repository.watchMonthSlots('c1', 2026, 11).first;
    expect(month.map((s) => s.id).toSet(), {'2026-11-01_09:00', '2026-11-30_17:00'});
  });

  test('servicios activos por nombre', () async {
    final services = firestore.collection('clinics/c1/services');
    await services.doc('s2').set(vacuna.toMap());
    await services.doc('s1').set(consulta.toMap());
    await services.doc('s3').set({...consulta.toMap(), 'nombre': 'Baño', 'activo': false});

    final list = await repository.watchActiveServices('c1').first;
    expect(list.map((s) => s.nombre), ['Consulta', 'Vacuna']);
  });

  test('mascotas del dueño por nombre, sin las de otros', () async {
    await firestore.doc('pets/p2').set(milo.toMap());
    await firestore.doc('pets/p1').set(luna.toMap());
    await firestore.doc('pets/x').set({...luna.toMap(), 'ownerUid': 'otro', 'nombre': 'Rex'});

    final pets = await repository.watchPets('ana').first;
    expect(pets.map((p) => p.nombre), ['Luna', 'Milo']);
  });
}
