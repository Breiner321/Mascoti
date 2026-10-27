import 'package:flutter/material.dart';

import '../../../../core/domain/appointment.dart';
import '../../../../core/theme/app_theme.dart';

/// Pide el motivo obligatorio de un rechazo o una cancelación (RF-14).
/// Devuelve el motivo, o null si se cierra. "Confirmar" no se activa
/// mientras el motivo esté vacío.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? warning,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title, confirmLabel: confirmLabel, warning: warning),
    );

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.confirmLabel, this.warning});

  final String title;
  final String confirmLabel;
  final String? warning;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final warning = widget.warning;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (warning != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(warning)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            maxLength: AppointmentLimits.maxMotivo,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motivo *',
              helperText: 'El motivo es obligatorio',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: _valid ? () => Navigator.of(context).pop(_controller.text.trim()) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
