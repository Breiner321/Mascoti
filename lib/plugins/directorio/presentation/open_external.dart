import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'directory_providers.dart';

/// Abre el primer enlace que el teléfono pueda abrir ("Llamar", "Cómo
/// llegar"); si ninguno, muestra [error].
Future<void> openExternal(
    BuildContext context, WidgetRef ref, List<Uri> uris, String error) async {
  final messenger = ScaffoldMessenger.of(context);
  final opener = ref.read(directoryUrlOpenerProvider);
  for (final uri in uris) {
    try {
      if (await opener(uri)) return;
    } catch (_) {}
  }
  messenger.showSnackBar(SnackBar(content: Text(error)));
}
