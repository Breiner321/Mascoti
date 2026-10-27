import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/theme/app_theme.dart';

/// Contraste WCAG 2.1 entre dos colores opacos.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final p in AppPalette.all) {
    group('paleta ${p.name} (WCAG 2.1 AA)', () {
      final text = <String, (Color, Color)>{
        'textPrimary / background': (p.textPrimary, p.background),
        'textPrimary / surface': (p.textPrimary, p.surface),
        'textPrimary / primaryContainer': (p.textPrimary, p.primaryContainer),
        'textMuted / background': (p.textMuted, p.background),
        'textMuted / surface': (p.textMuted, p.surface),
        'textMuted / primaryContainer': (p.textMuted, p.primaryContainer),
        'primary / background': (p.primary, p.background),
        'primary / surface': (p.primary, p.surface),
        'primary / primaryContainer': (p.primary, p.primaryContainer),
        'primary / primarySoft (botón deshabilitado)': (p.primary, p.primarySoft),
        'onPrimary / primary': (p.onPrimary, p.primary),
        'onPrimary / sos': (p.onPrimary, p.sos),
        'onPrimary / success': (p.onPrimary, p.success),
        'sosText / sosContainer': (p.sosText, p.sosContainer),
        'sosText / surface': (p.sosText, p.surface),
        'slotAvailable / su fondo': (p.slotAvailable, p.slotAvailableContainer),
        'slotBlocked / su fondo': (p.slotBlocked, p.slotBlockedContainer),
        'slotLocked / su fondo': (p.slotLocked, p.slotLockedContainer),
      };
      for (final MapEntry(key: name, value: (fg, bg)) in text.entries) {
        test('texto $name ≥ 4.5', () => expect(contrast(fg, bg), greaterThanOrEqualTo(4.5)));
      }

      final ui = <String, (Color, Color)>{
        'outline / surface': (p.outline, p.surface),
        'outline / background': (p.outline, p.background),
        'mapUser / surface': (p.mapUser, p.surface),
        'sos / surface': (p.sos, p.surface),
        'ícono del encabezado': (
          p.onPrimary,
          Color.alphaBlend(p.onPrimaryTranslucent, p.primary),
        ),
      };
      for (final MapEntry(key: name, value: (fg, bg)) in ui.entries) {
        test('control o ícono $name ≥ 3', () => expect(contrast(fg, bg), greaterThanOrEqualTo(3)));
      }
    });
  }

  test('la paleta clara conserva el morado de los mockups', () {
    expect(AppPalette.light.primary, const Color(0xFF7E22CE));
    expect(AppPalette.light.background, const Color(0xFFFAF5FF));
  });

  test('el tema deja activa su paleta en AppColors', () {
    AppTheme.of(AppPalette.dark);
    expect(AppColors.background, AppPalette.dark.background);
    expect(AppTheme.of(AppPalette.dark).brightness, Brightness.dark);
    AppTheme.light();
    expect(AppColors.primary, AppPalette.light.primary);
  });
}
