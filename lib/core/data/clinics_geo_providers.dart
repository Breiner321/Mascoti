import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clinics_geo_repository.dart';

final clinicsGeoRepositoryProvider = Provider<ClinicsGeoRepository>(
  (ref) => ClinicsGeoRepository(),
);

/// Parámetros de una búsqueda geográfica (clave del provider).
@immutable
class NearbyQuery {
  const NearbyQuery({
    required this.lat,
    required this.lng,
    this.radiusKm = ClinicsGeoRepository.defaultRadiusKm,
    this.filters = const ClinicFilters(),
  });

  final double lat;
  final double lng;
  final double radiusKm;
  final ClinicFilters filters;

  @override
  bool operator ==(Object other) =>
      other is NearbyQuery &&
      other.lat == lat &&
      other.lng == lng &&
      other.radiusKm == radiusKm &&
      other.filters == filters;

  @override
  int get hashCode => Object.hash(lat, lng, radiusKm, filters);
}

/// Clínicas cercanas en tiempo real (RF-09, RF-10, RF-14).
final nearbyClinicsProvider =
    StreamProvider.autoDispose.family<List<NearbyClinic>, NearbyQuery>(
  (ref, q) => ref.watch(clinicsGeoRepositoryProvider).watchNearby(
        lat: q.lat,
        lng: q.lng,
        radiusKm: q.radiusKm,
        filters: q.filters,
      ),
  retry: (_, __) => null,
);
