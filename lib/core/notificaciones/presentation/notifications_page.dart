import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_providers.dart';
import '../../format/relative_time.dart';
import '../../kernel/plugin_registry.dart';
import '../../theme/app_theme.dart';
import '../domain/app_notification.dart';
import '../notification_route.dart';
import '../notifications_providers.dart';

/// Centro de notificaciones `/notificaciones` (RF-13 paso 7): historial de
/// alertas en tiempo real, también cuando el push está desactivado.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _markAllAsRead(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      await ref.read(notificationsRepositoryProvider).markAllAsRead(user.uid);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron marcar como leídas. Verifica tu conexión')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final hasUnread = notifications.value?.any((n) => !n.leido) ?? false;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Notificaciones',
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: hasUnread ? () => _markAllAsRead(context, ref) : null,
                child: const Text('Marcar como leídas'),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (notifications) {
            AsyncData(:final value) when value.isEmpty => const _Empty(),
            AsyncData(:final value) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: value.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _NotificationTile(notification: value[i]),
              ),
            AsyncError() => _Error(onRetry: () => ref.invalidate(notificationsProvider)),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  IconData get _icon => switch (notification.tipo) {
        NotificationType.citaNueva => Icons.inbox_outlined,
        NotificationType.citaAprobada => Icons.event_available,
        NotificationType.citaRechazada || NotificationType.citaCancelada => Icons.event_busy,
        NotificationType.recordatorioCita => Icons.alarm,
        NotificationType.vacuna => Icons.vaccines_outlined,
        NotificationType.pedido => Icons.shopping_bag_outlined,
        NotificationType.mensaje => Icons.chat_bubble_outline,
        null => Icons.notifications_outlined,
      };

  void _open(BuildContext context, WidgetRef ref) {
    if (!notification.leido) {
      ref.read(notificationsRepositoryProvider).markAsRead(notification.id).catchError((_) {});
    }
    final user = ref.read(currentUserProvider);
    final route = notificationRoute(notification.tipo?.value, notification.referenciaId);
    if (user == null || route == null) return;
    final target = resolveNotificationTarget(
      route: route,
      registry: ref.read(pluginRegistryProvider),
      role: user.role,
    );
    // Si la pantalla aún no existe se queda aquí (ya está en la app).
    if (target == route) context.push(target);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final unread = !notification.leido;
    final createdAt = notification.createdAt;
    return Material(
      color: unread ? AppColors.primaryContainer : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.titulo,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(notification.cuerpo, style: textTheme.bodyMedium),
                    if (createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        relativeTime(createdAt, DateTime.now()),
                        style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (unread)
                Semantics(
                  label: 'Sin leer',
                  child: Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('No tienes notificaciones', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Aquí verás los cambios de tus citas y los recordatorios.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No se pudieron cargar las notificaciones. Verifica tu conexión'),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
