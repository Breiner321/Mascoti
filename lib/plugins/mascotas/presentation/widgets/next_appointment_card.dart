import 'package:flutter/material.dart';

import '../../../../core/domain/appointment.dart';
import '../../../../core/format/bogota_time.dart';
import '../../../../core/format/time_format.dart';
import '../../../../core/theme/app_theme.dart';
import 'coming_soon_badge.dart';

/// Tarjeta morada "Próxima cita": la próxima pendiente o confirmada (RF-14),
/// o "Sin citas · Agendar".
class NextAppointmentCard extends StatelessWidget {
  const NextAppointmentCard({
    super.key,
    required this.onSchedule,
    this.appointment,
    this.onOpen,
  });

  /// null = el agendamiento aún no existe ("Próximamente").
  final VoidCallback? onSchedule;

  final Appointment? appointment;

  /// Abre el detalle de [appointment].
  final VoidCallback? onOpen;

  static const _months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  /// "28 oct · 9:30 a. m." en hora de Bogotá.
  static String when(Appointment a) {
    final w = BogotaTime.wallClock(a.inicio);
    return '${w.day} ${_months[w.month - 1]} · ${TimeFormat.hour(a.hora)}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final a = appointment;
    final light = textTheme.bodySmall?.copyWith(color: AppColors.primaryContainer);
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: a == null ? onSchedule : onOpen,
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
                  if (a == null && onSchedule == null)
                    const ComingSoonBadge(onDark: true),
                  if (a != null) _StatusBadge(status: a.estado),
                ],
              ),
              const SizedBox(height: 24),
              Text('Próxima cita', style: light),
              const SizedBox(height: 2),
              Text(
                a == null ? 'Sin citas · Agendar' : when(a),
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (a != null)
                Text(
                  '${a.petNombre} · ${a.clinicNombre}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: light,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.onPrimaryTranslucent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
