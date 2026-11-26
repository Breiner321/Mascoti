import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../auth_providers.dart';
import '../domain/session_state.dart';

/// Carga de la sesión. Si el servidor no responde (sin conexión, o Firestore
/// no disponible), después de [slowAfter] muestra un aviso con "Reintentar" y
/// "Cerrar sesión" en lugar de girar para siempre.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  static const slowAfter = Duration(seconds: 10);

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _slow = false;
    _timer = Timer(SplashPage.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _retry() {
    ref
      ..invalidate(firebaseUserProvider)
      ..invalidate(userProfileProvider);
    setState(_startTimer);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (session) {
            // El detalle técnico (en inglés, de Firebase) no se muestra:
            // solo va al registro de depuración.
            SessionError(:final message) => _Problem(
                text: 'No pudimos cargar tu cuenta. Verifica tu conexión.',
                debugDetail: message,
                onRetry: _retry,
              ),
            _ when _slow => _Problem(
                text: 'Estamos tardando en conectar. Verifica tu conexión.',
                onRetry: _retry,
              ),
            _ => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pets, size: 56, color: AppColors.primary),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                ],
              ),
          },
        ),
      ),
    );
  }
}

class _Problem extends ConsumerWidget {
  const _Problem({required this.text, required this.onRetry, this.debugDetail});

  final String text;
  final String? debugDetail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (debugDetail != null) debugPrint('Error de sesión: $debugDetail');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off, size: 48, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        TextButton(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
