import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/directory_filters.dart';

/// Sin clínicas en el radio (RF-09, flujo alterno): mensaje del RF y control
/// deslizante para ampliar el radio (5–50 km).
class NoClinicsView extends StatefulWidget {
  const NoClinicsView({
    super.key,
    required this.radiusKm,
    required this.onRadiusChanged,
    this.onClearFilters,
  });

  static const message =
      'No encontramos clínicas cerca. Intenta ampliar el radio de búsqueda';

  final double radiusKm;
  final ValueChanged<double> onRadiusChanged;

  /// Solo si hay filtros activos.
  final VoidCallback? onClearFilters;

  @override
  State<NoClinicsView> createState() => _NoClinicsViewState();
}

class _NoClinicsViewState extends State<NoClinicsView> {
  late double _radius = widget.radiusKm;

  @override
  void didUpdateWidget(NoClinicsView old) {
    super.didUpdateWidget(old);
    if (old.radiusKm != widget.radiusKm) _radius = widget.radiusKm;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.travel_explore, size: 48, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(NoClinicsView.message,
            textAlign: TextAlign.center, style: textTheme.bodyLarge),
        const SizedBox(height: 16),
        Text('Radio de búsqueda: ${_radius.round()} km',
            textAlign: TextAlign.center, style: textTheme.titleSmall),
        Slider(
          value: _radius,
          min: DirectoryFilters.minRadiusKm,
          max: DirectoryFilters.maxRadiusKm,
          divisions:
              (DirectoryFilters.maxRadiusKm - DirectoryFilters.minRadiusKm)
                  .round(),
          label: '${_radius.round()} km',
          onChanged: (v) => setState(() => _radius = v),
          onChangeEnd: (v) =>
              widget.onRadiusChanged(DirectoryFilters.clampRadius(v)),
        ),
        if (widget.onClearFilters != null)
          Center(
            child: TextButton(
                onPressed: widget.onClearFilters,
                child: const Text('Quitar filtros')),
          ),
      ],
    );
  }
}
