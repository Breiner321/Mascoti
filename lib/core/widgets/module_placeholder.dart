import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pantalla temporal para módulos aún no construidos.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({
    super.key,
    required this.title,
    required this.description,
    this.requirements = const [],
  });

  final String title;
  final String description;

  /// Ej.: ['RF-05 · semana 2'].
  final List<String> requirements;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              description,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            if (requirements.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final rf in requirements)
                    Chip(
                      label: Text(rf),
                      backgroundColor: AppColors.primaryContainer,
                      side: BorderSide.none,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
