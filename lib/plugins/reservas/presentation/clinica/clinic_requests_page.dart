import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/appointments_providers.dart';
import '../../../../core/theme/app_theme.dart';
import 'clinic_routes.dart';
import 'request_card.dart';

/// Pestaña "Solicitudes" de la clínica (RF-14): citas pendientes en tiempo
/// real, la más próxima primero.
class ClinicRequestsPage extends ConsumerWidget {
  const ClinicRequestsPage({super.key});

  static const emptyTitle = 'No tienes solicitudes pendientes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId;
    final textTheme = Theme.of(context).textTheme;
    if (clinicId == null) {
      return const _Message(
        icon: Icons.storefront_outlined,
        title: 'Completa el perfil de tu clínica',
        text: 'Cuando tu clínica esté activa, aquí verás las citas que pidan los dueños.',
      );
    }
    final requests = ref.watch(pendingRequestsProvider(clinicId));
    final count = requests.value?.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Solicitudes',
                  style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (count != null && count > 0)
                Text(
                  count == 1 ? '1 cita por responder' : '$count citas por responder',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (requests) {
            AsyncData(:final value) when value.isEmpty => const _Message(
                icon: Icons.inbox_outlined,
                title: emptyTitle,
                text: 'Cuando un dueño pida una cita, aparecerá aquí para que la apruebes o la rechaces.',
              ),
            AsyncData(:final value) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(pendingRequestsProvider(clinicId)),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: value.length,
                  itemBuilder: (context, i) => RequestCard(
                    key: ValueKey(value[i].id),
                    appointment: value[i],
                    onTap: () => context.push(ClinicAppointmentRoutes.detail(value[i].id)),
                  ),
                ),
              ),
            AsyncError() => _Message(
                icon: Icons.cloud_off,
                title: 'No pudimos cargar las solicitudes',
                text: 'Verifica tu conexión.',
                onRetry: () => ref.invalidate(pendingRequestsProvider(clinicId)),
              ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text, this.onRetry});

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(text,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}
