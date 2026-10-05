import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Etiqueta de los accesos a módulos que todavía no existen.
class ComingSoonBadge extends StatelessWidget {
  const ComingSoonBadge({super.key, this.onDark = false});

  /// true sobre fondo morado (tarjeta "Próxima cita").
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: onDark ? AppColors.onPrimaryTranslucent : AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Próximamente',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: onDark ? AppColors.onPrimary : AppColors.primary,
        ),
      ),
    );
  }
}
