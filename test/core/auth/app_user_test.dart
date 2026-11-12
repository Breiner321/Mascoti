import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';

void main() {
  AppUser user(Map<String, dynamic> extra) =>
      AppUser.fromMap('u1', {'role': 'dueno', 'email': 'ana.perez@gmail.com', ...extra});

  group('nombreVisible (Cambio 1)', () {
    test('usa el nombre que escribió el dueño', () {
      final u = user({'nombre': ' Ana Pérez ', 'displayName': 'ana.p', 'telefono': '3001234567'});
      expect(u.nombreVisible, 'Ana Pérez');
      expect(u.telefono, '3001234567');
      expect(u.needsProfileCompletion, isFalse);
    });

    test('sin nombre, el de Google; sin ninguno, "Usuario" (nunca el correo)', () {
      expect(user({'displayName': 'Ana G'}).nombreVisible, 'Ana G');
      expect(user({'displayName': '  ', 'nombre': ''}).nombreVisible, 'Usuario');
      expect(user({}).nombreVisible, isNot(contains('@')));
    });

    test('solo el dueño sin nombre debe completar su perfil', () {
      expect(user({'displayName': 'Ana G'}).needsProfileCompletion, isTrue);
      final clinic = AppUser.fromMap('v1', {'role': 'clinica', 'displayName': 'Vet', 'clinicId': 'c1'});
      expect(clinic.needsProfileCompletion, isFalse);
    });
  });
}
