import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

import '../domain/animal_type.dart';
import '../domain/clinic.dart';
import '../domain/clinic_service.dart';

/// Clínica encontrada en la búsqueda geográfica, con su distancia.
@immutable
class NearbyClinic {
  const NearbyClinic({required this.clinic, required this.distanceKm});

  final Clinic clinic;

  /// Distancia en línea recta desde el punto de búsqueda.
  final double distanceKm;
}

/// Filtros opcionales del directorio (RF-09 paso 8). Se aplican en memoria
/// sobre las clínicas del radio: son pocas, y así no se necesita un índice
/// compuesto por cada combinación de filtros.
@immutable
class ClinicFilters {
  const ClinicFilters({
    this.animalTypes = const {},
    this.serviceCategory,
    this.onlyEmergencies = false,
  });

  /// La clínica debe atender TODOS estos tipos (vacío = sin filtro).
  final Set<AnimalType> animalTypes;

  /// La clínica debe ofrecer un servicio activo de esta categoría.
  final ServiceCategory? serviceCategory;

  /// Solo clínicas con atención de emergencias (RF-10).
  final bool onlyEmergencies;

  bool matches(Clinic clinic) =>
      clinic.tiposAnimales.toSet().containsAll(animalTypes) &&
      (serviceCategory == null || clinic.categoriasServicio.contains(serviceCategory)) &&
      (!onlyEmergencies || clinic.atencionEmergencias);

  @override
  bool operator ==(Object other) =>
      other is ClinicFilters &&
      setEquals(other.animalTypes, animalTypes) &&
      other.serviceCategory == serviceCategory &&
      other.onlyEmergencies == onlyEmergencies;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(animalTypes), serviceCategory, onlyEmergencies);
}

/// Búsqueda de clínicas activas cerca de un punto (RF-09). La reutilizan el
/// SOS (RF-10, `onlyEmergencies`) y el agendamiento (RF-14). Usa el campo
/// `geo {geohash, geopoint}` de `clinics` con geoflutterfire_plus.
///
/// Índice necesario: `clinics (estado ASC, geo.geohash ASC)`.
class ClinicsGeoRepository {
  ClinicsGeoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Radio por defecto del directorio (RF-09: 10 km).
  static const defaultRadiusKm = 10.0;

  GeoCollectionReference<Map<String, dynamic>> get _geo =>
      GeoCollectionReference(_firestore.collection('clinics'));

  static GeoPoint _geopointOf(Map<String, dynamic> data) {
    final geo = data['geo'];
    final point = geo is Map ? geo['geopoint'] : null;
    return point is GeoPoint ? point : const GeoPoint(0, 0);
  }

  static Query<Map<String, dynamic>> _onlyActive(Query<Map<String, dynamic>> query) =>
      query.where('estado', isEqualTo: ClinicStatus.activo.value);

  /// Clínicas activas dentro de [radiusKm] alrededor de ([lat], [lng]), que
  /// cumplen [filters], de la más cercana a la más lejana. En tiempo real.
  Stream<List<NearbyClinic>> watchNearby({
    required double lat,
    required double lng,
    double radiusKm = defaultRadiusKm,
    ClinicFilters filters = const ClinicFilters(),
  }) =>
      _geo
          .subscribeWithinWithDistance(
            center: GeoFirePoint(GeoPoint(lat, lng)),
            radiusInKm: radiusKm,
            field: 'geo',
            geopointFrom: _geopointOf,
            queryBuilder: _onlyActive,
          )
          .map((docs) => _toNearby(docs, radiusKm, filters));

  /// Igual que [watchNearby], una sola vez.
  Future<List<NearbyClinic>> fetchNearby({
    required double lat,
    required double lng,
    double radiusKm = defaultRadiusKm,
    ClinicFilters filters = const ClinicFilters(),
  }) async {
    final docs = await _geo.fetchWithinWithDistance(
      center: GeoFirePoint(GeoPoint(lat, lng)),
      radiusInKm: radiusKm,
      field: 'geo',
      geopointFrom: _geopointOf,
      queryBuilder: _onlyActive,
    );
    return _toNearby(docs, radiusKm, filters);
  }

  static List<NearbyClinic> _toNearby(
    List<GeoDocumentSnapshot<Map<String, dynamic>>> docs,
    double radiusKm,
    ClinicFilters filters,
  ) {
    final result = <NearbyClinic>[];
    for (final geoDoc in docs) {
      final data = geoDoc.documentSnapshot.data();
      // La librería deja un 2 % de margen; aquí el radio es estricto.
      if (data == null || geoDoc.distanceFromCenterInKm > radiusKm) continue;
      final clinic = Clinic.fromMap(geoDoc.documentSnapshot.id, data);
      if (!clinic.isActive || !filters.matches(clinic)) continue;
      result.add(NearbyClinic(clinic: clinic, distanceKm: geoDoc.distanceFromCenterInKm));
    }
    result.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return result;
  }

  /// Campos para cambiar la dirección de una clínica (RF-04) junto con sus
  /// coordenadas y su `geo`, como exigen las reglas: así el mapa nunca la
  /// muestra en la ubicación anterior.
  static Map<String, dynamic> addressUpdate({
    required String direccion,
    required double lat,
    required double lng,
  }) =>
      {
        'direccion': direccion,
        'lat': lat,
        'lng': lng,
        'geo': GeoFirePoint(GeoPoint(lat, lng)).data,
      };
}
