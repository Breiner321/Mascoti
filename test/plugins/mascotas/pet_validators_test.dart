import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/plugins/mascotas/domain/pet_validators.dart';

void main() {
  test('nombre obligatorio y de máximo 40 caracteres', () {
    expect(PetValidators.nombre(null), 'El nombre es obligatorio');
    expect(PetValidators.nombre('   '), 'El nombre es obligatorio');
    expect(PetValidators.nombre('Luna'), isNull);
    expect(PetValidators.nombre('a' * 40), isNull);
    expect(PetValidators.nombre('a' * 41), 'El nombre no puede superar 40 caracteres');
  });

  test('especie obligatoria', () {
    expect(PetValidators.especie(null), 'Selecciona la especie');
    expect(PetValidators.especie(PetSpecies.gato), isNull);
  });

  test('raza opcional de máximo 60 caracteres', () {
    expect(PetValidators.raza(null), isNull);
    expect(PetValidators.raza(''), isNull);
    expect(PetValidators.raza('b' * 61), 'La raza no puede superar 60 caracteres');
  });

  test('la fecha de nacimiento no puede ser futura', () {
    final now = DateTime(2026, 10, 16, 12);
    expect(PetValidators.fechaNacimiento(null, now), isNull);
    expect(PetValidators.fechaNacimiento(DateTime(2020, 1, 1), now), isNull);
    expect(PetValidators.fechaNacimiento(DateTime(2026, 10, 16), now), isNull);
    expect(PetValidators.fechaNacimiento(DateTime(2026, 10, 17), now),
        'La fecha de nacimiento no puede ser futura');
  });

  group('alergias y condiciones', () {
    test('no se agregan vacíos, repetidos ni demasiado largos', () {
      expect(PetValidators.tag('  ', []), 'Escribe un valor para agregarlo');
      expect(PetValidators.tag('Pollo', ['pollo']), 'Ya está en la lista');
      expect(PetValidators.tag('x' * 41, []), 'Máximo 40 caracteres');
      expect(PetValidators.tag('Pollo', ['Res']), isNull);
    });

    test('máximo 30 por lista (límite de las reglas)', () {
      final full = [for (var i = 0; i < 30; i++) 'alergia $i'];
      expect(PetValidators.tag('otra', full), 'Máximo 30 elementos');
    });
  });

  group('contacto de emergencia', () {
    test('es opcional', () {
      expect(PetValidators.contactoNombre('', ''), isNull);
      expect(PetValidators.contactoTelefono('', ''), isNull);
    });

    test('si se llena un campo, el otro es obligatorio', () {
      expect(PetValidators.contactoNombre('', '3001234567'),
          'Escribe el nombre del contacto');
      expect(PetValidators.contactoTelefono('', 'Ana'),
          'Escribe el teléfono del contacto');
    });

    test('el teléfono tiene exactamente 10 dígitos', () {
      expect(PetValidators.contactoTelefono('3001234567', 'Ana'), isNull);
      expect(PetValidators.contactoTelefono('300123456', 'Ana'),
          'El teléfono debe tener 10 dígitos');
      expect(PetValidators.contactoTelefono('30012345678', 'Ana'),
          'El teléfono debe tener 10 dígitos');
      expect(PetValidators.contactoTelefono('300-123-45', 'Ana'),
          'El teléfono debe tener 10 dígitos');
    });
  });

  test('solo se aceptan fotos JPG o PNG', () {
    expect(PetValidators.imageType('foto.jpg', null), PetImageType.jpg);
    expect(PetValidators.imageType('FOTO.JPEG', null), PetImageType.jpg);
    expect(PetValidators.imageType('foto.png', null), PetImageType.png);
    expect(PetValidators.imageType('sin_extension', 'image/png'), PetImageType.png);
    expect(PetValidators.imageType('foto.heic', 'image/heic'), isNull);
    expect(PetValidators.imageType('foto.webp', null), isNull);
  });
}
