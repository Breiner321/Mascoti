import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/clinics_geo_repository.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/map_vet.dart';
import 'package:mascoti/core/domain/vet_place.dart';
import 'package:mascoti/core/format/osm_hours.dart';

NearbyClinic ally(String id, String nombre, double lat, double lng, {String? osmId}) => NearbyClinic(
      clinic: Clinic(
        id: id,
        ownerUid: 'vet',
        nombre: nombre,
        telefono: '3001234567',
        direccion: 'Calle 1',
        lat: lat,
        lng: lng,
        estado: ClinicStatus.activo,
        osmId: osmId,
      ),
      distanceKm: 0,
    );

VetPlace place(String id, String nombre, double lat, double lng) =>
    VetPlace(osmId: id, nombre: nombre, lat: lat, lng: lng);

/// ~0.00045° de latitud ≈ 50 m.
const lat0 = 4.65;
const lng0 = -74.06;

void main() {
  group('nombres', () {
    test('sin tildes, signos ni palabras comunes', () {
      expect(VetMatching.nameTokens('Clínica Veterinaria Patitas S.A.S.'), {'patitas'});
      expect(VetMatching.nameTokens('Centro Médico Veterinario San Ángel'), {'san', 'angel'});
    });

    test('parecido', () {
      expect(VetMatching.similarity('Veterinaria Patitas', 'Clínica Veterinaria Patitas'), 1);
      expect(VetMatching.similarity('Patitas Felices', 'Patitas'), 1);
      expect(VetMatching.similarity('Patitas', 'Huellitas'), 0);
      expect(VetMatching.similarity('Vet San Ángel', 'Clínica San Martín'), 0.5);
      // Nombres solo con palabras comunes: se comparan completos.
      expect(VetMatching.similarity('Clínica Veterinaria', 'clinica  veterinaria'), 1);
      expect(VetMatching.similarity('Clínica Veterinaria', 'Veterinaria'), 0);
    });
  });

  group('deduplicación', () {
    test('mismo osmId: sale una sola vez, como aliada', () {
      final merged = VetMatching.merge(
        allies: [ally('c1', 'Vet Norte', lat0, lng0, osmId: 'node/1')],
        // Lejos y con otro nombre: igual es la misma por el osmId.
        places: [place('node/1', 'Otro nombre', lat0 + 0.01, lng0)],
        fromLat: lat0,
        fromLng: lng0,
      );
      expect(merged, hasLength(1));
      expect(merged.single, isA<AllyVet>());
    });

    test('con osmId distinto no se fusiona aunque esté cerca y se llame igual', () {
      final merged = VetMatching.merge(
        allies: [ally('c1', 'Patitas', lat0, lng0, osmId: 'node/1')],
        places: [place('node/2', 'Patitas', lat0 + 0.0001, lng0)],
        fromLat: lat0,
        fromLng: lng0,
      );
      expect(merged, hasLength(2));
    });

    test('sin osmId: cerca (< 50 m) y nombre parecido se fusionan', () {
      final merged = VetMatching.merge(
        allies: [ally('c1', 'Clínica Veterinaria Patitas', lat0, lng0)],
        places: [place('node/1', 'Veterinaria Patitas', lat0 + 0.0003, lng0)],
        fromLat: lat0,
        fromLng: lng0,
      );
      expect(merged.map((v) => v.key), ['aliado:c1']);
    });

    test('dos veterinarias distintas a 20 m NO se fusionan', () {
      final merged = VetMatching.merge(
        allies: [ally('c1', 'Patitas', lat0, lng0)],
        places: [place('node/1', 'Huellitas', lat0 + 0.00018, lng0)],
        fromLat: lat0,
        fromLng: lng0,
      );
      expect(merged.map((v) => v.key), ['aliado:c1', 'osm:node/1']);
    });

    test('mismo nombre pero a más de 50 m (otra sede) NO se fusionan', () {
      final merged = VetMatching.merge(
        allies: [ally('c1', 'Patitas', lat0, lng0)],
        places: [place('node/1', 'Patitas', lat0 + 0.001, lng0)],
        fromLat: lat0,
        fromLng: lng0,
      );
      expect(merged, hasLength(2));
    });

    test('ordenadas por distancia y "Solo aliados"', () {
      final allies = [ally('c1', 'Lejos', lat0 + 0.02, lng0)];
      final places = [place('node/1', 'Cerca', lat0 + 0.001, lng0)];
      final merged = VetMatching.merge(allies: allies, places: places, fromLat: lat0, fromLng: lng0);
      expect(merged.map((v) => v.nombre), ['Cerca', 'Lejos']);
      expect(merged.first.distanceKm, closeTo(0.111, 0.01));
      final onlyAllies = VetMatching.merge(
          allies: allies, places: places, fromLat: lat0, fromLng: lng0, onlyAllies: true);
      expect(onlyAllies.map((v) => v.nombre), ['Lejos']);
    });
  });

  test('horario de OSM en español', () {
    expect(OsmHours.toSpanish('Mo-Fr 08:00-18:00; Sa 08:00-12:00'),
        'Lu-Vi 8:00 a. m.–6:00 p. m.; Sá 8:00 a. m.–12:00 p. m.');
    expect(OsmHours.toSpanish('24/7'), 'Abierto 24 horas');
    expect(OsmHours.toSpanish('Su off'), 'Do cerrado');
    expect(OsmHours.toSpanish('por cita'), 'por cita');
  });

  group('área del mapa', () {
    test('alrededor de un punto, centro y diagonal', () {
      final a = MapArea.around(lat0, lng0, 5);
      expect(a.centerLat, closeTo(lat0, 1e-9));
      expect(a.heightKm, closeTo(10, 0.01));
      expect(a.widthKm, closeTo(10, 0.01));
      expect(a.halfDiagonalKm, closeTo(7.07, 0.01));
      expect(a.tooLargeForOsm, isFalse);
      expect(MapArea.around(lat0, lng0, 20).tooLargeForOsm, isTrue);
      expect(a.contains(lat0, lng0), isTrue);
    });

    test('redondeo para no repetir consultas', () {
      const a = MapArea(sur: 4.64012, oeste: -74.07049, norte: 4.66004, este: -74.05001);
      expect(a.rounded(), const MapArea(sur: 4.64, oeste: -74.07, norte: 4.66, este: -74.05));
    });
  });
}
