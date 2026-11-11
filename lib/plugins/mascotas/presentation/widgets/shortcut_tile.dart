import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'coming_soon_badge.dart';

/// Tarjeta de la sección "Accesos". Con [onTap] null se ve deshabilitada y
/// con la etiqueta "Próximamente".
class ShortcutTile extends StatelessWidget {
  const ShortcutTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.emergency = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// Estilo rojo de "Emergencia".
  final bool emergency;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      // Cambio 3: deshabilitado = etiqueta "Próximamente" y texto atenuado,
      // sin bajar la opacidad (el texto quedaba ilegible).
      child: Material(
        color: emergency ? AppColors.sosContainer : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: emergency ? AppColors.sosBorder : AppColors.border,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: emergency ? AppColors.sos : AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        size: 22,
                        color: emergency ? AppColors.onPrimary : AppColors.primary,
                      ),
                    ),
                    const Spacer(),
                    if (!enabled) const ComingSoonBadge(),
                  ],
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: !enabled
                        ? AppColors.textMuted
                        : emergency
                            ? AppColors.sosText
                            : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
