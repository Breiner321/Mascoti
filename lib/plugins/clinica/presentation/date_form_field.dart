import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Campo de fecha con calendario, validado junto con el resto del Form.
class DateFormField extends FormField<DateTime> {
  DateFormField({
    super.key,
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    required DateTime firstDate,
    required DateTime lastDate,
    super.validator,
    bool clearable = false,
    super.enabled = true,
  }) : super(
          initialValue: value,
          builder: (field) {
            final enabled = field.widget.enabled;
            Future<void> pick() async {
              final now = DateTime.now();
              final initial = field.value ?? (now.isAfter(lastDate) ? lastDate : now);
              final picked = await showDatePicker(
                context: field.context,
                initialDate: initial.isBefore(firstDate)
                    ? firstDate
                    : (initial.isAfter(lastDate) ? lastDate : initial),
                firstDate: firstDate,
                lastDate: lastDate,
                helpText: label,
              );
              if (picked == null) return;
              field.didChange(picked);
              onChanged(picked);
            }

            final date = field.value;
            return InkWell(
              onTap: enabled ? pick : null,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                isEmpty: date == null,
                decoration: InputDecoration(
                  labelText: label,
                  enabled: enabled,
                  errorText: field.errorText,
                  errorMaxLines: 2,
                  prefixIcon: const Icon(Icons.event_outlined),
                  suffixIcon: clearable && enabled && date != null
                      ? IconButton(
                          tooltip: 'Quitar fecha',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            field.didChange(null);
                            onChanged(null);
                          },
                        )
                      : null,
                ),
                child: date == null ? null : Text(DateFormat('dd/MM/yyyy').format(date)),
              ),
            );
          },
        );
}
