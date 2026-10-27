import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/appointments_providers.dart';
import '../../../core/domain/animal_type.dart';
import '../../../core/domain/appointment.dart';
import '../../../core/domain/clinic.dart';
import '../../../core/domain/weekly_schedule.dart';
import '../../../core/format/time_format.dart';
import '../../../core/theme/app_theme.dart';
import '../clinica_routes.dart';
import '../data/clinic_repository.dart';
import '../domain/agenda_rules.dart';
import 'clinic_providers.dart';
import 'weekly_schedule_editor.dart';

/// Perfil de atención de la clínica (RF-04): especies que atiende,
/// emergencias (RF-10), horario semanal y reglas de reserva (Cambio 2).
///
/// Obligatoria tras el registro mientras `clinics/{id}.estado` sea
/// 'incompleto' (RF-01 paso 14); después se abre desde el perfil o la agenda.
class ClinicSetupPage extends ConsumerWidget {
  const ClinicSetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId;
    if (clinicId == null) {
      return const _Message(
        icon: Icons.storefront_outlined,
        text: 'Tu cuenta no tiene una clínica asociada.',
      );
    }

    final clinic = ref.watch(clinicProvider(clinicId));
    return switch (clinic) {
      AsyncData(value: final c?) => _CareProfileForm(key: ValueKey(c.id), clinic: c),
      AsyncData() => const _Message(
          icon: Icons.storefront_outlined,
          text: 'No encontramos tu clínica.',
        ),
      AsyncError() => _Message(
          icon: Icons.cloud_off,
          text: 'No se pudo cargar el perfil de atención.',
          onRetry: () => ref.invalidate(clinicProvider(clinicId)),
        ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _CareProfileForm extends ConsumerStatefulWidget {
  const _CareProfileForm({super.key, required this.clinic});

  final Clinic clinic;

  @override
  ConsumerState<_CareProfileForm> createState() => _CareProfileFormState();
}

class _CareProfileFormState extends ConsumerState<_CareProfileForm> {
  /// Anticipación máxima que se ofrece (días).
  static const maxDaysOptions = [7, 15, 30, 60, 90];

  /// Anticipación mínima que se ofrece (minutos).
  static const minAdvanceOptions = [0, 60, 120, 240, 1440];

  late final Set<AnimalType> _types = widget.clinic.tiposAnimales.toSet();
  late bool _emergencies = widget.clinic.atencionEmergencias;
  // Una clínica sin migrar ve su horarioBase como horario de todos los días.
  late WeeklySchedule _schedule = widget.clinic.schedule ?? WeeklySchedule.standard;
  late BookingSettings _settings = _initialSettings(widget.clinic.bookingSettings);
  bool _saving = false;

  static BookingSettings _initialSettings(BookingSettings stored) =>
      BookingSettings.slotOptions.contains(stored.duracionSlotMin)
          ? stored
          : stored.copyWith(duracionSlotMin: 30);

  /// Obligatoria mientras la clínica no haya hecho su primera configuración.
  bool get _isFirstSetup => !widget.clinic.isActive;

  String? get _scheduleError => _schedule.validate(_settings.duracionSlotMin);

  bool get _canSave => _types.isNotEmpty && _scheduleError == null && !_saving;

  static String _minAdvanceLabel(int minutes) => switch (minutes) {
        0 => 'Sin mínimo',
        1440 => '1 día',
        60 => '1 hora',
        _ => '${minutes ~/ 60} horas',
      };

  /// Cambio 2: si el horario nuevo deja citas por fuera, se listan antes de
  /// guardar. Las citas se mantienen; la clínica decide si las cancela.
  Future<bool> _confirmConflicts() async {
    if (_isFirstSetup) return true;
    final now = ref.read(agendaClockProvider)();
    List<Appointment> upcoming;
    try {
      upcoming = await ref
          .read(appointmentsRepositoryProvider)
          .watchAgenda(widget.clinic.id, from: now, to: now.add(const Duration(days: 366)))
          .first;
    } catch (_) {
      return true; // Sin red no se bloquea el guardado: las citas se mantienen.
    }
    final conflicts = AgendaRules.conflictsWith(
      appointments: upcoming,
      schedule: _schedule,
      slotMinutes: _settings.duracionSlotMin,
      now: now,
    );
    if (conflicts.isEmpty || !mounted) return true;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hay citas fuera del nuevo horario'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${conflicts.length == 1 ? 'Esta cita queda' : 'Estas ${conflicts.length} citas quedan'} '
                'por fuera del horario. Se mantienen; si no puedes atenderlas, '
                'cancélalas desde Solicitudes.',
              ),
              const SizedBox(height: 12),
              for (final a in conflicts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_busy),
                  title: Text('${a.fecha} · ${TimeFormat.hour(a.hora)}'),
                  subtitle: Text('${a.petNombre} · ${a.ownerNombre}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Revisar horario'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Guardar de todas formas'),
          ),
        ],
      ),
    );
    return save ?? false;
  }

  Future<void> _save() async {
    if (!_canSave) return; // RF-04: sin especies no se envía nada.
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final wasFirstSetup = _isFirstSetup;

    // Antes de marcar "guardando": el diálogo de conflictos espera a la clínica.
    if (!await _confirmConflicts() || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(clinicRepositoryProvider).saveCareProfile(
            widget.clinic,
            tiposAnimales: [
              for (final t in AnimalType.values)
                if (_types.contains(t)) t,
            ],
            atencionEmergencias: _emergencies,
            horarioSemanal: _schedule,
            reservas: _settings,
          );
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Perfil actualizado',
              style: TextStyle(color: AppColors.onPrimary)),
        ),
      );
      // Primera configuración: se habilita el panel. Edición: se vuelve atrás.
      if (wasFirstSetup) {
        router.go(ClinicaRoutes.agenda);
      } else if (router.canPop()) {
        router.pop();
      }
    } on ClinicPermissionDenied {
      messenger.showSnackBar(
        const SnackBar(content: Text('No tienes permisos para editar este perfil')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheduleError = _scheduleError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil de atención'),
        automaticallyImplyLeading: !_isFirstSetup,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_isFirstSetup) ...[
              Text(
                'Configura tu perfil de atención',
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Antes de recibir citas, indica los tipos de animales que atiendes, '
                'tus horarios y si atiendes emergencias.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
            ],
            _Section(
              title: 'Especies que atiendes',
              children: [
                for (final type in AnimalType.values)
                  CheckboxListTile(
                    title: Text(type.label),
                    value: _types.contains(type),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: _saving
                        ? null
                        : (checked) => setState(() {
                              checked == true ? _types.add(type) : _types.remove(type);
                            }),
                  ),
                if (_types.isEmpty)
                  Text(
                    'Selecciona al menos una especie.',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Emergencias',
              children: [
                SwitchListTile(
                  title: const Text('Atendemos emergencias'),
                  value: _emergencies,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _saving ? null : (v) => setState(() => _emergencies = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Horario semanal',
              children: [
                Text(
                  'Estarás disponible siempre dentro de este horario. Bloquea días '
                  'u horas puntuales desde tu agenda.',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                WeeklyScheduleEditor(
                  schedule: _schedule,
                  slotMinutes: _settings.duracionSlotMin,
                  enabled: !_saving,
                  onChanged: (s) => setState(() => _schedule = s),
                ),
                if (scheduleError != null && !_schedule.isOpenSomeDay)
                  Text(
                    scheduleError,
                    style: textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Reservas',
              children: [
                Text('Duración de cada franja', style: textTheme.bodyMedium),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    for (final m in BookingSettings.slotOptions)
                      ButtonSegment(value: m, label: Text('$m min')),
                  ],
                  selected: {_settings.duracionSlotMin},
                  onSelectionChanged: _saving
                      ? null
                      : (s) => setState(
                            () => _settings = _settings.copyWith(duracionSlotMin: s.first),
                          ),
                ),
                const SizedBox(height: 16),
                Text('Se puede reservar hasta', style: textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final d in maxDaysOptions)
                      ChoiceChip(
                        label: Text('$d días antes'),
                        selected: _settings.anticipacionMaxDias == d,
                        onSelected: _saving
                            ? null
                            : (_) => setState(
                                  () => _settings = _settings.copyWith(anticipacionMaxDias: d),
                                ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Anticipación mínima', style: textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final m in minAdvanceOptions)
                      ChoiceChip(
                        label: Text(_minAdvanceLabel(m)),
                        selected: _settings.anticipacionMinMin == m,
                        onSelected: _saving
                            ? null
                            : (_) => setState(
                                  () => _settings = _settings.copyWith(anticipacionMinMin: m),
                                ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar Configuración'),
            ),
            if (_isFirstSetup) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Material (no un Container con color) para que los ListTile muestren su
    // efecto al tocarlos.
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Message extends ConsumerWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil de atención')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (onRetry != null)
                FilledButton(onPressed: onRetry, child: const Text('Reintentar'))
              else
                OutlinedButton.icon(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
