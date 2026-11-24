import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/appointments_providers.dart';
import '../../../../core/data/clinics_geo_providers.dart';
import '../../../../core/data/clinics_geo_repository.dart';
import '../../../../core/data/shop_providers.dart';
import '../../../../core/domain/clinic.dart';
import '../../data/shop_clinic_repository.dart';

final shopClinicRepositoryProvider = Provider<ShopClinicRepository>(
  (ref) => ShopClinicRepository(),
);

final ownerLocationProvider =
    Provider<OwnerLocation>((ref) => const GeolocatorOwnerLocation());

/// Una clínica (nombre, teléfono), en tiempo real.
final shopClinicProvider = StreamProvider.autoDispose.family<Clinic?, String>(
  (ref, clinicId) =>
      ref.watch(shopClinicRepositoryProvider).watchClinic(clinicId),
  retry: (_, __) => null,
);

/// "Tus clínicas": donde el dueño tuvo citas o pedidos, sin repetir
/// (id → nombre), la más reciente primero.
final visitedClinicsProvider = Provider.autoDispose<Map<String, String>>((ref) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const {};
  final appointments =
      ref.watch(ownerAppointmentsProvider(uid)).value ?? const [];
  final orders = ref.watch(ownerOrdersProvider(uid)).value ?? const [];
  return {
    for (final o in orders) o.clinicId: o.clinicNombre,
    for (final a in appointments) a.clinicId: a.clinicNombre,
  };
});

/// Ubicación del dueño, pedida solo cuando toca "Usar mi ubicación".
final ownerPositionProvider =
    FutureProvider.autoDispose<({double lat, double lng})?>(
  (ref) => ref.watch(ownerLocationProvider).current(),
  retry: (_, __) => null,
);

/// Clínicas aliadas a 10 km (ClinicsGeoRepository del core).
final nearbyShopClinicsProvider =
    Provider.autoDispose<AsyncValue<List<NearbyClinic>>>((ref) {
  final position = ref.watch(ownerPositionProvider);
  return switch (position) {
    AsyncData(value: final p?) =>
      ref.watch(nearbyClinicsProvider(NearbyQuery(lat: p.lat, lng: p.lng))),
    AsyncData() => const AsyncData([]),
    AsyncError(:final error, :final stackTrace) =>
      AsyncError(error, stackTrace),
    _ => const AsyncLoading(),
  };
});

/// Clínica cuyo catálogo se está viendo. null = aún no elige (se usa la del
/// carrito o la primera de "Tus clínicas").
final selectedShopClinicProvider =
    NotifierProvider<SelectedShopClinic, String?>(SelectedShopClinic.new);

class SelectedShopClinic extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String clinicId) => state = clinicId;
}

/// Abre un enlace fuera de la app ("Llamar"). Se reemplaza en las pruebas.
final shopUrlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Hora actual (vencimiento de los pedidos). Se reemplaza en las pruebas.
final shopClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
