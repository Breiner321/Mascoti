import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/brand_logo.dart';
import '../auth_providers.dart';
import '../domain/auth_failure.dart';

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
    } on AuthFailure catch (e) {
      _showError(e.message, retry: e.canRetry);
    } catch (_) {
      _showError(const AuthFailure(AuthFailureKind.unknown).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message, {bool retry = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: retry
            ? SnackBarAction(label: 'Reintentar', onPressed: _continueWithGoogle)
            : null,
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
              const BrandLogo.mark(),
              const SizedBox(height: 28),
              Text(
                'Te damos la bienvenida',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Cuidado, citas y tienda para tu mascota en un solo lugar.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _loading ? null : _continueWithGoogle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: _loading
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login, size: 16, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Continuar con Google',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
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
