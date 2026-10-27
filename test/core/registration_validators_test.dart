import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/domain/registration.dart';

void main() {
  group('RF-01 validaciones de clínica', () {
    test('nombre comercial: obligatorio y mínimo 3 caracteres', () {
      expect(RegistrationValidators.clinicName(''), isNotNull);
      expect(RegistrationValidators.clinicName('ab'), isNotNull);
      expect(RegistrationValidators.clinicName('  Vet  '), isNull);
    });

    test('teléfono: exactamente 10 dígitos', () {
      expect(RegistrationValidators.phone('300123456'), isNotNull);
      expect(RegistrationValidators.phone('30012345678'), isNotNull);
      expect(RegistrationValidators.phone('300-123-45'), isNotNull);
      expect(RegistrationValidators.phone('3001234567'), isNull);
    });

    // La dirección ya no se valida como texto: debe escogerse de Google
    // Places con lat/lng. Ver test/core/widgets/address_autocomplete_field_test.dart.
  });

  test('payload de registro de clínica', () {
    const request = RegistrationRequest.clinic(
      ClinicRegistration(
        nombre: ' Vet Norte ',
        telefono: '3001234567',
        direccion: 'Calle 1',
        lat: 4.711,
        lng: -74.0721,
      ),
    );
    expect(request.toMap(), {
      'role': 'clinica',
      'clinica': {
        'nombre': 'Vet Norte',
        'telefono': '3001234567',
        'direccion': 'Calle 1',
        'lat': 4.711,
        'lng': -74.0721,
      },
    });
    expect(
      const RegistrationRequest.owner(
        OwnerRegistration(nombre: '  Ana   Pérez ', telefono: ' 3001234567 '),
      ).toMap(),
      {
        'role': 'dueno',
        'dueno': {'nombre': 'Ana Pérez', 'telefono': '3001234567'},
      },
    );
  });

  test('Cambio 1: nombre completo del dueño (3-60, espacios normalizados)', () {
    expect(RegistrationValidators.ownerName(''), 'El nombre completo es obligatorio');
    expect(RegistrationValidators.ownerName('   '), 'El nombre completo es obligatorio');
    expect(RegistrationValidators.ownerName('Al'), 'Mínimo 3 caracteres');
    expect(RegistrationValidators.ownerName('  Al  '), 'Mínimo 3 caracteres');
    // Los espacios internos se normalizan y cuentan como uno.
    expect(RegistrationValidators.ownerName(' A  l '), isNull);
    expect(RegistrationValidators.ownerName('Ana'), isNull);
    expect(RegistrationValidators.ownerName('x' * 60), isNull);
    expect(RegistrationValidators.ownerName('x' * 61), 'Máximo 60 caracteres');
    expect(RegistrationValidators.normalizeName('  María   José  Ruiz '), 'María José Ruiz');
  });
}
