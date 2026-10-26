import 'package:flutter/material.dart';

import '../../../core/domain/appointment.dart';
import '../../../core/domain/clinic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/day_schedule.dart';
import 'slot_tile.dart';

/// Franjas del día seleccionado con la barra de acciones y "Guardar
/// Disponibilidad" (RF-06).
class DaySlotsView extends StatelessWidget {
  const DaySlotsView({
    super.key,
    required this.title,
    required this.plan,
    required this.services,
    required this.selection,
    required this.isPast,
    required this.pendingChanges,
    required this.saving,
    required this.onTapFranja,
    required this.onMarkAvailable,
    required this.onMarkUnavailable,
    required this.onClear,
    required this.onCancelSelection,
    required this.onSave,
    this.appointments = const {},
  });

  final String title;
  final DayPlan plan;

  /// Servicios activos, por id (para mostrar nombres).
  final Map<String, ClinicService> services;
  final Set<String> selection;
  final bool Function(String hora) isPast;
  final int pendingChanges;
  final bool saving;
  final ValueChanged<Franja> onTapFranja;
  final VoidCallback onMarkAvailable;
  final VoidCallback onMarkUnavailable;
  final VoidCallback onClear;
  final VoidCallback onCancelSelection;
  final VoidCallback onSave;

  /// Citas del día por hora de su franja (RF-14).
  final Map<String, Appointment> appointments;

  String? _serviceName(Franja franja) {
    final byHora = {for (final f in plan.franjas) f.hora: f};
    final source = franja.kind == FranjaKind.covered ? byHora[franja.coveredBy] : franja;
    final id = source?.slot?.serviceId;
    return id == null ? null : services[id]?.nombre;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canSave = pendingChanges > 0 && !plan.hasConflicts && !saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Toca una o varias franjas para cambiar su disponibilidad.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        const _Legend(),
        const SizedBox(height: 12),
        if (plan.franjas.isEmpty)
          const Text('El horario base no genera franjas para este día.')
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.35,
            children: [
              for (final franja in plan.franjas)
                SlotTile(
                  key: ValueKey('franja-${franja.hora}'),
                  franja: franja,
                  serviceName: _serviceName(franja),
                  selected: selection.contains(franja.hora),
                  past: isPast(franja.hora),
                  appointment: appointments[franja.hora],
                  onTap: () => onTapFranja(franja),
                ),
            ],
          ),
        if (plan.hasConflicts) ...[
          const SizedBox(height: 12),
          Text(
            'Hay franjas que se solapan o terminan después del cierre. '
            'Corrige las marcadas en rojo para guardar.',
            style: textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        if (selection.isNotEmpty)
          _SelectionBar(
            count: selection.length,
            onMarkAvailable: onMarkAvailable,
            onMarkUnavailable: onMarkUnavailable,
            onClear: onClear,
            onCancel: onCancelSelection,
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: canSave ? onSave : null,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(
            pendingChanges > 0
                ? 'Guardar Disponibilidad ($pendingChanges)'
                : 'Guardar Disponibilidad',
          ),
        ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onMarkAvailable,
    required this.onMarkUnavailable,
    required this.onClear,
    required this.onCancel,
  });

  final int count;
  final VoidCallback onMarkAvailable;
  final VoidCallback onMarkUnavailable;
  final VoidCallback onClear;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  count == 1 ? '1 franja seleccionada' : '$count franjas seleccionadas',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              TextButton(onPressed: onCancel, child: const Text('Cancelar')),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onMarkAvailable,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Disponible'),
              ),
              FilledButton.tonalIcon(
                onPressed: onMarkUnavailable,
                icon: const Icon(Icons.block),
                label: const Text('No disponible'),
              ),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.layers_clear_outlined),
                label: const Text('Quitar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AppColors.border),
              ),
            ),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        item(AppColors.slotAvailableContainer, 'Disponible'),
        item(AppColors.slotBlockedContainer, 'No disponible'),
        item(AppColors.slotLockedContainer, 'Ocupado'),
        item(AppColors.surface, 'Sin configurar'),
      ],
    );
  }
}
