import 'package:flutter/material.dart';

import '../../../core/domain/map_vet.dart';
import '../../../core/format/osm_hours.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/directory_filters.dart';

/// Tarjeta de una veterinaria que aún no usa Mascoti (Cambio 4): datos de
/// OpenStreetMap, "Cómo llegar" y, si tiene teléfono, "Llamar". No se puede
/// agendar ni ver servicios.
class VetPlaceCard extends StatelessWidget {
  const VetPlaceCard({
    super.key,
    required this.vet,
    required this.onDirections,
    this.onCall,
  });

  static const notAllyMessage =
      'Esta veterinaria aún no usa Mascoti: no tiene citas ni servicios en la app.';

  final OsmVet vet;
  final VoidCallback onDirections;

  /// null = sin teléfono en OpenStreetMap.
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final place = vet.place;
    final textTheme = Theme.of(context).textTheme;
    final hours = place.horario == null ? null : OsmHours.toSpanish(place.horario!);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(place.nombre,
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _Info(icon: Icons.near_me_outlined, text: distanceLabel(vet.distanceKm)),
          if (place.direccion case final address?)
            _Info(icon: Icons.place_outlined, text: address),
          if (hours != null) _Info(icon: Icons.schedule, text: hours),
          if (place.telefono case final phone?)
            _Info(icon: Icons.phone_outlined, text: phone),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(child: Text(notAllyMessage, style: textTheme.bodySmall)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (onCall != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Llamar'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: onDirections,
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Cómo llegar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Datos de OpenStreetMap',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
