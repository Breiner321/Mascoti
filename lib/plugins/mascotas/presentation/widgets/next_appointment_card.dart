import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'coming_soon_badge.dart';

/// Tarjeta morada "Próxima cita". Hasta RF-14 no hay citas que leer, así que
/// siempre muestra "Sin citas · Agendar".
class NextAppointmentCard extends StatelessWidget {
  const NextAppointmentCard({super.key, required this.onSchedule});

  /// null = el agendamiento aún no existe ("Próximamente").
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onSchedule,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: AppColors.onPrimary),
                  const Spacer(),
                  if (onSchedule == null) const ComingSoonBadge(onDark: true),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Próxima cita',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.primaryContainer),
              ),
              const SizedBox(height: 2),
              Text(
                'Sin citas · Agendar',
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.onPrimary,
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
