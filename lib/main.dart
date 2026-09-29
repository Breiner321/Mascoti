import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/kernel/plugin_manifest.dart';
import 'core/kernel/plugin_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initialize();

  // Kernel: registra y arranca los plugins habilitados en plugin_manifest.dart.
  final registry = PluginRegistry(enabledPlugins);
  await registry.initializeAll();

  runApp(
    ProviderScope(
      overrides: [pluginRegistryProvider.overrideWithValue(registry)],
      child: const MascotiApp(),
    ),
  );
}
