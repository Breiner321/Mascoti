import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Distintivo "Aliado Mascoti" (Cambio 4): la clínica usa la app, con
/// citas y servicios. Las veterinarias de OpenStreetMap no lo llevan.
class AllyBadge extends StatelessWidget {
  const AllyBadge({super.key});

  static const label = 'Aliado Mascoti';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pets, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
