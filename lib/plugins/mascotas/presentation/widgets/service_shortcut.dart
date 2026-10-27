import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Botón de la fila horizontal "Servicios" (Consulta, Peluquería, Vacunas).
class ServiceShortcut extends StatelessWidget {
  const ServiceShortcut({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;

  /// null = el agendamiento aún no existe ("Próximamente").
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // Cambio 3: deshabilitado se indica con texto ("Próximamente") y no con
    // transparencia, que dejaba el texto por debajo del contraste mínimo.
    return Tooltip(
      message: enabled ? label : '$label · Próximamente',
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96, minHeight: 88),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: enabled ? AppColors.primary : AppColors.textMuted, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: enabled ? AppColors.primary : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
