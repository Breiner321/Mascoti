import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Encabezado "‹ Noviembre 2026 ›" de los calendarios (Cambio 3). Reemplaza
/// las flechas de table_calendar, que no se anuncian en el lector de
/// pantalla: estas son botones de 48 dp con su nombre.
class CalendarMonthHeader extends StatelessWidget {
  const CalendarMonthHeader({
    super.key,
    required this.month,
    required this.title,
    required this.onChangeMonth,
    this.firstMonth,
    this.lastMonth,
  });

  /// Mes visible (cualquier día del mes).
  final DateTime month;
  final String title;

  /// Pide el primer día del mes anterior o siguiente.
  final ValueChanged<DateTime> onChangeMonth;

  /// Límites para deshabilitar las flechas.
  final DateTime? firstMonth;
  final DateTime? lastMonth;

  static int _index(DateTime d) => d.year * 12 + d.month;

  @override
  Widget build(BuildContext context) {
    final canGoBack = firstMonth == null || _index(month) > _index(firstMonth!);
    final canGoForward = lastMonth == null || _index(month) < _index(lastMonth!);
    return Row(
      children: [
        IconButton(
          tooltip: 'Mes anterior',
          color: AppColors.primary,
          icon: const Icon(Icons.chevron_left),
          onPressed: canGoBack ? () => onChangeMonth(DateTime(month.year, month.month - 1)) : null,
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Mes siguiente',
          color: AppColors.primary,
          icon: const Icon(Icons.chevron_right),
          onPressed:
              canGoForward ? () => onChangeMonth(DateTime(month.year, month.month + 1)) : null,
        ),
      ],
    );
  }
}
