import 'package:flutter/material.dart';

import '../../../../core/domain/order.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/clinic_order_rules.dart';

/// Pide el motivo para cancelar un pedido pagado y avisa del reembolso.
/// Devuelve el motivo, o null si la clínica se arrepiente.
Future<String?> showCancelOrderDialog(BuildContext context) => showDialog<String>(
      context: context,
      builder: (context) => const CancelOrderDialog(),
    );

/// Diálogo "Cancelar pedido": el motivo es obligatorio (el botón de
/// confirmar no se activa sin él) y se explica que el reembolso lo hace la
/// clínica (Cambio 5: la app no devuelve el dinero).
class CancelOrderDialog extends StatefulWidget {
  const CancelOrderDialog({super.key});

  @override
  State<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<CancelOrderDialog> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = ClinicOrderRules.validateReason(_motivo.text) == null;
    return AlertDialog(
      title: const Text('Cancelar pedido'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _motivo,
            autofocus: true,
            maxLength: OrderLimits.maxMotivo,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motivo de la cancelación',
              helperText: 'Obligatorio. El cliente lo verá en el aviso.',
              helperMaxLines: 3,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: AppColors.slotBlocked),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Las unidades vuelven a tu inventario. El pago no se devuelve '
                  'automáticamente: comunícate con el cliente para el reembolso.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.sosText,
            foregroundColor: AppColors.onPrimary,
          ),
          onPressed: valid ? () => Navigator.of(context).pop(_motivo.text.trim()) : null,
          child: const Text('Cancelar pedido'),
        ),
      ],
    );
  }
}
