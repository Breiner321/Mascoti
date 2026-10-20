import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/clinics_geo_providers.dart';
import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../data/location_service.dart';
import '../directorio_routes.dart';
import '../domain/directory_filters.dart';
import 'clinic_list_tile.dart';
import 'clinic_marker_card.dart';
import 'directory_filter_bar.dart';
import 'directory_map_view.dart';
import 'directory_providers.dart';
import 'location_needed_view.dart';
import 'no_clinics_view.dart';
import 'schedule_action.dart';

/// Pestaña "Mapa" del dueño (RF-09, mockup VISTA CLIENTE – Mapa): chips de
/// filtro, mapa centrado en el usuario y lista de clínicas con "Agendar".
class DirectoryPage extends ConsumerWidget {
  const DirectoryPage({super.key});

  static const deniedMessage =
      'Para mostrarte las clínicas cercanas necesitamos tu ubicación. '
      'Si prefieres no compartirla, busca por dirección o ciudad.';
  static const unavailableMessage =
      'No pudimos obtener tu ubicación. Activa el GPS del teléfono '
      'o busca por dirección o ciudad.';

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

/// Mapa y lista para un punto de búsqueda.
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
  String? _selectedId;

  NearbyQuery get _query => NearbyQuery(
        lat: widget.center.lat,
        lng: widget.center.lng,
        radiusKm: widget.filters.radiusKm,
        filters: widget.filters.toClinicFilters(),
      );

  void _setRadius(double km) => ref
      .read(directoryFiltersProvider.notifier)
      .update((f) => f.withRadius(km));

  void _showCard(NearbyClinic nearby) {
    setState(() => _selectedId = nearby.clinic.id);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ClinicMarkerCard(
        nearby: nearby,
        onViewProfile: () {
          Navigator.pop(sheetContext);
          context.push(DirectorioRoutes.clinic(nearby.clinic.id));
        },
        onSchedule: () {
          Navigator.pop(sheetContext);
          openSchedule(context, ref, nearby.clinic.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.center;
    final clinics = ref.watch(nearbyClinicsProvider(_query));
    final mapBuilder = ref.watch(directoryMapBuilderProvider);
    final accuracy = center.accuracyM;
    final showAccuracy = !_hideAccuracyWarning &&
        accuracy != null &&
        accuracy > LocationFound.impreciseAfterM;

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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 240,
              child: mapBuilder(DirectoryMapData(
                center: center,
                clinics: clinics.value ?? const [],
                radiusKm: widget.filters.radiusKm,
                onTapClinic: _showCard,
              )),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: switch (clinics) {
            AsyncData(:final value) when value.isEmpty => NoClinicsView(
                radiusKm: widget.filters.radiusKm,
                onRadiusChanged: _setRadius,
                onClearFilters: widget.filters.hasFilters
                    ? () => ref
                        .read(directoryFiltersProvider.notifier)
                        .update((f) => f.cleared())
                    : null,
              ),
            AsyncData(:final value) => ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: value.length,
                itemBuilder: (context, i) => ClinicListTile(
                  nearby: value[i],
                  selected: value[i].clinic.id == _selectedId,
                  onTap: () => _showCard(value[i]),
                  onSchedule: () =>
                      openSchedule(context, ref, value[i].clinic.id),
                ),
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
                            ref.invalidate(nearbyClinicsProvider(_query)),
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
