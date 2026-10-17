import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:mascoti/core/data/clinics_geo_repository.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/clinic_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ClinicsGeoRepository repository;

  // Centro de búsqueda: parque de la 93, Bogotá.
  const lat = 4.6767;
  const lng = -74.0483;

  Future<void> clinic(
    String id, {
    required double lat,
    required double lng,
    String estado = 'activo',
    List<String> tipos = const ['perros', 'gatos'],
    List<String> categorias = const ['consulta_general'],
    bool emergencias = false,
  }) =>
      firestore.doc('clinics/$id').set({
        'ownerUid': 'u-$id',
        'nombre': 'Clínica $id',
        'direccion': 'Calle $id',
        'lat': lat,
        'lng': lng,
        'geo': GeoFirePoint(GeoPoint(lat, lng)).data,
        'tiposAnimales': tipos,
        'categoriasServicio': categorias,
        'atencionEmergencias': emergencias,
        'estado': estado,
      });

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = ClinicsGeoRepository(firestore: firestore);
    // ~0,5 km, ~2,4 km y ~6 km del centro; una a ~35 km (Chía no, Zipaquirá).
    await clinic('cerca', lat: 4.6800, lng: -74.0450, emergencias: true);
    await clinic('media', lat: 4.6550, lng: -74.0560,
        tipos: ['aves', 'exoticos'], categorias: ['vacunacion', 'peluqueria']);
    await clinic('lejos', lat: 4.6300, lng: -74.0800, tipos: ['perros']);
    await clinic('zipaquira', lat: 5.0221, lng: -74.0047);
  });

  Future<List<String>> ids({
    double radiusKm = 10,
    ClinicFilters filters = const ClinicFilters(),
  }) async =>
      (await repository.fetchNearby(lat: lat, lng: lng, radiusKm: radiusKm, filters: filters))
          .map((n) => n.clinic.id)
          .toList();

  test('devuelve las clínicas activas del radio, de la más cercana a la más lejana',
      () async {
    final nearby = await repository.fetchNearby(lat: lat, lng: lng);

    expect(nearby.map((n) => n.clinic.id), ['cerca', 'media', 'lejos']);
    expect(nearby.first.distanceKm, lessThan(1));
    expect(nearby.last.distanceKm, inInclusiveRange(5, 10));
    for (var i = 1; i < nearby.length; i++) {
      expect(nearby[i].distanceKm, greaterThanOrEqualTo(nearby[i - 1].distanceKm));
    }
  });

  test('el radio es estricto', () async {
    expect(await ids(radiusKm: 1), ['cerca']);
    expect(await ids(radiusKm: 3), ['cerca', 'media']);
    expect(await ids(radiusKm: 50), ['cerca', 'media', 'lejos', 'zipaquira']);
  });

  test('excluye clínicas incompletas', () async {
    await clinic('nueva', lat: 4.6770, lng: -74.0480, estado: 'incompleto');
    expect(await ids(), ['cerca', 'media', 'lejos']);
  });

  // Las clínicas sin `geo` no aparecen porque Firestore deja fuera de una
  // consulta ordenada por `geo.geohash` los documentos sin ese campo.
  // fake_cloud_firestore no imita eso (lanza un error), así que ese caso se
  // cubre con el script functions/admin/verificar-geo-clinicas.mjs.

  test('filtro por tipos de animales (debe atender todos)', () async {
    expect(await ids(filters: const ClinicFilters(animalTypes: {AnimalType.perros})),
        ['cerca', 'lejos']);
    expect(
      await ids(filters: const ClinicFilters(animalTypes: {AnimalType.perros, AnimalType.gatos})),
      ['cerca'],
    );
    expect(await ids(filters: const ClinicFilters(animalTypes: {AnimalType.reptiles})), isEmpty);
  });

  test('filtro por categoría de servicio y por emergencias', () async {
    expect(await ids(filters: const ClinicFilters(serviceCategory: ServiceCategory.peluqueria)),
        ['media']);
    expect(await ids(filters: const ClinicFilters(onlyEmergencies: true)), ['cerca']);
  });

  test('watchNearby se actualiza cuando una clínica se activa', () async {
    final updates = <List<String>>[];
    final sub = repository
        .watchNearby(lat: lat, lng: lng, radiusKm: 1)
        .listen((list) => updates.add([for (final n in list) n.clinic.id]));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(updates.last, ['cerca']);

    await clinic('nueva', lat: 4.6770, lng: -74.0480, estado: 'incompleto');
    await pumpEventQueue();
    expect(updates.last, ['cerca']);

    await firestore.doc('clinics/nueva').update({'estado': 'activo'});
    await pumpEventQueue();
    expect(updates.last, containsAll(['cerca', 'nueva']));
  });

  test('addressUpdate trae dirección, coordenadas y geo coherentes', () {
    final update = ClinicsGeoRepository.addressUpdate(
      direccion: 'Calle 100 # 15-20',
      lat: 4.6867,
      lng: -74.0486,
    );
    final geo = update['geo'] as Map<String, dynamic>;
    expect(update['direccion'], 'Calle 100 # 15-20');
    expect(geo['geopoint'], const GeoPoint(4.6867, -74.0486));
    expect(geo['geohash'], startsWith('d2g6'));
  });
}
