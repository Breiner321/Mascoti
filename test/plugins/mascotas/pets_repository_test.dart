import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/plugins/mascotas/data/pets_repository.dart';
import 'package:mascoti/core/domain/patient_code.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/plugins/mascotas/domain/pet_photo.dart';

import 'fakes.dart';

void main() {
  group('PetsRepository', () {
    test('devuelve solo las mascotas del dueño, la más reciente primero',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('pets').add({
        'ownerUid': 'ana',
        'nombre': 'Luna',
        'especie': 'perro',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore.collection('pets').add({
        'ownerUid': 'ana',
        'nombre': 'Michi',
        'especie': 'gato',
        'createdAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      await firestore.collection('pets').add({
        'ownerUid': 'otro',
        'nombre': 'Max',
        'especie': 'perro',
      });

      final pets = await PetsRepository(firestore: firestore).watchPets('ana').first;

      expect(pets.map((p) => p.nombre), ['Michi', 'Luna']);
    });

    test('sin mascotas emite una lista vacía', () async {
      final pets =
          await PetsRepository(firestore: FakeFirebaseFirestore()).watchPets('ana').first;
      expect(pets, isEmpty);
    });
  });

  group('PetsRepository: guardar', () {
    late FakeFirebaseFirestore firestore;
    late FakePetStorage storage;
    late PetsRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      storage = FakePetStorage();
      repository = PetsRepository(firestore: firestore, storage: storage);
    });

    Pet luna(String id, {String? raza = 'Criolla', String? fotoPath}) => Pet(
          id: id,
          ownerUid: 'ana',
          nombre: 'Luna',
          especie: PetSpecies.perro,
          raza: raza,
          sexo: PetSex.hembra,
          fechaNacimiento: DateTime(2023, 9, 1),
          fotoPath: fotoPath,
          alergias: const ['Pollo'],
          contactoEmergencia:
              const EmergencyContact(nombre: 'Ana', telefono: '3001234567'),
        );

    Future<Map<String, dynamic>> doc(String id) async =>
        (await firestore.collection('pets').doc(id).get()).data()!;

    test('crea la mascota con fecha de creación del servidor', () async {
      final id = repository.newPetId();
      final stages = <PetSaveStage>[];

      final result = await repository.savePet(luna(id), isNew: true, onStage: stages.add);

      final data = await doc(id);
      expect(result.petId, id);
      expect(result.photoFailed, isFalse);
      expect(stages, [PetSaveStage.saving]);
      expect(data['nombre'], 'Luna');
      expect(data['especie'], 'perro');
      expect(data['alergias'], ['Pollo']);
      expect(data['contactoEmergencia'], {'nombre': 'Ana', 'telefono': '3001234567'});
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['fotoPath'], isNull);
    });

    test('editar cambia los datos, borra los opcionales vacíos y conserva createdAt',
        () async {
      await repository.savePet(luna('p1'), isNew: true);
      final createdAt = (await doc('p1'))['createdAt'];

      await repository.savePet(
        luna('p1', raza: null).copyWith(nombre: 'Luna Lunera'),
        isNew: false,
      );

      final data = await doc('p1');
      expect(data['nombre'], 'Luna Lunera');
      expect(data['raza'], isNull);
      expect(data['createdAt'], createdAt);
    });

    test('con foto: la sube a {ownerUid}/{petId}/foto.jpg y guarda la ruta', () async {
      final stages = <PetSaveStage>[];

      final result = await repository.savePet(
        luna('p1'),
        isNew: true,
        photo: PetPhoto(bytes: tinyPng),
        onStage: stages.add,
      );

      expect(result.photoFailed, isFalse);
      expect(stages, [PetSaveStage.saving, PetSaveStage.uploadingPhoto]);
      expect(storage.uploads, ['ana/p1/foto.jpg']);
      expect((await doc('p1'))['fotoPath'], 'ana/p1/foto.jpg');
    });

    test('si la foto falla, la mascota queda guardada sin foto y se puede reintentar',
        () async {
      storage.fail = true;

      final result = await repository.savePet(
        luna('p1'),
        isNew: true,
        photo: PetPhoto(bytes: tinyPng),
      );

      expect(result.photoFailed, isTrue);
      expect((await doc('p1'))['nombre'], 'Luna');
      expect((await doc('p1'))['fotoPath'], isNull);

      storage.fail = false;
      expect(await repository.uploadPhoto(luna('p1'), PetPhoto(bytes: tinyPng)), isTrue);
      expect((await doc('p1'))['fotoPath'], 'ana/p1/foto.jpg');
    });

    test('cambiar una foto JPG por una PNG borra la anterior', () async {
      await repository.savePet(luna('p1', fotoPath: 'ana/p1/foto.jpg'), isNew: true);

      await repository.uploadPhoto(
        luna('p1', fotoPath: 'ana/p1/foto.jpg'),
        PetPhoto(bytes: tinyPng, png: true),
      );

      expect((await doc('p1'))['fotoPath'], 'ana/p1/foto.png');
      expect(storage.deleted, ['ana/p1/foto.jpg']);
    });

    test('al crear asigna el código de paciente y lo registra en codigosPaciente',
        () async {
      final codes = ['MSC-7K4P'].iterator;
      repository = PetsRepository(
        firestore: firestore,
        storage: storage,
        generateCode: () => (codes..moveNext()).current,
      );

      await repository.savePet(luna('p1'), isNew: true);

      final data = await doc('p1');
      expect(data['codigoPaciente'], 'MSC-7K4P');
      expect(data['clinicasAutorizadas'], isEmpty);
      final code = (await firestore.doc('codigosPaciente/MSC-7K4P').get()).data()!;
      expect(code['petId'], 'p1');
      expect(code['ownerUid'], 'ana');
    });

    test('editar no toca el código ni las clínicas autorizadas', () async {
      await repository.savePet(luna('p1'), isNew: true);
      final code = (await doc('p1'))['codigoPaciente'];
      await firestore.doc('pets/p1').update({'clinicasAutorizadas': ['c1']});

      // El formulario podría traer una versión vieja de la mascota.
      await repository.savePet(luna('p1').copyWith(nombre: 'Luna B'), isNew: false);

      final data = await doc('p1');
      expect(data['nombre'], 'Luna B');
      expect(data['codigoPaciente'], code);
      expect(data['clinicasAutorizadas'], ['c1']);
    });

    test('ensurePatientCode asigna código a una mascota de la semana 2 una sola vez',
        () async {
      await firestore.doc('pets/p1').set({'ownerUid': 'ana', 'nombre': 'Luna', 'especie': 'perro'});
      final antigua = (await repository.watchPet('p1').first)!;
      expect(antigua.codigoPaciente, isNull);

      final code = await repository.ensurePatientCode(antigua);

      expect(PatientCode.isValid(code), isTrue);
      expect((await doc('p1'))['codigoPaciente'], code);
      expect((await firestore.doc('codigosPaciente/$code').get()).data()!['petId'], 'p1');
      final conCodigo = (await repository.watchPet('p1').first)!;
      expect(await repository.ensurePatientCode(conCodigo), code);
    });

    test('revokeClinic quita solo esa clínica', () async {
      await repository.savePet(luna('p1'), isNew: true);
      await firestore.doc('pets/p1').update({'clinicasAutorizadas': ['c1', 'c2']});

      await repository.revokeClinic('p1', 'c1');

      expect((await doc('p1'))['clinicasAutorizadas'], ['c2']);
    });

    test('watchPet emite la mascota, o null si no existe', () async {
      await repository.savePet(luna('p1'), isNew: true);

      expect((await repository.watchPet('p1').first)?.nombre, 'Luna');
      expect(await repository.watchPet('no-existe').first, isNull);
    });
  });

  group('Pet', () {
    final now = DateTime(2026, 10, 2);

    Pet born(DateTime? date) => Pet(
          id: 'p',
          ownerUid: 'ana',
          nombre: 'Luna',
          especie: PetSpecies.perro,
          fechaNacimiento: date,
        );

    test('edad en años y meses', () {
      expect(born(DateTime(2023, 9, 1)).ageLabel(now), '3 años');
      expect(born(DateTime(2025, 10, 2)).ageLabel(now), '1 año');
      expect(born(DateTime(2026, 5, 2)).ageLabel(now), '5 meses');
      expect(born(DateTime(2026, 9, 2)).ageLabel(now), '1 mes');
      expect(born(DateTime(2026, 9, 20)).ageLabel(now), 'Menos de 1 mes');
      expect(born(null).ageLabel(now), isNull);
    });

    test('resumen "Especie · edad"', () {
      expect(born(DateTime(2023, 9, 1)).summary(now), 'Perro · 3 años');
      expect(born(null).summary(now), 'Perro');
    });

    test('fromMap y toMap son simétricos', () {
      final pet = Pet(
        id: 'p1',
        ownerUid: 'ana',
        nombre: 'Luna',
        especie: PetSpecies.perro,
        sexo: PetSex.hembra,
        fechaNacimiento: DateTime(2023, 9, 1),
      );
      final copy = Pet.fromMap('p1', pet.toMap());
      expect(copy.nombre, 'Luna');
      expect(copy.fechaNacimiento, DateTime(2023, 9, 1));
      expect(copy.sexo, PetSex.hembra);
    });
  });

  test('AppUser lee onboardingVisto (falso si no existe)', () {
    expect(
      AppUser.fromMap('u1', {'role': 'dueno', 'onboardingVisto': true}).onboardingVisto,
      isTrue,
    );
    expect(AppUser.fromMap('u1', {'role': 'dueno'}).onboardingVisto, isFalse);
  });
}
