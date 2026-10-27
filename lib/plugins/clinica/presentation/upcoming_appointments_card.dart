import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/appointments_providers.dart';
import '../../../core/domain/appointment.dart';
import '../../../core/format/bogota_time.dart';
import '../../../core/format/time_format.dart';
import '../../../core/theme/app_theme.dart';

/// "Próximas citas" de hoy y mañana, arriba de la agenda (mockup "Mi día",
/// RF-14). La casilla marcada es una cita atendida. Tocar una cita abre su
/// detalle en el plugin reservas (por ruta, sin importarlo).
class UpcomingAppointmentsCard extends ConsumerWidget {
  const UpcomingAppointmentsCard(
      {super.key, required this.clinicId, required this.now});

  final String clinicId;
  final DateTime now;

  static const title = 'Próximas citas';
  static const empty = 'No tienes citas para hoy ni para mañana.';

  /// Estados que se muestran: las que siguen en pie y las atendidas.
  static const _shown = {
    AppointmentStatus.pendiente,
    AppointmentStatus.confirmada,
    AppointmentStatus.completada,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = BogotaTime.wallClock(now);
    final today = DateTime(w.year, w.month, w.day);
    final tomorrow = DateTime(w.year, w.month, w.day + 1);
    final todayQuery = (clinicId: clinicId, day: today);
    final tomorrowQuery = (clinicId: clinicId, day: tomorrow);
    final todayList = ref.watch(clinicDayAgendaProvider(todayQuery));
    final tomorrowList = ref.watch(clinicDayAgendaProvider(tomorrowQuery));
    final textTheme = Theme.of(context).textTheme;

    List<Appointment> visible(List<Appointment> list) => [
          for (final a in list)
            if (_shown.contains(a.estado)) a
        ];

    final Widget content;
    if (todayList.hasError || tomorrowList.hasError) {
      content = Row(
        children: [
          const Expanded(child: Text('No pudimos cargar las citas.')),
          TextButton(
            onPressed: () {
              ref.invalidate(clinicDayAgendaProvider(todayQuery));
              ref.invalidate(clinicDayAgendaProvider(tomorrowQuery));
            },
            child: const Text('Reintentar'),
          ),
        ],
      );
    } else if (!todayList.hasValue || !tomorrowList.hasValue) {
      content = const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      );
    } else {
      final hoy = visible(todayList.value!);
      final manana = visible(tomorrowList.value!);
      content = hoy.isEmpty && manana.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(empty,
                  style: textTheme.bodySmall
                      ?.copyWith(color: AppColors.textMuted)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hoy.isNotEmpty) ...[
                  const _DayLabel('Hoy'),
                  for (final a in hoy) _AppointmentRow(appointment: a),
                ],
                if (manana.isNotEmpty) ...[
                  const _DayLabel('Mañana'),
                  for (final a in manana) _AppointmentRow(appointment: a),
                ],
              ],
            );
    }

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            content,
          ],
        ),
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.textMuted, letterSpacing: 1),
        ),
      );
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    void open() => context.push('/reservas/${a.id}');
    final done = a.estado == AppointmentStatus.completada;
    final pending = a.estado == AppointmentStatus.pendiente;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: open,
      leading: Checkbox(value: done, onChanged: (_) => open()),
      title: Text(
        a.serviceNombre,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          decoration: done ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text('${TimeFormat.hour(a.hora)} · ${a.petNombre}'),
      trailing: pending
          ? Text('Por aprobar',
              style: TextStyle(
                  color: AppColors.slotBlocked, fontWeight: FontWeight.w600))
          : Icon(Icons.chevron_right, color: AppColors.textMuted),
    );
  }
}
