import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../auth/domain/app_user.dart';
import '../../kernel/plugin_registry.dart';
import '../../router/app_router.dart';
import '../data/device_registry.dart';
import '../notifications_providers.dart';
import 'notification_navigator.dart';
import 'push_messaging.dart';
import 'push_notifications_controller.dart';

final pushMessagingProvider = Provider<PushMessaging>((ref) => FirebasePushMessaging());

final deviceRegistryProvider = Provider<DeviceRegistry>((ref) => DeviceRegistry());

final notificationNavigatorProvider = Provider<NotificationNavigator>((ref) {
  final navigator = NotificationNavigator(
    router: ref.watch(routerProvider),
    registry: ref.watch(pluginRegistryProvider),
    currentUser: () => ref.read(currentUserProvider),
  );
  ref.onDispose(navigator.dispose);
  return navigator;
});

final pushNotificationsControllerProvider = Provider<PushNotificationsController>((ref) {
  final controller = PushNotificationsController(
    messaging: ref.watch(pushMessagingProvider),
    devices: ref.watch(deviceRegistryProvider),
    onTap: (data) {
      // Tocarla también la marca como leída en el centro de notificaciones.
      final id = data['notificationId'];
      if (id != null && id.isNotEmpty) {
        unawaited(ref.read(notificationsRepositoryProvider).markAsRead(id).catchError((_) {}));
      }
      ref.read(notificationNavigatorProvider).open(data);
    },
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Arranca el push y lo mantiene sincronizado con la sesión. MascotiApp lo
/// observa una vez; el cierre de sesión llama a
/// [PushNotificationsController.signedOut] desde AuthRepository.
final pushBootstrapProvider = Provider<void>((ref) {
  final controller = ref.watch(pushNotificationsControllerProvider);
  unawaited(controller.start());
  ref.listen<AppUser?>(
    currentUserProvider,
    (_, user) {
      if (user != null) {
        unawaited(controller.signedIn(user.uid));
      } else {
        controller.forget();
      }
    },
    fireImmediately: true,
  );
});
