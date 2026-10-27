import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/clinics_geo_providers.dart';
import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/data/vet_places_providers.dart';
import '../../../core/data/vet_places_repository.dart';
import '../../../core/domain/map_vet.dart';
import '../../../core/domain/vet_place.dart';
import '../../../core/maps/external_links.dart';
import '../../../core/theme/app_theme.dart';
import '../data/location_service.dart';
import '../directorio_routes.dart';
import '../domain/directory_filters.dart';
import 'ally_badge.dart';
import 'clinic_list_tile.dart';
import 'clinic_marker_card.dart';
import 'directory_filter_bar.dart';
import 'directory_map_view.dart';
import 'directory_providers.dart';
import 'location_needed_view.dart';
import 'no_clinics_view.dart';
import 'open_external.dart';
import 'schedule_action.dart';
import 'vet_marker_icon.dart';
import 'vet_place_card.dart';
import 'vet_place_list_tile.dart';

/// Pestaña "Mapa" del dueño (RF-09, mockup VISTA CLIENTE – Mapa): chips de
/// filtro, mapa centrado en el usuario y lista de clínicas con "Agendar".
/// Cambio 4: también las veterinarias de OpenStreetMap que aún no usan
/// Mascoti (solo informativas), y al mover el mapa se vuelve a buscar.
class DirectoryPage extends ConsumerWidget {
  const DirectoryPage({super.key});

  static const deniedMessage =
      'Para mostrarte las clínicas cercanas necesitamos tu ubicación. '
      'Si prefieres no compartirla, busca por dirección o ciudad.';
  static const unavailableMessage =
      'No pudimos obtener tu ubicación. Activa el GPS del teléfono '
      'o busca por dirección o ciudad.';
  static const allyOnlyFiltersNote =
      'Los filtros de especie, servicio y 24 horas solo aplican a Aliados '
      'Mascoti: las otras veterinarias se ocultan.';
  static const othersLegend = 'Otras veterinarias';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(directoryFiltersProvider);
    final manual = ref.watch(manualCenterProvider);
    final location = ref.watch(deviceLocationProvider);
    void retryLocation() {
      ref.read(manualCenterProvider.notifier).set(null);
      ref.invalidate(deviceLocationProvider);
    }

    final Widget body;
    if (manual != null) {
      body = _Results(
        center: SearchCenter(
            lat: manual.lat, lng: manual.lng, label: manual.direccion),
        filters: filters,
        onUseMyLocation: retryLocation,
      );
    } else {
      final locationService = ref.read(locationServiceProvider);
      body = switch (location) {
        AsyncData(
          value: LocationFound(:final lat, :final lng, :final accuracyM)
        ) =>
          _Results(
            center: SearchCenter(lat: lat, lng: lng, accuracyM: accuracyM),
            filters: filters,
          ),
        AsyncData(value: LocationDenied(:final permanently)) =>
          LocationNeededView(
            message: deniedMessage,
            actionLabel: permanently ? 'Abrir ajustes' : 'Permitir ubicación',
            onAction: permanently
                ? () => locationService.openSettings(appSettings: true)
                : retryLocation,
          ),
        AsyncData() || AsyncError() => LocationNeededView(
            message: unavailableMessage,
            actionLabel: 'Reintentar',
            onAction: retryLocation,
          ),
        _ => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Buscando tu ubicación…'),
              ],
            ),
          ),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Mapa',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('FILTROS',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textMuted, letterSpacing: 1)),
        ),
        DirectoryFilterBar(
          filters: filters,
          onChanged: (f) =>
              ref.read(directoryFiltersProvider.notifier).update((_) => f),
        ),
        const SizedBox(height: 8),
        Expanded(child: body),
      ],
    );
  }
}

/// Mapa y lista para un punto de búsqueda. Al mover el mapa (Cambio 4)
/// vuelve a buscar aliados y otras veterinarias en el área visible.
class _Results extends ConsumerStatefulWidget {
  const _Results(
      {required this.center, required this.filters, this.onUseMyLocation});

  final SearchCenter center;
  final DirectoryFilters filters;

