import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../mascotas_routes.dart';

class _Step {
  const _Step(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

const _steps = [
  _Step(
    Icons.event_available_outlined,
    'Agenda citas',
    'Encuentra clínicas veterinarias y reserva consultas, vacunas o '
        'peluquería en pocos toques.',
  ),
  _Step(
    Icons.history_edu_outlined,
    'El historial de tu mascota',
    'Consultas, vacunas y documentos de tu mascota, siempre a la mano.',
  ),
  _Step(
    Icons.sos_outlined,
    'Botón SOS',
    'En una emergencia, toca SOS para encontrar la clínica de urgencias '
        'más cercana.',
  ),
];

/// Onboarding de 3 pasos del dueño (RF-01 paso 14). Se muestra una sola vez:
/// "Saltar" o "Empezar" guardan `users/{uid}.onboardingVisto = true`.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == _steps.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(authRepositoryProvider).markOnboardingSeen();
    context.go(MascotasRoutes.home);
  }

  void _next() => _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );

  @override
  Widget build(BuildContext context) {
    // Si el router devolvió al usuario aquí antes de que la caché reflejara
    // onboardingVisto = true, sale apenas el perfil se actualice.
    ref.listen(currentUserProvider, (_, user) {
      if (user?.onboardingVisto ?? false) context.go(MascotasRoutes.home);
    });

    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(onPressed: _finish, child: const Text('Saltar')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final step = _steps[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: Icon(step.icon, size: 72, color: AppColors.primary),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          step.body,
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? AppColors.primary : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: _isLast ? _finish : _next,
                child: Text(_isLast ? 'Empezar' : 'Siguiente'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
