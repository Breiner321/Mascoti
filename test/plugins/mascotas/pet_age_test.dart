import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/pet.dart';

void main() {
  String? age(DateTime birth, DateTime now) => Pet(
        id: 'p',
        ownerUid: 'ana',
        nombre: 'Luna',
        especie: PetSpecies.perro,
        fechaNacimiento: birth,
      ).ageLabel(now);

  test('cumple años el mismo día del mes', () {
    expect(age(DateTime(2024, 10, 16), DateTime(2026, 10, 16)), '2 años');
  });

  test('un día antes del cumpleaños todavía no suma el año', () {
    expect(age(DateTime(2024, 10, 17), DateTime(2026, 10, 16)), '1 año');
  });

  test('nacido un 29 de febrero', () {
    expect(age(DateTime(2024, 2, 29), DateTime(2025, 2, 28)), '11 meses');
    expect(age(DateTime(2024, 2, 29), DateTime(2025, 3, 1)), '1 año');
  });

  test('menores de un año se cuentan en meses', () {
    expect(age(DateTime(2026, 4, 16), DateTime(2026, 10, 16)), '6 meses');
    expect(age(DateTime(2026, 10, 1), DateTime(2026, 10, 16)), 'Menos de 1 mes');
  });

  test('sin fecha o con fecha futura no se muestra la edad', () {
    final pet = const Pet(id: 'p', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.gato);
    expect(pet.ageLabel(DateTime(2026, 10, 16)), isNull);
    expect(age(DateTime(2027, 1, 1), DateTime(2026, 10, 16)), isNull);
  });
}
