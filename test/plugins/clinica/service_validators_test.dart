import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/clinic_service.dart';
import 'package:mascoti/plugins/clinica/presentation/service_validators.dart';

void main() {
  group('nombre (3-60)', () {
    test('obligatorio', () {
      expect(ServiceValidators.nombre(''), 'El nombre es obligatorio');
      expect(ServiceValidators.nombre('   '), 'El nombre es obligatorio');
      expect(ServiceValidators.nombre(null), 'El nombre es obligatorio');
    });

    test('longitud', () {
      const msg = 'El nombre debe tener entre 3 y 60 caracteres';
      expect(ServiceValidators.nombre('ab'), msg);
      expect(ServiceValidators.nombre('abc'), isNull);
      expect(ServiceValidators.nombre('a' * 60), isNull);
      expect(ServiceValidators.nombre('a' * 61), msg);
      expect(ServiceValidators.nombre('  ab  '), msg, reason: 'se ignoran espacios');
    });
  });

  test('categoría obligatoria', () {
    expect(ServiceValidators.categoria(null), 'Selecciona una categoría');
    expect(ServiceValidators.categoria(ServiceCategory.bano), isNull);
  });

  group('precio (> 0, COP sin decimales)', () {
    test('obligatorio', () {
      expect(ServiceValidators.precio(''), 'El precio es obligatorio');
    });

    test('mayor a 0 (mensaje literal del RF)', () {
      expect(ServiceValidators.precio('0'), 'El precio debe ser mayor a 0');
      expect(ServiceValidators.precio('-500'), 'El precio debe ser mayor a 0');
    });

    test('sin decimales', () {
      const msg = 'Ingresa el precio sin decimales';
      expect(ServiceValidators.precio('45000,50'), msg);
      expect(ServiceValidators.precio('45000.5'), msg);
      expect(ServiceValidators.precio('45.00'), msg);
      expect(ServiceValidators.precio('abc'), msg);
    });

    test('acepta enteros con o sin puntos de miles', () {
      expect(ServiceValidators.precio('45000'), isNull);
      expect(ServiceValidators.precio('45.000'), isNull);
      expect(ServiceValidators.precio('1.250.000'), isNull);
      expect(ServiceValidators.parsePrice('1.250.000'), 1250000);
      expect(ServiceValidators.parsePrice('45000'), 45000);
    });
  });

  group('duración (entero 5-480)', () {
    const msg = 'La duración debe ser un número entero entre 5 y 480 minutos';

    test('obligatoria', () {
      expect(ServiceValidators.duracion(''), 'La duración es obligatoria');
    });

    test('rango', () {
      expect(ServiceValidators.duracion('4'), msg);
      expect(ServiceValidators.duracion('5'), isNull);
      expect(ServiceValidators.duracion('480'), isNull);
      expect(ServiceValidators.duracion('481'), msg);
    });

    test('entero', () {
      expect(ServiceValidators.duracion('30.5'), msg);
      expect(ServiceValidators.duracion('treinta'), msg);
    });
  });

  test('descripción opcional, máximo 1000', () {
    expect(ServiceValidators.descripcion(''), isNull);
    expect(ServiceValidators.descripcion(null), isNull);
    expect(ServiceValidators.descripcion('a' * 1000), isNull);
    expect(ServiceValidators.descripcion('a' * 1001),
        'La descripción no puede superar 1000 caracteres');
  });

  test(r'formato COP: $ 45.000', () {
    expect(formatCop(45000), r'$ 45.000');
    expect(formatCop(1250000), r'$ 1.250.000');
    expect(formatCop(800), r'$ 800');
    expect(formatThousands(45000), '45.000');
  });
}
