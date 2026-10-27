import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'accessibility_settings.dart';

/// Perfil → Accesibilidad (Cambio 3): tema claro u oscuro, alto contraste,
/// tamaño de texto y animaciones. Se guarda en el teléfono.
class AccessibilityPage extends ConsumerWidget {
  const AccessibilityPage({super.key});

  static String _scaleLabel(double s) => '${(s * 100).round()} %';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accessibilitySettingsProvider);
    final notifier = ref.read(accessibilitySettingsProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Semantics(
            header: true,
            child: Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Semantics(
          header: true,
          child: Text(
            'Accesibilidad',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Estos ajustes se guardan en este teléfono.',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        section('Tema'),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto),
              label: Text('Sistema'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Claro'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Oscuro'),
            ),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (s) =>
              notifier.change((current) => current.copyWith(themeMode: s.first)),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.contrast),
          title: const Text('Alto contraste'),
          subtitle: const Text('Textos y bordes más marcados'),
          value: settings.highContrast,
          onChanged: (v) => notifier.change((s) => s.copyWith(highContrast: v)),
        ),
        section('Tamaño del texto'),
        Text(
          'Se suma al tamaño de letra de tu teléfono (máximo 200 %).',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in AccessibilitySettings.textScaleOptions)
              ChoiceChip(
                label: Text(_scaleLabel(s)),
                selected: settings.textScale == s,
                onSelected: (_) => notifier.change((current) => current.copyWith(textScale: s)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            'Así se ve el texto: Luna tiene consulta mañana a las 9:30 a. m.',
            style: textTheme.bodyLarge,
          ),
        ),
        section('Movimiento'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.animation),
          title: const Text('Reducir animaciones'),
          subtitle: const Text('Cambia de pantalla sin animaciones'),
          value: settings.reduceMotion,
          onChanged: (v) => notifier.change((s) => s.copyWith(reduceMotion: v)),
        ),
      ],
    );
  }
}
