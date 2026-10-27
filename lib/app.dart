import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/accessibility/accessibility_settings.dart';
import 'core/notificaciones/push/push_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class MascotiApp extends ConsumerStatefulWidget {
  const MascotiApp({super.key});

  @override
  ConsumerState<MascotiApp> createState() => _MascotiAppState();
}

/// Observa el tema del sistema (claro/oscuro) y "quitar animaciones" para
/// elegir la paleta en vivo (Cambio 3).
class _MascotiAppState extends ConsumerState<MascotiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // RF-13: token del dispositivo según la sesión y toques de notificaciones.
    ref.watch(pushBootstrapProvider);

    final settings = ref.watch(accessibilitySettingsProvider);
    final platform = WidgetsBinding.instance.platformDispatcher;
    final dark = switch (settings.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platform.platformBrightness == Brightness.dark,
    };
    final reduceMotion = settings.reduceMotion || platform.accessibilityFeatures.disableAnimations;
    final palette = AppPalette.resolve(dark: dark, highContrast: settings.highContrast);
    // También deja la paleta activa en AppColors.
    final theme = AppTheme.of(palette, reduceMotion: reduceMotion);

    return MaterialApp.router(
      // Los widgets leen AppColors al construirse: al cambiar de paleta se
      // reconstruye toda la app (el router conserva la pantalla actual).
      key: ValueKey(palette.name),
      title: 'Mascoti',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // Tamaño del sistema × tamaño de la app, hasta 200 %.
        final system = media.textScaler.scale(14) / 14;
        final scale = math.min(system * settings.textScale, AccessibilitySettings.maxTextScale);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: media.disableAnimations || reduceMotion,
          ),
          child: child!,
        );
      },
    );
  }
}
