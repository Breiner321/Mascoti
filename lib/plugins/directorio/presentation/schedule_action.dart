import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/kernel/plugin_registry.dart';
import '../directorio_routes.dart';

/// "Agendar" (RF-09 → RF-14): abre /reservas/nueva?clinicId=… si algún
/// plugin la declara; si no, avisa "Próximamente". No importa reservas.
void openSchedule(BuildContext context, WidgetRef ref, String clinicId) {
  final path = DirectorioRoutes.schedule(clinicId);
  if (ref.read(pluginRegistryProvider).hasRoute(path)) {
    context.push(path);
    return;
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        const SnackBar(content: Text('Próximamente: agendar citas')));
}
