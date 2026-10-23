import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/notifications_repository.dart';
import 'domain/app_notification.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) => NotificationsRepository());

/// Notificaciones del usuario con sesión, las más recientes primero.
final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>(
  (ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return Stream.value(const []);
    return ref.watch(notificationsRepositoryProvider).watchNotifications(user.uid);
  },
  retry: (_, __) => null,
);

/// Contador de no leídas de la campana.
final unreadNotificationsCountProvider = StreamProvider.autoDispose<int>(
  (ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return Stream.value(0);
    return ref.watch(notificationsRepositoryProvider).watchUnreadCount(user.uid);
  },
  retry: (_, __) => null,
);
