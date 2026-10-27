import 'package:flutter/material.dart';

import '../../../core/domain/appointment.dart';
import '../../../core/domain/availability.dart';
import '../../../core/domain/schedule_exception.dart';
import '../../../core/format/time_format.dart';
import '../../../core/theme/app_theme.dart';

/// Franjas de un día en la agenda de la clínica (Cambio 2). La clínica está
/// disponible por defecto: aquí solo se bloquean franjas o se ven las citas.
/// Cada estado se distingue con ícono y texto, no solo con color.
class DayExceptionsView extends StatelessWidget {
  const DayExceptionsView({
    super.key,
    required this.title,
    required this.cells,
    required this.appointments,
    required this.selection,
    required this.isPast,
    required this.onTapCell,
    required this.onBlockSelection,
    required this.onCancelSelection,
    required this.onBlockDay,
    required this.onOpenExtra,
    this.dayBlock,
    this.onUnblockDay,
    this.busy = false,
  });

  final String title;
  final List<DayCell> cells;

  /// Cita que ocupa cada franja ('HH:mm').
  final Map<String, Appointment> appointments;
  final Set<String> selection;
  final bool Function(String hora) isPast;
  final ValueChanged<DayCell> onTapCell;
  final VoidCallback onBlockSelection;
  final VoidCallback onCancelSelection;
  final VoidCallback onBlockDay;
  final VoidCallback onOpenExtra;

  /// Bloqueo de día completo que aplica, si lo hay.
  final ScheduleException? dayBlock;
  final VoidCallback? onUnblockDay;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final block = dayBlock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (block != null)
          Card(
            color: AppColors.slotBlockedContainer,
            child: ListTile(
              leading: Icon(Icons.block, color: AppColors.slotBlocked),
              title: const Text('Día bloqueado'),
              subtitle: Text(_describe(block)),
              trailing: TextButton(
                onPressed: busy ? null : onUnblockDay,
                child: const Text('Desbloquear'),
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onBlockDay,
                icon: const Icon(Icons.event_busy),
                label: const Text('Bloquear día'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onOpenExtra,
                icon: const Icon(Icons.more_time),
                label: const Text('Abrir horario extra'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (cells.isEmpty)
          Text(
            'No atiendes este día según tu horario semanal.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cell in cells)
                _CellTile(
                  key: ValueKey('franja-${cell.hora}'),
                  cell: cell,
                  appointment: appointments[cell.hora],
                  selected: selection.contains(cell.hora),
                  past: isPast(cell.hora),
                  onTap: () => onTapCell(cell),
                ),
            ],
          ),
        if (selection.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onBlockSelection,
                  icon: const Icon(Icons.block),
                  label: Text(selection.length == 1
                      ? 'Bloquear 1 franja'
                      : 'Bloquear ${selection.length} franjas'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onCancelSelection, child: const Text('Cancelar')),
            ],
          ),
        ],
      ],
    );
  }

  static String _describe(ScheduleException e) {
    final dates = e.fechaInicio == e.fechaFin ? e.fechaInicio : 'Del ${e.fechaInicio} al ${e.fechaFin}';
    final motivo = e.motivo;
    return motivo == null || motivo.isEmpty ? dates : '$dates · $motivo';
  }
}

class _CellTile extends StatelessWidget {
  const _CellTile({
    super.key,
    required this.cell,
    required this.appointment,
    required this.selected,
    required this.past,
    required this.onTap,
  });

  final DayCell cell;
  final Appointment? appointment;
  final bool selected;
  final bool past;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label, Color fg, Color bg) = selected
        ? (Icons.check_circle, 'Seleccionada', AppColors.onPrimary, AppColors.primary)
        : switch (cell.status) {
            CellStatus.libre => (
                Icons.check_circle_outline,
                'Libre',
                AppColors.slotAvailable,
                AppColors.slotAvailableContainer
              ),
            CellStatus.ocupada => (
                Icons.event,
                appointment == null
                    ? 'Ocupada'
                    : '${appointment!.petNombre} · ${appointment!.estado.label}',
                AppColors.slotLocked,
                AppColors.slotLockedContainer
              ),
            CellStatus.bloqueada => (
                Icons.block,
                cell.exception?.motivo?.isNotEmpty == true ? 'Bloqueada · ${cell.exception!.motivo}' : 'Bloqueada',
                AppColors.slotBlocked,
                AppColors.slotBlockedContainer
              ),
          };
    final hour = TimeFormat.hour(cell.hora);
    return Semantics(
      button: true,
      selected: selected,
      label: '$hour, $label${past ? ', ya pasó' : ''}',
      excludeSemantics: true,
      child: Opacity(
        opacity: past ? 0.5 : 1,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96, minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: fg),
                        const SizedBox(width: 4),
                        Text(hour, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        label,
                        style: TextStyle(color: fg, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
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
