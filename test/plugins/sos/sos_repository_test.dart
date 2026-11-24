import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/clinics_geo_repository.dart';
import 'package:mascoti/core/data/saved_clinics_store.dart';
import 'package:mascoti/plugins/sos/data/sos_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeFirebaseFirestore db;
  late SosRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = SosRepository(geo: ClinicsGeoRepository(firestore: db), firestore: db);
  });

  Future<void> addClinic(String id, {String estado = 'activo', bool emergencias = false}) =>
      db.doc('clinics/$id').set({
        'ownerUid': 'o-$id',
        'nombre': 'Clínica $id',
        'telefono': '604 123 4567',
        'direccion': 'Calle 10',
        'lat': 6.2,
        'lng': -75.5,
        'estado': estado,
        'atencionEmergencias': emergencias,
      });

  Future<void> addAppointment(String clinicId, DateTime inicio, {String ownerUid = 'ana'}) =>
      db.collection('appointments').add({
        'ownerUid': ownerUid,
        'clinicId': clinicId,
        'inicio': Timestamp.fromDate(inicio),
      });

  test('favoritas: clínicas activas de las citas del dueño, la más reciente primero, sin repetir',
      () async {
    await addClinic('a', emergencias: true);
    await addClinic('b');
    await addClinic('cerrada', estado: 'incompleto');
    await addClinic('ajena');
    await addAppointment('a', DateTime(2026, 10, 1));
    await addAppointment('b', DateTime(2026, 11, 1));
    await addAppointment('a', DateTime(2026, 11, 10));
    await addAppointment('cerrada', DateTime(2026, 11, 12));
    await addAppointment('ajena', DateTime(2026, 11, 15), ownerUid: 'beto');

    final favorites = await repo.fetchFavorites('ana');

    expect([for (final c in favorites) c.key], ['aliado:a', 'aliado:b']);
    expect(favorites.first.emergencias, isTrue);
    expect(favorites.first.aliada, isTrue);
    expect(favorites.first.telefono, '604 123 4567');
  });

  test('auditoría: emergencyTriggered propio con ubicación aproximada', () async {
    await repo.logEmergency(uid: 'ana', lat: 6.20884, lng: -75.56749);
    await repo.logEmergency(uid: 'ana');

    final events = (await db.collection('auditEvents').get()).docs.map((d) => d.data()).toList();
    expect(events, hasLength(2));
    final withLocation = events.firstWhere((e) => e.containsKey('lat'));
    expect(withLocation['tipo'], 'emergencyTriggered');
    expect(withLocation['uid'], 'ana');
    expect(withLocation['lat'], 6.21);
    expect(withLocation['lng'], -75.57);
    expect(withLocation['createdAt'], isNotNull);
    expect(events.firstWhere((e) => !e.containsKey('lat')).containsKey('lng'), isFalse);
  });

  group('SavedClinicsStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('guarda favoritas y últimas mostradas, y las vuelve a leer', () async {
      final store = SavedClinicsStore();
      const fav = SavedClinic(key: 'aliado:a', nombre: 'A', lat: 1, lng: 2, telefono: '1', aliada: true);
      const osm = SavedClinic(key: 'osm:node/1', nombre: 'B', lat: 3, lng: 4, abierto24h: true);

      await store.saveFavorites([fav]);
      await store.rememberShown([osm, for (var i = 0; i < 20; i++) fav]);
      final saved = await store.load();

      expect(saved.favorites, [fav]);
      expect(saved.recent, hasLength(SavedClinicsStore.maxRecent));
      expect(saved.recent.first, osm);
    });

    test('sin nada guardado o con datos dañados devuelve listas vacías', () async {
      SharedPreferences.setMockInitialValues({SavedClinicsStore.recentKey: 'no es json'});
      final saved = await SavedClinicsStore().load();
      expect(saved.favorites, isEmpty);
      expect(saved.recent, isEmpty);
    });
  });
}