  /// Solo con dirección elegida a mano: volver al GPS.
  final VoidCallback? onUseMyLocation;

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  bool _hideAccuracyWarning = false;
  String? _selectedKey;

  /// Lo que se ve del mapa (redondeado). null = todavía no se ha movido:
  /// se busca en el radio del filtro alrededor del punto de búsqueda.
  MapArea? _area;

  @override
  void didUpdateWidget(_Results old) {
    super.didUpdateWidget(old);
    // Otro punto o radio: el mapa se recentra y vuelve a informar el área.
    if (old.center.lat != widget.center.lat ||
        old.center.lng != widget.center.lng ||
        old.filters.radiusKm != widget.filters.radiusKm) {
      _area = null;
    }
  }

  NearbyQuery get _allyQuery {
    final area = _area;
    if (area == null) {
      return NearbyQuery(
        lat: widget.center.lat,
        lng: widget.center.lng,
        radiusKm: widget.filters.radiusKm,
        filters: widget.filters.toClinicFilters(),
      );
    }
    // Radio que cubre todo lo visible (hasta las esquinas).
    final radius = (area.halfDiagonalKm * 10).ceilToDouble() / 10;
    return NearbyQuery(
      lat: area.centerLat,
      lng: area.centerLng,
      radiusKm: radius.clamp(1.0, DirectoryFilters.maxRadiusKm),
      filters: widget.filters.toClinicFilters(),
    );
  }

  MapArea get _osmArea => (_area ??
          MapArea.around(
              widget.center.lat, widget.center.lng, widget.filters.radiusKm))
      .rounded();

  /// Las otras veterinarias no tienen especies, servicios ni emergencias:
  /// con esos filtros (o "Solo aliados") no se muestran.
  bool get _showOsm =>
      !widget.filters.onlyAllies && !widget.filters.hasAllyOnlyFilters;

  void _onAreaChanged(MapArea area) {
    final rounded = area.rounded();
    if (rounded != _area) setState(() => _area = rounded);
  }

  void _setRadius(double km) => ref
      .read(directoryFiltersProvider.notifier)
      .update((f) => f.withRadius(km));

  void _directions(MapVet vet) => openExternal(
      context,
      ref,
      ExternalLinks.directions(vet.lat, vet.lng, vet.nombre),
      'No se pudo abrir el mapa');

