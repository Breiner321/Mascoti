import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/plugins/clinica/data/patients_repository.dart';
import 'package:mascoti/plugins/clinica/domain/patient.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late PatientsRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = PatientsRepository(firestore: firestore);
  });

  Future<void> addPet(String id, String nombre, List<String> clinicas) =>
      firestore.doc('pets/$id').set({
        'ownerUid': 'ana',
        'nombre': nombre,
        'especie': 'perro',
        'codigoPaciente': 'MSC-7K4P',
        'clinicasAutorizadas': clinicas,
      });

  test('lista solo las mascotas que autorizaron a la clínica, por nombre', () async {
    await addPet('p1', 'toby', ['c1']);
    await addPet('p2', 'Luna', ['c1', 'c2']);
    await addPet('p3', 'Max', ['c2']);
    await addPet('p4', 'Kira', []);

    final pets = await repository.watchPatients('c1').first;

    expect(pets.map((p) => p.nombre), ['Luna', 'toby']);
    expect(pets.first.especie, PetSpecies.perro);
  });

  test('una mascota que no existe se entrega como null', () async {
    await addPet('p1', 'Toby', ['c1']);

    expect((await repository.watchPatient('p1').first)?.nombre, 'Toby');
    expect(await repository.watchPatient('nada').first, isNull);
  });

  test('guarda el nombre del dueño al vincular y lo entrega por petId', () async {
    await repository.saveOwnerName(clinicId: 'c1', petId: 'p1', duenoNombre: 'Ana Pérez');
    await repository.saveOwnerName(clinicId: 'c2', petId: 'p9', duenoNombre: 'Otro');

    final doc = await firestore.doc('clinics/c1/pacientes/p1').get();
    expect(doc.data()!['duenoNombre'], 'Ana Pérez');
    expect(doc.data()!['vinculadoAt'], isNotNull);
    expect(await repository.watchOwnerNames('c1').first, {'p1': 'Ana Pérez'});
  });

  group('búsqueda de pacientes', () {
    const patient = Patient(
      pet: Pet(
        id: 'p1',
        ownerUid: 'ana',
        nombre: 'Ñoño',
        especie: PetSpecies.gato,
        raza: 'Siamés',
        codigoPaciente: 'MSC-7K4P',
      ),
      duenoNombre: 'Ana Pérez',
    );

    test('por nombre, dueño, código, especie o raza, sin tildes ni mayúsculas', () {
      expect(patient.matches(''), isTrue);
      expect(patient.matches('nono'), isTrue);
      expect(patient.matches('PEREZ'), isTrue);
      expect(patient.matches('msc-7k'), isTrue);
      expect(patient.matches('gato'), isTrue);
      expect(patient.matches('siames'), isTrue);
      expect(patient.matches('perro'), isFalse);
    });
  });
}
