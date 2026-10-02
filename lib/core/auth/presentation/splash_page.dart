import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../auth_providers.dart';
import '../domain/session_state.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (session) {
            SessionError(:final message) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  const Text(
                    'No pudimos cargar tu cuenta. Verifica tu conexión.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(firebaseUserProvider),
                    child: const Text('Reintentar'),
                  ),
                  TextButton(
                    onPressed: () => ref.read(authRepositoryProvider).signOut(),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            _ => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pets, size: 56, color: AppColors.primary),
                  SizedBox(height: 16),
                  CircularProgressIndicator(),
                ],
              ),
          },
        ),
      ),
    );
  }
}
