import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/clinics_geo_repository.dart';
import 'package:mascoti/core/data/saved_clinics_store.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/map_vet.dart';
import 'package:mascoti/core/domain/vet_place.dart';
import 'package:mascoti/plugins/sos/domain/emergency_ranking.dart';

const _lat = 6.2088;
const _lng = -75.5674;
const _degPerKm = 1 / 111.195;

Clinic _clinic(String id, double km, {bool emergencias = false, String telefono = '6041234567'}) =>
    Clinic(
      id: id,
      ownerUid: 'o',
      nombre: 'Clínica $id',
      telefono: telefono,
      direccion: 'Calle 10',
      lat: _lat + km * _degPerKm,
      lng: _lng,
      atencionEmergencias: emergencias,
      estado: ClinicStatus.activo,
    );

VetPlace _place(String id, double km, {String? horario}) => VetPlace(
      osmId: 'node/$id',
      nombre: 'Veterinaria $id',
      lat: _lat + km * _degPerKm,
      lng: _lng,
      horario: horario,
    );

List<String> _names(List<EmergencyVet> vets) => [for (final v in vets) v.nombre];

void main() {
  group('EmergencyRanking.live', () {
    test('aliadas con emergencias, luego OSM 24 horas, luego las demás; cada grupo por distancia', () {
      final merged = VetMatching.merge(
        allies: [
          NearbyClinic(clinic: _clinic('cerca', 0.5), distanceKm: 0.5),
          NearbyClinic(clinic: _clinic('urgencias-lejos', 8, emergencias: true), distanceKm: 8),
          NearbyClinic(clinic: _clinic('urgencias-cerca', 3, emergencias: true), distanceKm: 3),
        ],
        places: [
          _place('normal', 0.2, horario: 'Mo-Fr 08:00-18:00'),
          _place('24h-lejos', 6, horario: '24/7'),
          _place('24h-cerca', 1, horario: '24/7'),
        ],
        fromLat: _lat,
        fromLng: _lng,
      );

      final vets = EmergencyRanking.live(merged: merged);

      expect(_names(vets), [
        'Clínica urgencias-cerca',
        'Clínica urgencias-lejos',
        'Veterinaria 24h-cerca',
        'Veterinaria 24h-lejos',
        'Veterinaria normal',
        'Clínica cerca',
      ]);
      expect(vets.first.clinic.aliada, isTrue);
      expect(vets[2].clinic.abierto24h, isTrue);
    });

    test('marca las favoritas y no pasa de 15', () {
      final merged = VetMatching.merge(
        allies: [
          for (var i = 0; i < 20; i++)
            NearbyClinic(clinic: _clinic('c$i', i + 1.0), distanceKm: i + 1.0),
        ],
        places: const [],
        fromLat: _lat,
        fromLng: _lng,
      );
      final vets = EmergencyRanking.live(merged: merged, favoriteKeys: {'aliado:c3'});
      expect(vets, hasLength(EmergencyRanking.maxResults));
      expect(vets.firstWhere((v) => v.favorite).key, 'aliado:c3');
    });
  });

  group('EmergencyRanking.saved', () {
    final favorite = SavedClinic.fromClinic(_clinic('fav', 5));
    final recentEmergency = SavedClinic.fromClinic(_clinic('urg', 9, emergencias: true));
    final recentOsm = SavedClinic.fromMapVet(OsmVet(_place('osm', 2), distanceKm: 2));

    test('sin ubicación: por prioridad, favoritas primero y luego por nombre, sin repetir', () {
      final vets = EmergencyRanking.saved((
        favorites: [favorite],
        recent: [recentOsm, favorite, recentEmergency],
      ));
      expect(_names(vets), ['Clínica urg', 'Clínica fav', 'Veterinaria osm']);
      expect(vets.every((v) => v.distanceKm == null), isTrue);
      expect(vets[1].favorite, isTrue);
    });

    test('con ubicación calcula la distancia de cada guardada', () {
      final vets = EmergencyRanking.saved(
        (favorites: [favorite], recent: [recentOsm]),
        lat: _lat,
        lng: _lng,
      );
      expect(_names(vets), ['Veterinaria osm', 'Clínica fav']);
      expect(vets.first.distanceKm, closeTo(2, 0.01));
    });
  });

  group('EmergencyRanking.nextRadius', () {
    test('amplía de 10 en 10 km hasta tener 3 o llegar a 50 km', () {
      expect(EmergencyRanking.nextRadius(10, 0), 20);
      expect(EmergencyRanking.nextRadius(20, 2), 30);
      expect(EmergencyRanking.nextRadius(40, 1), 50);
      expect(EmergencyRanking.nextRadius(50, 0), isNull);
      expect(EmergencyRanking.nextRadius(10, 3), isNull);
    });
  });

  test('distanceText', () {
    expect(distanceText(0.45), '450 m');
    expect(distanceText(2.34), '2,3 km');
    expect(distanceText(12.6), '13 km');
  });
}
