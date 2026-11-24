import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/clinics_geo_providers.dart';
import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/data/saved_clinics_store.dart';
import '../../../core/location/location_service.dart';
import '../data/sos_repository.dart';

final sosRepositoryProvider = Provider<SosRepository>(
  (ref) => SosRepository(geo: ref.watch(clinicsGeoRepositoryProvider)),
);

/// Abre "Llamar" (tel:) o "Cómo llegar" fuera de la app. Se reemplaza en
/// las pruebas.
final sosUrlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Ubicación al abrir el SOS; "Activar ubicación" la vuelve a pedir.
final sosLocationProvider = FutureProvider.autoDispose<LocationResult>(
  (ref) => ref.watch(locationServiceProvider).current(),
  retry: (_, __) => null,
);

/// Lo guardado en el teléfono: se muestra al instante.
final sosSavedClinicsProvider = FutureProvider.autoDispose<SavedClinics>(
  (ref) => ref.watch(savedClinicsStoreProvider).load(),
  retry: (_, __) => null,
);

/// Aliadas cercanas al punto, con radio creciente (RF-10).
final sosAlliesProvider =
    FutureProvider.autoDispose.family<List<NearbyClinic>, ({double lat, double lng})>(
  (ref, p) => ref.watch(sosRepositoryProvider).fetchAllies(p.lat, p.lng),
  retry: (_, __) => null,
);
