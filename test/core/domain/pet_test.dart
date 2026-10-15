import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/pet.dart';

void main() {
  final doc = <String, dynamic>{
    'ownerUid': 'ana',
    'nombre': 'Luna',
    'especie': 'perro',
    'raza': 'Criolla',
    'sexo': 'hembra',
    'fechaNacimiento': Timestamp.fromDate(DateTime(2023, 9, 1)),
    'fotoPath': 'ana/p1/foto.jpg',
    'alergias': ['pollo', 3],
    'condiciones': <String>[],
    'contactoEmergencia': {'nombre': 'Ana', 'telefono': '3001234567'},
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
  };

  test('fromMap lee todos los campos', () {
    final pet = Pet.fromMap('p1', doc);
    expect(pet.especie, PetSpecies.perro);
    expect(pet.sexo, PetSex.hembra);
    expect(pet.fechaNacimiento, DateTime(2023, 9, 1));
    expect(pet.fotoPath, 'ana/p1/foto.jpg');
    expect(pet.alergias, ['pollo']); // se descartan valores que no son texto
    expect(pet.contactoEmergencia,
        const EmergencyContact(nombre: 'Ana', telefono: '3001234567'));
  });

  test('toMap → fromMap conserva los datos (valores en español)', () {
    final pet = Pet.fromMap('p1', doc);
    final map = pet.toMap();
    expect(map['especie'], 'perro');
    expect(map['sexo'], 'hembra');
    expect(map.containsKey('fotoUrl'), isFalse);
    expect(Pet.fromMap('p1', map), pet);
  });

  test('campos opcionales vacíos', () {
    final pet = Pet.fromMap('p2', {'ownerUid': 'ana', 'nombre': 'Michi', 'especie': 'gato'});
    expect(pet.sexo, isNull);
    expect(pet.raza, isNull);
    expect(pet.alergias, isEmpty);
    expect(pet.contactoEmergencia, isNull);
    expect(pet.toMap()['sexo'], isNull);
  });

  test('copyWith', () {
    final pet = Pet.fromMap('p1', doc);
    final updated = pet.copyWith(nombre: 'Luna B', alergias: const ['pollo', 'res']);
    expect(updated.nombre, 'Luna B');
    expect(updated.alergias, ['pollo', 'res']);
    expect(updated.especie, pet.especie);
    expect(updated.id, pet.id);
  });

  test('especies: valores de Firestore y relación con lo que atiende la clínica', () {
    expect(PetSpecies.values.map((s) => s.value),
        ['perro', 'gato', 'ave', 'roedor', 'reptil', 'granja', 'exotico']);
    expect(PetSpecies.perro.animalType, AnimalType.perros);
    expect(PetSpecies.granja.animalType, AnimalType.granja);
    // Cada especie corresponde a un tipo distinto de clínica.
    expect(PetSpecies.values.map((s) => s.animalType).toSet(), AnimalType.values.toSet());
    expect(PetSpecies.fromValue('dragon'), PetSpecies.exotico);
    expect(PetSex.fromValue('otro'), isNull);
  });

  test('resumen "Especie · edad"', () {
    final now = DateTime(2026, 10, 15);
    expect(Pet.fromMap('p1', doc).summary(now), 'Perro · 3 años');
    expect(Pet.fromMap('p2', {'nombre': 'X', 'especie': 'gato'}).summary(now), 'Gato');
  });
}
