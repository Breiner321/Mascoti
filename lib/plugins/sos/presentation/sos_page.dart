import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/saved_clinics_store.dart';
import '../../../core/data/vet_places_providers.dart';
import '../../../core/domain/map_vet.dart';
import '../../../core/domain/vet_place.dart';
import '../../../core/location/location_service.dart';
import '../../../core/maps/external_links.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/emergency_ranking.dart';
import 'emergency_clinic_card.dart';
import 'sos_providers.dart';

/// Modo emergencia (RF-10), a pantalla completa. Pensada para alguien con
/// prisa: muestra al instante las clínicas guardadas en el teléfono y, cuando
/// llega la ubicación, las cercanas (aliadas con emergencias, luego las de
/// OpenStreetMap abiertas 24 horas, luego las demás). Nunca queda vacía.
///
/// Con lector de pantalla, la primera acción es "Llamar a" la más cercana
/// (el botón Cerrar va al final del recorrido).
class SosPage extends ConsumerStatefulWidget {
  const SosPage({super.key});

  static const title = 'Emergencia veterinaria';
  static const searchingLocation = 'Buscando tu ubicación…';
  static const searchingClinics = 'Buscando veterinarias cercanas…';
  static const noLocation = 'Sin tu ubicación. Te mostramos las clínicas guardadas en el teléfono.';
  static const offline = 'Sin conexión. Te mostramos las clínicas guardadas en el teléfono.';
  static const noneNearby =
      'No encontramos veterinarias a menos de 50 km. Te mostramos las guardadas en el teléfono.';
  static const enableLocation = 'Activar ubicación';

  @override
  ConsumerState<SosPage> createState() => _SosPageState();
}

