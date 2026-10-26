import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/format/relative_time.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/notificaciones/domain/app_notification.dart';
import 'package:mascoti/core/notificaciones/notification_route.dart';
import 'package:mascoti/core/notificaciones/push/push_messaging.dart';

import '../fake_plugins.dart';

void main() {
  group('notificationRoute', () {
    test('las de citas abren el detalle de la cita', () {
      for (final tipo in [
        'cita_nueva', 'cita_aprobada', 'cita_rechazada', 'cita_cancelada', 'recordatorio_cita',
      ]) {
        expect(notificationRoute(tipo, 'a1'), '/reservas/a1', reason: tipo);
      }
    });

    test('la de vacuna abre el perfil de la mascota', () {
      expect(notificationRoute('vacuna', 'p1'), '/mascotas/perfil/p1');
    });

    test('sin pantalla específica o datos raros → null', () {
      expect(notificationRoute('pedido', 'o1'), isNull);
      expect(notificationRoute('desconocido', 'x'), isNull);
      expect(notificationRoute(null, 'a1'), isNull);
      expect(notificationRoute('cita_aprobada', null), isNull);
      expect(notificationRoute('cita_aprobada', ''), isNull);
      expect(notificationRoute('cita_aprobada', '../perfil'), isNull);
    });
  });

  group('resolveNotificationTarget', () {
    final registry = PluginRegistry([
      FakePlugin('reservas',
          roles: {UserRole.dueno, UserRole.clinica}, paths: ['/reservas', '/reservas/:id']),
      FakePlugin('mascotas',
          roles: {UserRole.dueno},
          paths: ['/mascotas', '/mascotas/perfil/:petId'],
          tabs: [tab('/mascotas', 10)]),
      FakePlugin('clinica', roles: {UserRole.clinica}, tabs: [tab('/clinica', 10)]),
    ]);

    test('va a la pantalla si existe y el rol la puede ver', () {
      expect(
        resolveNotificationTarget(route: '/reservas/a1', registry: registry, role: UserRole.dueno),
        '/reservas/a1',
      );
      expect(
        resolveNotificationTarget(
            route: '/mascotas/perfil/p1', registry: registry, role: UserRole.dueno),
        '/mascotas/perfil/p1',
      );
    });

    test('si la ruta no existe o el rol no la ve, al inicio del rol', () {
      final sinDetalle = PluginRegistry([
        FakePlugin('reservas', roles: {UserRole.dueno}, tabs: [tab('/reservas', 10)]),
      ]);
      expect(
        resolveNotificationTarget(route: '/reservas/a1', registry: sinDetalle, role: UserRole.dueno),
        '/reservas',
      );
      expect(
        resolveNotificationTarget(
            route: '/mascotas/perfil/p1', registry: registry, role: UserRole.clinica),
        '/clinica',
      );
      expect(
        resolveNotificationTarget(route: null, registry: registry, role: UserRole.dueno),
        '/mascotas',
      );
    });
  });

  test('tipos de notificación iguales al servidor', () {
    expect(NotificationType.values.map((t) => t.value), [
      'cita_nueva', 'cita_aprobada', 'cita_rechazada', 'cita_cancelada', 'recordatorio_cita',
      'vacuna', 'pedido', 'mensaje',
    ]);
  });

  test('payload de las notificaciones locales', () {
    expect(FirebasePushMessaging.stringData({'tipo': 'vacuna', 'n': 3}), {'tipo': 'vacuna', 'n': '3'});
    expect(FirebasePushMessaging.decodePayload('{"tipo":"vacuna","referenciaId":"p1"}'),
        {'tipo': 'vacuna', 'referenciaId': 'p1'});
    expect(FirebasePushMessaging.decodePayload('no es json'), isNull);
    expect(FirebasePushMessaging.decodePayload(null), isNull);
  });

  test('tiempo relativo del centro de notificaciones', () {
    final now = DateTime(2026, 11, 5, 12);
    expect(relativeTime(now.subtract(const Duration(seconds: 20)), now), 'Ahora');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now), 'Hace 5 min');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now), 'Hace 3 h');
    expect(relativeTime(now.subtract(const Duration(days: 1, hours: 2)), now), 'Ayer');
    expect(relativeTime(now.subtract(const Duration(days: 4)), now), 'Hace 4 días');
    expect(relativeTime(DateTime(2026, 10, 1, 9), now), '01/10/2026');
  });
}
