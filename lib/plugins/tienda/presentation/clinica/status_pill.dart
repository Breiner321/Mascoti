import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Pastilla con borde de color, ícono y texto. El texto va en el color
/// principal del tema para cumplir el contraste en todas las paletas.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style:
                  Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