class _SosPageState extends ConsumerState<SosPage> with WidgetsBindingObserver {
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Auditoría (RF-10): una vez, cuando se sabe si hay ubicación. No
    // bloquea la pantalla ni muestra errores.
    ref.listenManual<AsyncValue<LocationResult>>(
      sosLocationProvider,
      (_, next) {
        if (_logged || next.isLoading) return;
        _logged = true;
        final found = next.value is LocationFound ? next.value! as LocationFound : null;
        _logEmergency(found);
      },
      fireImmediately: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFavorites());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes del teléfono se pide otra vez la ubicación.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(sosLocationProvider).value is! LocationFound) {
      ref.invalidate(sosLocationProvider);
    }
  }

  void _logEmergency(LocationFound? found) {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    unawaited(ref
        .read(sosRepositoryProvider)
        .logEmergency(uid: uid, lat: found?.lat, lng: found?.lng)
        .catchError((Object _) {}));
  }

  /// Guarda en el teléfono las clínicas de citas anteriores (favoritas)
  /// para la próxima emergencia sin conexión.
  Future<void> _syncFavorites() async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    try {
      final favorites = await ref.read(sosRepositoryProvider).fetchFavorites(uid);
      await ref.read(savedClinicsStoreProvider).saveFavorites(favorites);
      if (mounted) ref.invalidate(sosSavedClinicsProvider);
    } catch (_) {
      // Sin conexión: se queda lo que ya estaba guardado.
    }
  }

  Future<void> _enableLocation(LocationResult? current) async {
    final service = ref.read(locationServiceProvider);
    if (current is LocationDenied && current.permanently) {
      await service.openSettings(appSettings: true);
    } else if (current is LocationUnavailable) {
      await service.openSettings(appSettings: false);
    }
    ref.invalidate(sosLocationProvider);
  }

  Future<void> _open(List<Uri> uris, String error) async {
    final messenger = ScaffoldMessenger.of(context);
    final opener = ref.read(sosUrlOpenerProvider);
    for (final uri in uris) {
      try {
        if (await opener(uri)) return;
      } catch (_) {}
    }
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(sosLocationProvider);
    final saved = ref.watch(sosSavedClinicsProvider).value ??
        (favorites: const <SavedClinic>[], recent: const <SavedClinic>[]);
    final found = location.value is LocationFound ? location.value! as LocationFound : null;

    List<EmergencyVet> vets;
    String? status;
    var searching = false;
    Widget? fix;

    if (found == null) {
      vets = EmergencyRanking.saved(saved);
      if (location.isLoading) {
        status = SosPage.searchingLocation;
        searching = true;
      } else {
        status = SosPage.noLocation;
        fix = _FixButton(
          icon: Icons.my_location,
          label: SosPage.enableLocation,
          onPressed: () => _enableLocation(location.value),
        );
      }
    } else {
      final point = (lat: found.lat, lng: found.lng);
      final allies = ref.watch(sosAlliesProvider(point));
      final osm = ref.watch(nearbyVetPlacesProvider(
        MapArea.around(found.lat, found.lng, EmergencyRanking.osmRadiusKm).rounded(),
      ));
      final savedNearby = EmergencyRanking.saved(saved, lat: found.lat, lng: found.lng);
      switch (allies) {
        case AsyncData(value: final list):
          final favoriteKeys = {for (final c in saved.favorites) c.key};
          vets = EmergencyRanking.live(
            merged: VetMatching.merge(
              allies: list,
              places: osm.value ?? const [],
              fromLat: found.lat,
              fromLng: found.lng,
            ),
            favoriteKeys: favoriteKeys,
          );
          if (vets.isEmpty) {
            vets = savedNearby;
            status = osm.isLoading ? SosPage.searchingClinics : SosPage.noneNearby;
            searching = osm.isLoading;
          } else {
            if (osm.isLoading) {
              status = SosPage.searchingClinics;
              searching = true;
            }
            unawaited(ref
                .read(savedClinicsStoreProvider)
                .rememberShown([for (final v in vets) v.clinic]));
          }
        case AsyncError():
          vets = savedNearby;
          status = SosPage.offline;
          fix = _FixButton(
            icon: Icons.refresh,
            label: 'Reintentar',
            onPressed: () => ref.invalidate(sosAlliesProvider(point)),
          );
        default:
          vets = savedNearby;
          status = SosPage.searchingClinics;
          searching = true;
      }
    }

    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Semantics(
          explicitChildNodes: true,
          child: Stack(
            children: [
              Semantics(
                container: true,
                sortKey: const OrdinalSortKey(0),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 56),
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: Icon(Icons.warning_amber_rounded, size: 36, color: AppColors.sosText),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                SosPage.title,
                                style: text.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900, color: AppColors.sosText),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Llama primero: la clínica te dirá qué hacer mientras llegas.',
                      style: text.titleMedium?.copyWith(color: AppColors.textPrimary),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 12),
                      _StatusStrip(text: status, searching: searching),
                    ],
                    const SizedBox(height: 16),
                    for (final vet in vets) ...[
                      EmergencyClinicCard(
                        vet: vet,
                        onCall: () => _open(
                          [ExternalLinks.call(vet.telefono ?? '')],
                          'No se pudo abrir el teléfono',
                        ),
                        onDirections: () => _open(
                          ExternalLinks.directions(vet.clinic.lat, vet.clinic.lng, vet.nombre),
                          'No se pudo abrir el mapa',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (vets.isEmpty && !searching) const _NothingSaved(),
                    if (fix != null) ...[
                      const SizedBox(height: 4),
                      fix,
                    ],
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Semantics(
                  container: true,
                  sortKey: const OrdinalSortKey(1),
                  child: IconButton.filledTonal(
                    tooltip: 'Cerrar',
                    iconSize: 28,
                    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _close,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Qué está pasando (buscando, sin ubicación, sin conexión), con ícono y
/// texto. Se anuncia al cambiar.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.text, required this.searching});

  final String text;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.sosContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.sosBorder),
        ),
        child: Row(
          children: [
            if (searching)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.sosText),
              )
            else
              Icon(Icons.info_outline, color: AppColors.sosText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FixButton extends StatelessWidget {
  const _FixButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// Sin nada guardado y sin búsqueda en curso.
class _NothingSaved extends StatelessWidget {
  const _NothingSaved();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Aún no hay clínicas guardadas en el teléfono. Activa la ubicación o '
        'conéctate a internet para ver las veterinarias cercanas.',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}
