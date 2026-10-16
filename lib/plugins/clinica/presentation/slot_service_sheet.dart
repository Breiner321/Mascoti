import 'package:flutter/material.dart';

import '../../../core/domain/clinic_service.dart';
import 'service_validators.dart';

/// Elige el servicio permitido en las franjas seleccionadas (RF-06 paso 3).
/// Devuelve el servicio o null si se cancela.
Future<ClinicService?> showSlotServiceSheet(
  BuildContext context, {
  required List<ClinicService> services,
  required int selectedCount,
}) =>
    showModalBottomSheet<ClinicService>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SlotServiceSheet(services: services, selectedCount: selectedCount),
    );

class SlotServiceSheet extends StatefulWidget {
  const SlotServiceSheet({
    super.key,
    required this.services,
    required this.selectedCount,
  });

  final List<ClinicService> services;
  final int selectedCount;

  @override
  State<SlotServiceSheet> createState() => _SlotServiceSheetState();
}

class _SlotServiceSheetState extends State<SlotServiceSheet> {
  ClinicService? _service;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final n = widget.selectedCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Marcar como disponible', style: textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            n == 1 ? '1 franja seleccionada' : '$n franjas seleccionadas',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ClinicService>(
            initialValue: _service,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Servicio'),
            items: [
              for (final s in widget.services)
                DropdownMenuItem(
                  value: s,
                  child: Text(
                    '${s.nombre} · ${formatCop(s.precio)} · ${s.duracionMin} min',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (s) => setState(() => _service = s),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _service == null ? null : () => Navigator.of(context).pop(_service),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }
}
