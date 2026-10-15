import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/plugins/mascotas/data/pets_repository.dart';
import 'package:mascoti/core/domain/pet.dart';

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
