import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/opening_hours.dart';
import 'package:mascoti/plugins/clinica/data/clinic_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class
class _MockCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockDoc extends Mock implements DocumentReference<Map<String, dynamic>> {}

void main() {
  late FakeFirebaseFirestore firestore;
  late ClinicRepository repo;

  const hours = OpeningHours(apertura: '09:00', cierre: '17:00', duracionSlotMin: 60);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repo = ClinicRepository(firestore: firestore);
    await firestore.doc('clinics/c1').set({
      'ownerUid': 'vet',
      'nombre': 'Vet Central',
      'telefono': '3001234567',
      'direccion': 'Calle 1',
      'lat': 4.6,
      'lng': -74.1,
      'estado': 'incompleto',
    });
  });

  Future<Clinic> current() async => (await repo.watchClinic('c1').first)!;

  /// Firestore simulado cuyo `clinics/c1.update` responde con [onUpdate].
  (_MockDoc, ClinicRepository) mockedRepo(Future<void> Function() onUpdate) {
    final doc = _MockDoc();
    final collection = _MockCollection();
    final mock = _MockFirestore();
    when(() => mock.collection('clinics')).thenReturn(collection);
    when(() => collection.doc('c1')).thenReturn(doc);
    when(() => doc.update(any())).thenAnswer((_) => onUpdate());
    return (doc, ClinicRepository(firestore: mock));
  }

  test('watchClinic emite la clínica y sus cambios en tiempo real', () async {
    final emitted = <Clinic?>[];
    final sub = repo.watchClinic('c1').listen(emitted.add);
    await pumpEventQueue();
    await firestore.doc('clinics/c1').update({
      'tiposAnimales': ['gatos'],
    });
    await pumpEventQueue();
    await sub.cancel();

    expect(emitted.first!.nombre, 'Vet Central');
    expect(emitted.first!.estado, ClinicStatus.incompleto);
    expect(emitted.last!.tiposAnimales, [AnimalType.gatos]);
  });

  test('watchClinic emite null si la clínica no existe', () async {
    expect(await repo.watchClinic('no-existe').first, isNull);
  });

  test('primer guardado: guarda el perfil y pasa a activo', () async {
    await repo.saveCareProfile(
      await current(),
      tiposAnimales: [AnimalType.perros, AnimalType.exoticos],
      atencionEmergencias: true,
      horarioBase: hours,
    );

    final data = (await firestore.doc('clinics/c1').get()).data()!;
    expect(data['tiposAnimales'], ['perros', 'exoticos']);
    expect(data['atencionEmergencias'], isTrue);
    expect(data['horarioBase'],
        {'apertura': '09:00', 'cierre': '17:00', 'duracionSlotMin': 60});
    expect(data['estado'], 'activo');
    // No toca campos que las reglas no permiten cambiar.
    expect(data['nombre'], 'Vet Central');
    expect(data['ownerUid'], 'vet');
  });

  test('guardados posteriores no envían estado', () async {
    await firestore.doc('clinics/c1').update({'estado': 'activo'});
    final clinic = await current();
    final (doc, mocked) = mockedRepo(() async {});

    await mocked.saveCareProfile(
      clinic,
      tiposAnimales: [AnimalType.gatos],
      atencionEmergencias: false,
      horarioBase: hours,
    );

    final sent = verify(() => doc.update(captureAny())).captured.single as Map;
    expect(sent.keys,
        unorderedEquals(['tiposAnimales', 'atencionEmergencias', 'horarioBase']));
  });

  test('permission-denied se convierte en ClinicPermissionDenied', () async {
    final clinic = await current();
    final (_, mocked) = mockedRepo(
      () => Future.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ),
    );

    await expectLater(
      mocked.saveCareProfile(
        clinic,
        tiposAnimales: [AnimalType.perros],
        atencionEmergencias: false,
        horarioBase: hours,
      ),
      throwsA(isA<ClinicPermissionDenied>()),
    );
  });

  test('otros errores de Firestore se propagan sin cambios', () async {
    final clinic = await current();
    final (_, mocked) = mockedRepo(
      () => Future.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
    );

    await expectLater(
      mocked.saveCareProfile(
        clinic,
        tiposAnimales: [AnimalType.perros],
        atencionEmergencias: false,
        horarioBase: hours,
      ),
      throwsA(isA<FirebaseException>()),
    );
  });
}
