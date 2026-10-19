import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/domain/clinic.dart';
import '../../../core/domain/clinic_service.dart';
import '../../../core/places/place_address.dart';
import '../data/clinic_directory_repository.dart';
import '../data/location_service.dart';
import '../domain/directory_filters.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);

final clinicDirectoryRepositoryProvider = Provider<ClinicDirectoryRepository>(
  (ref) => ClinicDirectoryRepository(),
);

/// Abre un enlace fuera de la app ("Llamar" con tel:, "Cómo llegar" en
/// la app de mapas). Se reemplaza en las pruebas.
final directoryUrlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Ubicación del teléfono: se pide al abrir el mapa; "Reintentar" la vuelve
/// a pedir con `ref.invalidate`.
final deviceLocationProvider = FutureProvider.autoDispose<LocationResult>(
  (ref) => ref.watch(locationServiceProvider).current(),
  retry: (_, __) => null,
);

/// Dirección o ciudad elegida a mano (sin permiso de ubicación, o para
/// buscar en otro lugar). null = usar el GPS.
final manualCenterProvider =
    NotifierProvider<ManualCenter, PlaceAddress?>(ManualCenter.new);

class ManualCenter extends Notifier<PlaceAddress?> {
  @override
  PlaceAddress? build() => null;

  void set(PlaceAddress? place) => state = place;
}

final directoryFiltersProvider =
    NotifierProvider<DirectoryFiltersNotifier, DirectoryFilters>(
        DirectoryFiltersNotifier.new);

class DirectoryFiltersNotifier extends Notifier<DirectoryFilters> {
  @override
  DirectoryFilters build() => const DirectoryFilters();

  void update(DirectoryFilters Function(DirectoryFilters) change) =>
      state = change(state);
}

/// Punto desde el que se buscan clínicas.
@immutable
class SearchCenter {
  const SearchCenter(
      {required this.lat, required this.lng, this.label, this.accuracyM});

  final double lat;
  final double lng;

  /// Dirección elegida a mano; null = ubicación del GPS.
  final String? label;
  final double? accuracyM;

  bool get fromGps => label == null;
}

final clinicProfileProvider =
    StreamProvider.autoDispose.family<Clinic?, String>(
  (ref, id) => ref.watch(clinicDirectoryRepositoryProvider).watchClinic(id),
  retry: (_, __) => null,
);

final clinicActiveServicesProvider =
    StreamProvider.autoDispose.family<List<ClinicService>, String>(
  (ref, id) =>
      ref.watch(clinicDirectoryRepositoryProvider).watchActiveServices(id),
  retry: (_, __) => null,
);
