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

    test('dirección obligatoria', () {
      expect(RegistrationValidators.address(' '), isNotNull);
      expect(RegistrationValidators.address('Cra 7 # 10-20'), isNull);
    });
  });

  test('payload de registro de clínica', () {
    const request = RegistrationRequest.clinic(
      ClinicRegistration(nombre: ' Vet Norte ', telefono: '3001234567', direccion: 'Calle 1'),
    );
    expect(request.toMap(), {
      'role': 'clinica',
      'clinica': {
        'nombre': 'Vet Norte',
        'telefono': '3001234567',
        'direccion': 'Calle 1',
        'lat': null,
        'lng': null,
      },
    });
    expect(const RegistrationRequest.owner().toMap(), {'role': 'dueno'});
  });
}
