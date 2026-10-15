import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/opening_hours.dart';

void main() {
  // Documento tal como lo deja completar-registro + una configuración RF-04.
  final firestoreDoc = <String, dynamic>{
    'ownerUid': 'vet',
    'nombre': 'Vet Norte',
    'telefono': '3001234567',
    'direccion': 'Calle 100, Bogotá',
    'lat': 4.711,
    'lng': -74.0721,
    'geo': {'geohash': 'd2g6f3w7df', 'geopoint': const GeoPoint(4.711, -74.0721)},
    'tiposAnimales': ['perros', 'gatos', 'dinosaurios'],
    'atencionEmergencias': true,
    'horarioBase': {'apertura': '08:00', 'cierre': '18:00', 'duracionSlotMin': 30},
    'estado': 'activo',
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
  };

  group('Clinic', () {
    test('fromMap lee todos los campos y descarta tipos desconocidos', () {
      final clinic = Clinic.fromMap('c1', firestoreDoc);

      expect(clinic.id, 'c1');
      expect(clinic.ownerUid, 'vet');
      expect(clinic.geohash, 'd2g6f3w7df');
      expect(clinic.tiposAnimales, [AnimalType.perros, AnimalType.gatos]);
      expect(clinic.atencionEmergencias, isTrue);
      expect(clinic.horarioBase, OpeningHours.standard);
      expect(clinic.estado, ClinicStatus.activo);
      expect(clinic.isActive, isTrue);
      expect(clinic.createdAt, DateTime(2026, 10, 1));
    });

    test('recién registrada: valores por defecto', () {
      final clinic = Clinic.fromMap('c1', {
        'ownerUid': 'vet',
        'nombre': 'Vet',
        'estado': 'incompleto',
      });
      expect(clinic.tiposAnimales, isEmpty);
      expect(clinic.atencionEmergencias, isFalse);
      expect(clinic.horarioBase, isNull);
      expect(clinic.estado, ClinicStatus.incompleto);
    });

    test('toMap → fromMap conserva los datos (con los valores en español)', () {
      final clinic = Clinic.fromMap('c1', firestoreDoc);
      final map = clinic.toMap();

      expect(map['tiposAnimales'], ['perros', 'gatos']);
      expect(map['estado'], 'activo');
      expect((map['geo'] as Map)['geopoint'], const GeoPoint(4.711, -74.0721));
      expect(Clinic.fromMap('c1', map), clinic);
    });

    test('toProfileUpdate solo trae los campos que la clínica puede editar', () {
      final update = Clinic.fromMap('c1', firestoreDoc).toProfileUpdate();
      expect(update.keys.toSet(), {
        'tiposAnimales',
        'atencionEmergencias',
        'horarioBase',
        'telefono',
        'direccion',
        'estado',
      });
    });

    test('copyWith cambia solo lo indicado', () {
      final clinic = Clinic.fromMap('c1', firestoreDoc);
      final updated = clinic.copyWith(
        tiposAnimales: [AnimalType.aves],
        estado: ClinicStatus.incompleto,
      );
      expect(updated.tiposAnimales, [AnimalType.aves]);
      expect(updated.estado, ClinicStatus.incompleto);
      expect(updated.nombre, clinic.nombre);
      expect(updated, isNot(clinic));
    });

    test('un estado desconocido se trata como incompleto', () {
      expect(ClinicStatus.fromValue('verificada'), ClinicStatus.incompleto);
    });
  });

  group('AnimalType', () {
    test('valores de Firestore y textos del RF-04', () {
      expect(AnimalType.values.map((t) => t.value),
          ['perros', 'gatos', 'aves', 'roedores', 'reptiles', 'granja', 'exoticos']);
      expect(AnimalType.granja.label, 'Animales de granja');
      expect(AnimalType.fromValue('exoticos'), AnimalType.exoticos);
      expect(AnimalType.fromValue('dinosaurios'), isNull);
      expect(AnimalType.listFrom(null), isEmpty);
    });
  });

  group('OpeningHours', () {
    test('genera las franjas del día sin pasarse del cierre', () {
      expect(
        const OpeningHours(apertura: '08:00', cierre: '10:00', duracionSlotMin: 30)
            .slotTimes(),
        ['08:00', '08:30', '09:00', '09:30'],
      );
      expect(
        const OpeningHours(apertura: '08:00', cierre: '09:40', duracionSlotMin: 45)
            .slotTimes(),
        ['08:00', '08:45'],
      );
      expect(OpeningHours.standard.slotTimes(), hasLength(20));
    });

    test('valida formato, orden y duración', () {
      expect(OpeningHours.standard.isValid, isTrue);
      expect(const OpeningHours(apertura: '18:00', cierre: '08:00', duracionSlotMin: 30).isValid,
          isFalse);
      expect(const OpeningHours(apertura: '8:00', cierre: '18:00', duracionSlotMin: 30).isValid,
          isFalse);
      expect(const OpeningHours(apertura: '08:00', cierre: '18:00', duracionSlotMin: 3).isValid,
          isFalse);
      expect(
        const OpeningHours(apertura: '18:00', cierre: '08:00', duracionSlotMin: 30).slotTimes(),
        isEmpty,
      );
    });

    test('toMap / fromMap / copyWith', () {
      final hours = OpeningHours.fromMap(OpeningHours.standard.toMap());
      expect(hours, OpeningHours.standard);
      expect(hours.copyWith(cierre: '12:00').cierre, '12:00');
      expect(OpeningHours.fromMap(const {}), OpeningHours.standard);
    });
  });
}
