import 'package:flutter/material.dart';

import '../../../core/domain/map_vet.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/directory_filters.dart';

/// Veterinaria que aún no usa Mascoti en la lista bajo el mapa (Cambio 4):
/// nombre, "Sin Mascoti · distancia" y "Cómo llegar" (no hay "Agendar").
class VetPlaceListTile extends StatelessWidget {
  const VetPlaceListTile({
    super.key,
    required this.vet,
    required this.onTap,
    required this.onDirections,
    this.selected = false,
  });

  final OsmVet vet;
  final VoidCallback onTap;
  final VoidCallback onDirections;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primaryContainer : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
          leading: Icon(Icons.local_hospital_outlined, color: AppColors.textMuted),
          title: Text(
            vet.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text('Sin Mascoti · ${distanceLabel(vet.distanceKm)}',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          trailing: IconButton(
            tooltip: 'Cómo llegar a ${vet.nombre}',
            icon: const Icon(Icons.directions_outlined),
            onPressed: onDirections,
          ),
        ),
      ),
    );
  }
}
