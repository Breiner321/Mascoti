import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/pet_validators.dart';

/// Lista editable de etiquetas (alergias, condiciones): se escribe un valor,
/// se agrega con el botón o con Enter, y se quita con la X del chip.
class TagChipsField extends StatefulWidget {
  const TagChipsField({
    super.key,
    required this.label,
    required this.hint,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  State<TagChipsField> createState() => _TagChipsFieldState();
}

class _TagChipsFieldState extends State<TagChipsField> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final error = PetValidators.tag(_controller.text, widget.values);
    setState(() => _error = error);
    if (error != null) return;
    widget.onChanged([...widget.values, _controller.text.trim()]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          maxLength: PetValidators.maxTagLength,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            errorText: _error,
            counterText: '',
            suffixIcon: IconButton(
              tooltip: 'Agregar',
              icon: const Icon(Icons.add_circle, color: AppColors.primary),
              onPressed: widget.enabled ? _add : null,
            ),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _add(),
        ),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final value in widget.values)
                InputChip(
                  label: Text(value),
                  isEnabled: widget.enabled,
                  deleteButtonTooltipMessage: 'Quitar $value',
                  onDeleted: () => widget.onChanged(
                    [for (final v in widget.values) if (v != value) v],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
