import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../auth_providers.dart';

/// Pantalla de bienvenida (mockup LOGIN). Un solo botón "Continuar con Google"
/// sirve para registrarse (RF-01) y para iniciar sesión (RF-02): si la cuenta
/// es nueva, el router lleva a /registro para escoger el rol.
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  bool _loading = false;

  Future<void> _continueWithGoogle() async {
    setState(() => _loading = true);
    try {
      // Si el usuario cierra el selector, devuelve false y no pasa nada.
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on TimeoutException {
      _showError('No se pudo completar el inicio de sesión. Verifica tu conexión');
    } catch (_) {
      _showError('No se pudo iniciar sesión con Google. Intenta de nuevo');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Reintentar', onPressed: _continueWithGoogle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.pets, size: 48, color: AppColors.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Te damos la bienvenida',
                style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Consultas, citas y tienda para tu mascota en un solo lugar.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _loading ? null : _continueWithGoogle,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Continuar con Google'),
              ),
              const Spacer(flex: 2),
              Text(
                'Al continuar aceptas los Términos y la Política de privacidad.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
