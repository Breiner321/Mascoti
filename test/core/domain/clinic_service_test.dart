import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/clinic_service.dart';

void main() {
  final doc = <String, dynamic>{
    'nombre': 'Vacuna triple felina',
    'categoria': 'vacunacion',
    'descripcion': 'Incluye revisión',
    'precio': 45000.5,
    'duracionMin': 30,
    'activo': true,
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
    'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 3)),
  };

  test('fromMap lee los campos del RF-05', () {
    final service = ClinicService.fromMap('s1', doc);
    expect(service.id, 's1');
    expect(service.categoria, ServiceCategory.vacunacion);
    expect(service.precio, 45000.5);
    expect(service.duracionMin, 30);
    expect(service.activo, isTrue);
    expect(service.updatedAt, DateTime(2026, 10, 3));
  });

  test('toMap → fromMap conserva los datos', () {
    final service = ClinicService.fromMap('s1', doc);
    expect(service.toMap()['categoria'], 'vacunacion');
    expect(ClinicService.fromMap('s1', service.toMap()), service);
  });

  test('un precio entero de Firestore se lee como double', () {
    expect(ClinicService.fromMap('s1', {...doc, 'precio': 45000}).precio, 45000.0);
  });

  test('soft delete con copyWith(activo: false)', () {
    final deleted = ClinicService.fromMap('s1', doc).copyWith(activo: false);
    expect(deleted.activo, isFalse);
    expect(deleted.toMap()['activo'], isFalse);
    expect(deleted.nombre, 'Vacuna triple felina');
  });

  test('categorías: valores de Firestore y textos del RF-05', () {
    expect(ServiceCategory.values.map((c) => c.value), [
      'vacunacion',
      'peluqueria',
      'bano',
      'cirugia',
      'consulta_general',
      'otro',
    ]);
    expect(ServiceCategory.consultaGeneral.label, 'Consulta general');
    expect(ServiceCategory.fromValue('consulta_general'), ServiceCategory.consultaGeneral);
    expect(ServiceCategory.fromValue('desconocida'), ServiceCategory.otro);
  });

  test('sin el campo activo se considera activo', () {
    expect(ClinicService.fromMap('s1', {...doc}..remove('activo')).activo, isTrue);
  });
}
