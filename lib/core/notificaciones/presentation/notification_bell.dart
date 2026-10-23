import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router/core_routes.dart';
import '../../theme/app_theme.dart';
import '../notifications_providers.dart';

/// Campana del encabezado con el contador de no leídas (RF-13). Abre el
/// centro de notificaciones.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sin conexión o con error, la campana se ve sin contador.
    final unread = ref.watch(unreadNotificationsCountProvider).value ?? 0;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        tooltip: unread == 0 ? 'Notificaciones' : 'Notificaciones, $unread sin leer',
        onPressed: () => context.push(CoreRoutes.notifications),
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread >= 100 ? '99+' : '$unread'),
          backgroundColor: AppColors.sos,
          child: const Icon(Icons.notifications_outlined),
        ),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.onPrimaryTranslucent,
          foregroundColor: AppColors.onPrimary,
          fixedSize: const Size(40, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
