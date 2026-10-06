import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'coming_soon_badge.dart';

/// Tarjeta "Carnet · Vacunas y controles" (RF-08, RF-18).
class HealthCardTile extends StatelessWidget {
  const HealthCardTile({super.key, required this.onTap});

  /// null = el carnet aún no existe ("Próximamente").
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.vaccines_outlined, color: AppColors.primary),
                  const Spacer(),
                  if (onTap == null) const ComingSoonBadge(),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Carnet',
                style: textTheme.bodySmall?.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: 2),
              Text(
                'Vacunas y controles',
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
