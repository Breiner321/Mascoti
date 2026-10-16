import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/domain/clinic.dart';
import '../../../core/domain/clinic_service.dart';
import '../../../core/domain/opening_hours.dart';
import '../../../core/domain/slot.dart';
import '../../../core/theme/app_theme.dart';
import '../clinica_routes.dart';
import '../data/slots_repository.dart';
import '../domain/day_schedule.dart';
import 'agenda_calendar.dart';
import 'clinic_providers.dart';
import 'day_slots_view.dart';
import 'slot_service_sheet.dart';

/// Agenda de la clínica (RF-06, mockup VISTA DE TIENDA "Mi día"): calendario
/// mensual y franjas del día seleccionado.
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

    return _AgendaBody(clinic: clinicValue, services: servicesValue);
  }
}

class _AgendaBody extends ConsumerStatefulWidget {
  const _AgendaBody({required this.clinic, required this.services});

  final Clinic clinic;
  final List<ClinicService> services;

  @override
  ConsumerState<_AgendaBody> createState() => _AgendaBodyState();
}

class _AgendaBodyState extends ConsumerState<_AgendaBody> {
  late DateTime _selectedDay = _dateOnly(ref.read(agendaClockProvider)());
  late DateTime _focusedDay = _selectedDay;

  /// Borradores del día seleccionado, por hora.
  final Map<String, SlotEdit> _edits = {};
  final Set<String> _selection = {};
  bool _saving = false;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String get _fecha => Slot.dateKey(_selectedDay);
  String get _clinicId => widget.clinic.id;
  OpeningHours get _hours => widget.clinic.horarioBase ?? OpeningHours.standard;

  Map<String, int> get _durations =>
      {for (final s in widget.services) s.id: s.duracionMin};

  bool _isPast(String hora) =>
      DaySchedule.isPast(_fecha, hora, ref.read(agendaClockProvider)());

  void _snack(String text, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: success ? AppColors.success : null,
        content: Text(
          text,
          style: success ? const TextStyle(color: AppColors.onPrimary) : null,
        ),
      ),
    );
  }

  Future<void> _selectDay(DateTime day) async {
    final next = _dateOnly(day);
    if (next == _selectedDay) return;
    if (_edits.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cambios sin guardar'),
          content: const Text(
            'Tienes cambios sin guardar en este día. ¿Quieres descartarlos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _selectedDay = next;
      _focusedDay = next;
      _edits.clear();
      _selection.clear();
    });
  }

  void _tapFranja(Franja franja) {
    if (franja.kind == FranjaKind.locked) {
      // RF-06, flujo alterno "Conflicto con cita existente".
      _snack('No puedes modificar un horario con una cita confirmada. Cancela la cita primero');
      return;
    }
    if (_isPast(franja.hora)) {
      _snack('Este horario ya pasó; no se puede modificar.');
      return;
    }
    setState(() {
      if (!_selection.remove(franja.hora)) _selection.add(franja.hora);
    });
  }

  void _applyToSelection(SlotEdit edit) {
    setState(() {
      for (final hora in _selection) {
        _edits[hora] = edit;
      }
      _selection.clear();
    });
  }

  Future<void> _markAvailable() async {
    final service = await showSlotServiceSheet(
      context,
      services: widget.services,
      selectedCount: _selection.length,
    );
    if (service == null) return;
    _applyToSelection(MarkAvailable(serviceId: service.id, precio: service.precio));
  }

  Future<void> _save(Map<String, Slot> saved) async {
    final changes = DaySchedule.changes(fecha: _fecha, saved: saved, edits: _edits);
    if (changes.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(slotsRepositoryProvider).saveDay(_clinicId, _fecha, changes);
      if (!mounted) return;
      setState(() => _edits.clear());
      _snack('Disponibilidad guardada', success: true);
    } on SlotsSaveRejected {
      _snack('Algunas franjas cambiaron. Revisa la agenda e intenta de nuevo');
    } catch (_) {
      _snack('No se pudo guardar. Revisa tu conexión e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final configured = ref
            .watch(configuredDaysProvider(
                (clinicId: _clinicId, month: DateTime(_focusedDay.year, _focusedDay.month))))
            .value ??
        const <String>{};
    final daySlots = ref.watch(daySlotsProvider((clinicId: _clinicId, fecha: _fecha)));

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
              tooltip: 'Perfil de atención',
              onPressed: () => context.push(ClinicaRoutes.setup),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        // TODO(RF-14, semana 4): lista de citas del día del mockup "Mi día"
        // (casillas "Consulta general · 9:00 · Luna").
        const SizedBox(height: 12),
        AgendaCalendar(
          selectedDay: _selectedDay,
          focusedDay: _focusedDay,
          configuredDays: configured,
          onDaySelected: _selectDay,
          onPageChanged: (focused) => setState(() => _focusedDay = focused),
        ),
        const SizedBox(height: 20),
        switch (daySlots) {
          AsyncData(value: final saved) => DaySlotsView(
              title: 'Franjas del ${formatShortDay(_selectedDay)}',
              plan: DaySchedule.build(
                fecha: _fecha,
                hours: _hours,
                saved: saved,
                edits: _edits,
                serviceDurations: _durations,
              ),
              services: {for (final s in widget.services) s.id: s},
              selection: _selection,
              isPast: _isPast,
              pendingChanges:
                  DaySchedule.changes(fecha: _fecha, saved: saved, edits: _edits).length,
              saving: _saving,
              onTapFranja: _tapFranja,
              onMarkAvailable: _markAvailable,
              onMarkUnavailable: () => _applyToSelection(const MarkUnavailable()),
              onClear: () => _applyToSelection(const ClearSlot()),
              onCancelSelection: () => setState(_selection.clear),
              onSave: () => _save(saved),
            ),
          AsyncError() => _Centered(
              icon: Icons.cloud_off,
              text: 'No se pudieron cargar las franjas de este día.',
              action: FilledButton(
                onPressed: () =>
                    ref.invalidate(daySlotsProvider((clinicId: _clinicId, fecha: _fecha))),
                child: const Text('Reintentar'),
              ),
            ),
          _ => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        },
      ],
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
