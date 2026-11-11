import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/appointments_providers.dart';
import '../../../core/domain/appointment.dart';
import '../../../core/domain/availability.dart';
import '../../../core/domain/clinic.dart';
import '../../../core/domain/colombian_holidays.dart';
import '../../../core/domain/opening_hours.dart';
import '../../../core/domain/schedule_exception.dart';
import '../../../core/domain/slot.dart';
import '../../../core/format/bogota_time.dart';
import '../../../core/format/time_format.dart';
import '../../../core/theme/app_theme.dart';
import '../clinica_routes.dart';
import '../domain/agenda_rules.dart';
import 'agenda_calendar.dart';
import 'clinic_providers.dart';
import 'day_exceptions_view.dart';
import 'upcoming_appointments_card.dart';

/// Agenda de la clínica (RF-06, mockup "Mi día"). Desde el Cambio 2 la
/// clínica está disponible siempre dentro de su horario semanal: aquí solo
/// se manejan las EXCEPCIONES (bloquear franjas, rangos o días; abrir
/// horario extra) y se ven las citas del día.
class ClinicAgendaPage extends ConsumerWidget {
  const ClinicAgendaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId;
    if (clinicId == null) {
      return const _Centered(
        icon: Icons.storefront_outlined,
        text: 'Tu cuenta no tiene una clínica asociada.',
      );
    }
    final clinic = ref.watch(clinicProvider(clinicId));
    final services = ref.watch(clinicServicesProvider(clinicId));

    if (clinic.hasError || services.hasError) {
      return _Centered(
        icon: Icons.cloud_off,
        text: 'No se pudo cargar tu agenda.',
        action: FilledButton(
          onPressed: () {
            ref.invalidate(clinicProvider(clinicId));
            ref.invalidate(clinicServicesProvider(clinicId));
          },
          child: const Text('Reintentar'),
        ),
      );
    }
    final clinicValue = clinic.value;
    final servicesValue = services.value;
    if (clinicValue == null || servicesValue == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // RF-06, precondición: al menos un servicio activo (RF-05).
    if (servicesValue.isEmpty) {
      return _Centered(
        icon: Icons.medical_services_outlined,
        text: 'Para abrir tu agenda primero agrega al menos un servicio.',
        action: FilledButton.icon(
          onPressed: () => context.go(ClinicaRoutes.services),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Ir a Servicios'),
        ),
      );
    }
    final schedule = clinicValue.schedule;
    if (schedule == null) {
      return _Centered(
        icon: Icons.schedule,
        text: 'Configura tu horario semanal para empezar a recibir citas.',
        action: FilledButton.icon(
          onPressed: () => context.push(ClinicaRoutes.setup),
          icon: const Icon(Icons.tune),
          label: const Text('Configurar horario'),
        ),
      );
    }

    return _AgendaBody(clinic: clinicValue);
  }
}

class _AgendaBody extends ConsumerStatefulWidget {
  const _AgendaBody({required this.clinic});

  final Clinic clinic;

  @override
  ConsumerState<_AgendaBody> createState() => _AgendaBodyState();
}

class _AgendaBodyState extends ConsumerState<_AgendaBody> {
  late DateTime _selectedDay = _dateOnly(ref.read(agendaClockProvider)());
  late DateTime _focusedDay = _selectedDay;
  final Set<String> _selection = {};
  bool _busy = false;

  /// Días hacia adelante en los que se sugieren festivos.
  static const _holidayWindowDays = 90;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String get _fecha => Slot.dateKey(_selectedDay);
  String get _clinicId => widget.clinic.id;
  int get _slotMinutes => widget.clinic.bookingSettings.duracionSlotMin;
  DateTime get _now => ref.read(agendaClockProvider)();
  String get _today => BogotaTime.dateKey(_now);

  /// Desde dónde se leen las excepciones: el mes visible o hoy, lo que sea antes.
  String get _exceptionsFrom {
    final monthStart = Slot.dateKey(DateTime(_focusedDay.year, _focusedDay.month));
    return monthStart.compareTo(_today) < 0 ? monthStart : _today;
  }

  bool _isPast(String hora) {
    final start = BogotaTime.tryParse(_fecha, hora);
    return start == null || !start.isAfter(_now);
  }