  void _show(MapVet vet) {
    setState(() => _selectedKey = vet.key);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => switch (vet) {
        AllyVet() => ClinicMarkerCard(
            nearby: _nearbyOf(vet),
            onViewProfile: () {
              Navigator.pop(sheetContext);
              context.push(DirectorioRoutes.clinic(vet.nearby.clinic.id));
            },
            onSchedule: () {
              Navigator.pop(sheetContext);
              openSchedule(context, ref, vet.nearby.clinic.id);
            },
          ),
        OsmVet() => VetPlaceCard(
            vet: vet,
            onDirections: () => _directions(vet),
            onCall: switch (vet.telefono) {
              final phone? => () => openExternal(context, ref,
                  [ExternalLinks.call(phone)], 'No se pudo abrir el teléfono'),
              null => null,
            },
          ),
      },
    );
  }

  /// La clínica con la distancia desde el punto de búsqueda (no desde el
  /// centro del mapa).
  NearbyClinic _nearbyOf(AllyVet vet) =>
      NearbyClinic(clinic: vet.nearby.clinic, distanceKm: vet.distanceKm);

  @override
  Widget build(BuildContext context) {
    final center = widget.center;
    final filters = widget.filters;
    final allyQuery = _allyQuery;
    final osmArea = _osmArea;
    final allies = ref.watch(nearbyClinicsProvider(allyQuery));
    final osm = _showOsm ? ref.watch(nearbyVetPlacesProvider(osmArea)) : null;
    final mapBuilder = ref.watch(directoryMapBuilderProvider);
    final vets = VetMatching.merge(
      allies: allies.value ?? const [],
      places: osm?.value ?? const [],
      fromLat: center.lat,
      fromLng: center.lng,
    );
    final accuracy = center.accuracyM;
    final showAccuracy = !_hideAccuracyWarning &&
        accuracy != null &&
        accuracy > LocationFound.impreciseAfterM;
    // Sin Supabase configurado (env sin llenar) no se avisa nada.
    final osmFailure = switch (osm) {
      AsyncError(error: VetPlacesFailure.notConfigured) => null,
      AsyncError(error: final VetPlacesFailure f) => f,
      AsyncError() => VetPlacesFailure.unavailable,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (center.label case final label?)
          _InfoStrip(
            icon: Icons.place_outlined,
            text: 'Cerca de: $label',
            action: widget.onUseMyLocation == null
                ? null
                : TextButton(
                    onPressed: widget.onUseMyLocation,
                    child: const Text('Usar mi ubicación')),
          ),
        if (showAccuracy)
          _InfoStrip(
            icon: Icons.gps_not_fixed,
            text: 'Tu ubicación es aproximada (± ${accuracy.round()} m). '
                'Los resultados pueden no ser exactos.',
            action: IconButton(
              tooltip: 'Cerrar aviso',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _hideAccuracyWarning = true),
            ),
          ),
        if (!filters.onlyAllies && filters.hasAllyOnlyFilters)
          const _InfoStrip(
              icon: Icons.filter_alt_outlined,
              text: DirectoryPage.allyOnlyFiltersNote),
        if (osmFailure != null)
          _InfoStrip(
            icon: osmFailure.tooLarge ? Icons.zoom_in : Icons.cloud_off_outlined,
            text: osmFailure.message,
            action: osmFailure.tooLarge
                ? null
                : TextButton(
                    onPressed: () =>
                        ref.invalidate(nearbyVetPlacesProvider(osmArea)),
                    child: const Text('Reintentar')),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 240,
              child: mapBuilder(DirectoryMapData(
                center: center,
                vets: vets,
                radiusKm: filters.radiusKm,
                onTapVet: _show,
                onAreaChanged: _onAreaChanged,
              )),
            ),
          ),
        ),
        _MapLegend(
            showOthers: _showOsm, loadingOthers: osm?.isLoading ?? false),
        Expanded(
          child: switch (allies) {
            AsyncData() when vets.isEmpty && (osm?.isLoading ?? false) =>
              const Center(child: CircularProgressIndicator()),
            AsyncData() when vets.isEmpty => NoClinicsView(
                radiusKm: filters.radiusKm,
                onRadiusChanged: _setRadius,
                onClearFilters: filters.hasFilters
                    ? () => ref
                        .read(directoryFiltersProvider.notifier)
                        .update((f) => f.cleared())
                    : null,
              ),
            AsyncData() => ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: vets.length,
                itemBuilder: (context, i) => switch (vets[i]) {
                  final AllyVet v => ClinicListTile(
                      nearby: _nearbyOf(v),
                      selected: v.key == _selectedKey,
                      onTap: () => _show(v),
                      onSchedule: () =>
                          openSchedule(context, ref, v.nearby.clinic.id),
                    ),
                  final OsmVet v => VetPlaceListTile(
                      vet: v,
                      selected: v.key == _selectedKey,
                      onTap: () => _show(v),
                      onDirections: () => _directions(v),
                    ),
                },
              ),
            AsyncError() => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                          'No pudimos cargar las clínicas. Verifica tu conexión.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(nearbyClinicsProvider(allyQuery)),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

/// Leyenda de los marcadores (Cambio 4).
class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.showOthers, required this.loadingOthers});

  final bool showOthers;
  final bool loadingOthers;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const VetMarkerIcon(ally: true, scale: 0.5),
            const SizedBox(width: 6),
            Text(AllyBadge.label, style: style),
          ]),
          if (showOthers)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const VetMarkerIcon(ally: false, scale: 0.6),
              const SizedBox(width: 6),
              Text(DirectoryPage.othersLegend, style: style),
              if (loadingOthers) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ]),
        ],
      ),
    );
  }
}

/// Aviso no bloqueante sobre el mapa.
class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
