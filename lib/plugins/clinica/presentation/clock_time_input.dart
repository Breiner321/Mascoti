import 'package:flutter/material.dart';

import '../../../core/domain/opening_hours.dart';

/// Hora del horario de atención sin reloj: hora (1–12), minutos y
/// a. m. / p. m. en la misma fila. [value] y [onChanged] usan 'HH:MM' en
/// 24 h, como en Firestore. Solo ofrece los minutos múltiplos de
/// [stepMinutes] (la duración de la franja), más el guardado si no lo es.
class ClockTimeInput extends StatelessWidget {
  const ClockTimeInput({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.stepMinutes,
    required this.onChanged,
    this.enabled = true,
  });

  /// Texto visible, p. ej. "Abre".
  final String label;

  /// Lo que anuncia TalkBack, p. ej. "Abre el Lunes".
  final String semanticLabel;
  final String value;
  final int stepMinutes;
  final ValueChanged<String> onChanged;
  final bool enabled;

  int get _total => OpeningHours.minutesOf(value);
  int get _hour12 => _total ~/ 60 % 12 == 0 ? 12 : _total ~/ 60 % 12;
  int get _minute => _total % 60;
  bool get _isPm => _total ~/ 60 >= 12;

  void _emit({int? hour12, int? minute, bool? pm}) {
    final h = (hour12 ?? _hour12) % 12 + ((pm ?? _isPm) ? 12 : 0);
    onChanged(OpeningHours.formatMinutes(h * 60 + (minute ?? _minute)));
  }

  @override
  Widget build(BuildContext context) {
    final step = stepMinutes.clamp(1, 60);
    final minutes = {for (var m = 0; m < 60; m += step) m, _minute}.toList()..sort();

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ExcludeSemantics(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Semantics(
            label: 'Hora',
            child: DropdownButton<int>(
              value: _hour12,
              onChanged: enabled ? (h) => _emit(hour12: h) : null,
              items: [
                for (var h = 1; h <= 12; h++) DropdownMenuItem(value: h, child: Text('$h')),
              ],
            ),
          ),
          const ExcludeSemantics(child: Text(':')),
          Semantics(
            label: 'Minutos',
            child: DropdownButton<int>(
              value: _minute,
              onChanged: enabled ? (m) => _emit(minute: m) : null,
              items: [
                for (final m in minutes)
                  DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0'))),
              ],
            ),
          ),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('a. m.')),
              ButtonSegment(value: true, label: Text('p. m.')),
            ],
            selected: {_isPm},
            onSelectionChanged: enabled ? (s) => _emit(pm: s.single) : null,
          ),
        ],
      ),
    );
  }
}
