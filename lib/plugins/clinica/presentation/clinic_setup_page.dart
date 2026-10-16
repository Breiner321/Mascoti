import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/domain/animal_type.dart';
import '../../../core/domain/clinic.dart';
import '../../../core/domain/opening_hours.dart';
import '../../../core/theme/app_theme.dart';
import '../clinica_routes.dart';
import '../data/clinic_repository.dart';
import 'clinic_providers.dart';

/// Perfil de atención de la clínica (RF-04): especies que atiende,
/// emergencias (RF-10) y horario base (RF-06).
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
  static const slotOptions = [15, 30, 60];

  late final Set<AnimalType> _types = widget.clinic.tiposAnimales.toSet();
  late bool _emergencies = widget.clinic.atencionEmergencias;
  late OpeningHours _hours = _initialHours(widget.clinic.horarioBase);
  bool _saving = false;

  static OpeningHours _initialHours(OpeningHours? stored) {
    final hours = stored ?? OpeningHours.standard;
    return slotOptions.contains(hours.duracionSlotMin)
        ? hours
        : hours.copyWith(duracionSlotMin: OpeningHours.standard.duracionSlotMin);
  }

  /// Obligatoria mientras la clínica no haya hecho su primera configuración.
  bool get _isFirstSetup => !widget.clinic.isActive;

  String? get _hoursError {
    if (!_hours.isValid) {
      return 'La hora de apertura debe ser anterior a la de cierre.';
    }
    if (_hours.slotTimes().isEmpty) {
      return 'El horario debe permitir al menos una franja.';
    }
    return null;
  }

  bool get _canSave => _types.isNotEmpty && _hoursError == null && !_saving;

  Future<void> _pickTime({required bool opening}) async {
    final current = opening ? _hours.apertura : _hours.cierre;
    final minutes = OpeningHours.minutesOf(current);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText: opening ? 'Hora de apertura' : 'Hora de cierre',
    );
    if (picked == null) return;
    final value = OpeningHours.formatMinutes(picked.hour * 60 + picked.minute);
    setState(() {
      _hours = opening ? _hours.copyWith(apertura: value) : _hours.copyWith(cierre: value);
    });
  }

  Future<void> _save() async {
    if (!_canSave) return; // RF-04: sin especies no se envía nada.
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final wasFirstSetup = _isFirstSetup;

    setState(() => _saving = true);
    try {
      await ref.read(clinicRepositoryProvider).saveCareProfile(
            widget.clinic,
            tiposAnimales: [
              for (final t in AnimalType.values)
                if (_types.contains(t)) t,
            ],
            atencionEmergencias: _emergencies,
            horarioBase: _hours,
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
    final hoursError = _hoursError;

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
              title: 'Horario base',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text('Hora de apertura'),
                  trailing: Text(_hours.apertura, style: textTheme.titleMedium),
                  onTap: _saving ? null : () => _pickTime(opening: true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.nightlight_outlined),
                  title: const Text('Hora de cierre'),
                  trailing: Text(_hours.cierre, style: textTheme.titleMedium),
                  onTap: _saving ? null : () => _pickTime(opening: false),
                ),
                const SizedBox(height: 8),
                Text('Duración de cada cita', style: textTheme.bodyMedium),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    for (final m in slotOptions)
                      ButtonSegment(value: m, label: Text('$m min')),
                  ],
                  selected: {_hours.duracionSlotMin},
                  onSelectionChanged: _saving
                      ? null
                      : (s) => setState(
                            () => _hours = _hours.copyWith(duracionSlotMin: s.first),
                          ),
                ),
                if (hoursError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    hoursError,
                    style: textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
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