  void _snack(String text, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: success ? AppColors.success : null,
        content: Text(text, style: success ? TextStyle(color: AppColors.onPrimary) : null),
      ),
    );
  }

  void _selectDay(DateTime day) => setState(() {
        _selectedDay = _dateOnly(day);
        _focusedDay = _selectedDay;
        _selection.clear();
      });

  void _tapCell(DayCell cell, Map<String, Appointment> appointments) {
    switch (cell.status) {
      case CellStatus.ocupada:
        final appointment = appointments[cell.hora];
        if (appointment != null) context.push('/reservas/${appointment.id}');
      case CellStatus.bloqueada:
        final exception = cell.exception;
        if (exception != null) {
          _unblock(exception);
        } else {
          _snack('Esta franja se bloqueó con la agenda anterior y no se puede editar aquí.');
        }
      case CellStatus.libre:
        if (_isPast(cell.hora)) {
          _snack('Este horario ya pasó; no se puede modificar.');
          return;
        }
        setState(() {
          if (!_selection.remove(cell.hora)) _selection.add(cell.hora);
        });
    }
  }

  /// Pide un motivo opcional. null si la clínica canceló.
  Future<String?> _askReason(String title, {String initial = ''}) => showDialog<String>(
        context: context,
        builder: (context) => _ReasonDialog(title: title, initial: initial),
      );

  Future<void> _save(Iterable<ScheduleException> exceptions, String done) async {
    setState(() => _busy = true);
    try {
      await ref.read(exceptionsRepositoryProvider).addAll(_clinicId, exceptions);
      if (!mounted) return;
      setState(_selection.clear);
      _snack(done, success: true);
    } catch (_) {
      _snack('No se pudo guardar. Revisa tu conexión e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _blockSelection() async {
    final motivo = await _askReason('Bloquear franjas');
    if (motivo == null) return;
    await _save([
      for (final (desde, hasta) in AgendaRules.contiguousRanges(_selection, _slotMinutes))
        ScheduleException(
          tipo: ExceptionType.bloqueo,
          fechaInicio: _fecha,
          fechaFin: _fecha,
          desde: desde,
          hasta: hasta,
          motivo: motivo,
        ),
    ], 'Franjas bloqueadas');
  }

  Future<void> _blockDay(String fecha, {String motivoSugerido = '', int activeAppointments = 0}) async {
    final motivo = await _askReason(
      activeAppointments == 0
          ? 'Bloquear el día'
          : 'Bloquear el día (hay $activeAppointments ${activeAppointments == 1 ? 'cita' : 'citas'}; se mantienen)',
      initial: motivoSugerido,
    );
    if (motivo == null) return;
    await _save([
      ScheduleException(
          tipo: ExceptionType.bloqueo, fechaInicio: fecha, fechaFin: fecha, motivo: motivo),
    ], 'Listo: ese día ya no se ofrece para citas');
  }

  Future<void> _openExtra() async {
    Future<String?> pick(String help, String initial) async {
      final m = OpeningHours.minutesOf(initial);
      final t = await TimeFormat.pick(context,
          initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60), helpText: help);
      return t == null ? null : OpeningHours.formatMinutes(t.hour * 60 + t.minute);
    }

    final desde = await pick('Horario extra: desde', '18:00');
    if (desde == null || !mounted) return;
    final hasta = await pick('Horario extra: hasta', '20:00');
    if (hasta == null || !mounted) return;
    if (OpeningHours.minutesOf(desde) >= OpeningHours.minutesOf(hasta)) {
      _snack('La hora de inicio debe ser antes de la de fin.');
      return;
    }
    if (OpeningHours.minutesOf(desde) % _slotMinutes != 0 ||
        OpeningHours.minutesOf(hasta) % _slotMinutes != 0) {
      _snack('Usa horas en bloques de $_slotMinutes minutos.');
      return;
    }
    await _save([
      ScheduleException(
        tipo: ExceptionType.apertura,
        fechaInicio: _fecha,
        fechaFin: _fecha,
        desde: desde,
        hasta: hasta,
      ),
    ], 'Horario extra abierto');
  }

  Future<void> _unblock(ScheduleException e) async {
    final range = e.fechaInicio == e.fechaFin ? e.fechaInicio : 'del ${e.fechaInicio} al ${e.fechaFin}';
    final hours = e.isFullDay ? 'todo el día' : '${TimeFormat.hour(e.desde!)} – ${TimeFormat.hour(e.hasta!)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar bloqueo'),
        content: Text('Se vuelve a abrir $range, $hours.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar bloqueo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(exceptionsRepositoryProvider).delete(_clinicId, e.id);
      if (mounted) _snack('Bloqueo eliminado', success: true);
    } catch (_) {
      if (mounted) _snack('No se pudo eliminar. Revisa tu conexión e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final schedule = widget.clinic.schedule!;
    final exceptionsAsync = ref.watch(
        clinicAgendaExceptionsProvider((clinicId: _clinicId, desde: _exceptionsFrom)));
    final exceptions = exceptionsAsync.value ?? const <ScheduleException>[];
    final daySlots = ref.watch(daySlotsProvider((clinicId: _clinicId, fecha: _fecha)));
    final dayAppointments = ref
            .watch(clinicDayAgendaProvider((clinicId: _clinicId, day: _selectedDay)))
            .value ??
        const <Appointment>[];
    // Cada franja que aparta una cita activa (o ya atendida) apunta a ella.
    final appointments = <String, Appointment>{
      for (final a in dayAppointments)
        if (a.estado.isActive || a.estado == AppointmentStatus.completada)
          for (final id in a.allSlotIds) id.split('_').last: a,
    };

    final monthDays = DateTime(_focusedDay.year, _focusedDay.month + 1, 0).day;
    final marked = {
      for (var d = 1; d <= monthDays; d++)
        if (exceptions.any((e) => e.covers(Slot.dateKey(DateTime(_focusedDay.year, _focusedDay.month, d)))))
          Slot.dateKey(DateTime(_focusedDay.year, _focusedDay.month, d)),
    };
    final holidays = AgendaRules.holidaySuggestions(
      desde: _today,
      hasta: BogotaTime.dateKey(_now.add(const Duration(days: _holidayWindowDays))),
      schedule: schedule,
      exceptions: exceptions,
    );
    final dayBlock = AgendaRules.fullDayBlock(exceptions, _fecha);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDayTitle(_selectedDay),
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                  Text(
                    'Mi día',
                    style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Horario y perfil de atención',
              onPressed: () => context.push(ClinicaRoutes.setup),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // RF-14: citas de hoy y mañana (mockup "Mi día").
        UpcomingAppointmentsCard(clinicId: _clinicId, now: _now),
        if (holidays.isNotEmpty) ...[
          const SizedBox(height: 12),
          _HolidaySuggestions(
            holidays: holidays.take(3).toList(),
            onBlock: _busy ? null : (h) => _blockDay(h.fecha, motivoSugerido: h.nombre),
          ),
        ],
        const SizedBox(height: 12),
        AgendaCalendar(
          selectedDay: _selectedDay,
          focusedDay: _focusedDay,
          configuredDays: marked,
          onDaySelected: _selectDay,
          onPageChanged: (focused) => setState(() => _focusedDay = focused),
        ),
        const SizedBox(height: 20),
        if (exceptionsAsync.hasError || daySlots.hasError)
          _Centered(
            icon: Icons.cloud_off,
            text: 'No se pudo cargar este día.',
            action: FilledButton(
              onPressed: () {
                ref.invalidate(clinicAgendaExceptionsProvider(
                    (clinicId: _clinicId, desde: _exceptionsFrom)));
                ref.invalidate(daySlotsProvider((clinicId: _clinicId, fecha: _fecha)));
              },
              child: const Text('Reintentar'),
            ),
          )
        else if (!exceptionsAsync.hasValue || !daySlots.hasValue)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          DayExceptionsView(
            title: 'Franjas del ${formatShortDay(_selectedDay)}',
            cells: Availability.dayCells(
              fecha: _fecha,
              schedule: schedule,
              slotMinutes: _slotMinutes,
              exceptions: exceptions,
              slotStates: {
                for (final s in daySlots.value!.values) s.hora: s.estado.value,
              },
            ),
            appointments: appointments,
            selection: _selection,
            isPast: _isPast,
            busy: _busy,
            dayBlock: dayBlock,
            onTapCell: (cell) => _tapCell(cell, appointments),
            onBlockSelection: _blockSelection,
            onCancelSelection: () => setState(_selection.clear),
            onBlockDay: () => _blockDay(
              _fecha,
              activeAppointments: dayAppointments.where((a) => a.estado.isActive).length,
            ),
            onUnblockDay: dayBlock == null ? null : () => _unblock(dayBlock),
            onOpenExtra: _openExtra,
          ),
      ],
    );
  }
}

/// Motivo opcional de un bloqueo. Dueño de su controlador: se libera cuando
/// el diálogo termina de cerrarse, no antes.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        maxLength: ScheduleException.maxMotivo,
        decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Bloquear'),
        ),
      ],
    );
  }
}

/// Festivos de Colombia próximos que caen en días de atención (Cambio 2).
class _HolidaySuggestions extends StatelessWidget {
  const _HolidaySuggestions({required this.holidays, required this.onBlock});

  final List<Holiday> holidays;
  final ValueChanged<Holiday>? onBlock;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.celebration_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Próximos festivos', style: textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sigues abierto estos días. ¿Los bloqueas?',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in holidays)
                ActionChip(
                  avatar: const Icon(Icons.block, size: 18),
                  label: Text('${formatShortDay(DateTime.parse(h.fecha))} · ${h.nombre}'),
                  tooltip: 'Bloquear ${h.nombre}',
                  onPressed: onBlock == null ? null : () => onBlock!(h),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
