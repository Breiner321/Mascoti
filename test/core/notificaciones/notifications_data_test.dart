import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/notificaciones/data/device_registry.dart';
import 'package:mascoti/core/notificaciones/data/notifications_repository.dart';
import 'package:mascoti/core/notificaciones/domain/app_notification.dart';
import 'package:mascoti/core/notificaciones/push/push_messaging.dart';
import 'package:mascoti/core/notificaciones/push/push_notifications_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePushMessaging implements PushMessaging {
  bool permission = true;
  String? token = 'tok-1';
  Map<String, String>? initial;
  final refresh = StreamController<String>.broadcast();
  final tapController = StreamController<Map<String, String>>.broadcast();
  int deleted = 0;
  int permissionRequests = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Future<void> deleteToken() async => deleted++;

  @override
  Future<Map<String, String>?> initialTap() async => initial;

  @override
  Stream<Map<String, String>> get taps => tapController.stream;
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({});
  });

  group('NotificationsRepository', () {
    late NotificationsRepository repository;

    setUp(() => repository = NotificationsRepository(firestore: firestore));

    Future<void> seed(String id, {String uid = 'ana', bool leido = false, int minute = 0}) =>
        firestore.doc('notifications/$id').set({
          'uid': uid,
          'tipo': 'cita_aprobada',
          'titulo': 'T$id',
          'cuerpo': 'C',
          'referenciaId': 'a1',
          'leido': leido,
          'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1, 9, minute)),
        });

    test('lista solo las del usuario, la más reciente primero', () async {
      await seed('n1', minute: 1);
      await seed('n2', minute: 5, leido: true);
      await seed('n3', uid: 'beto', minute: 9);

      final list = await repository.watchNotifications('ana').first;
      expect(list.map((n) => n.id), ['n2', 'n1']);
      expect(list.last.tipo, NotificationType.citaAprobada);
      expect(list.last.leido, isFalse);
    });

    test('contador de no leídas en tiempo real y marcar todas como leídas', () async {
      await seed('n1');
      await seed('n2');
      await seed('n3', leido: true);
      await seed('n4', uid: 'beto');

      final counts = <int>[];
      final sub = repository.watchUnreadCount('ana').listen(counts.add);
      await pumpEventQueue();
      await repository.markAsRead('n1');
      await pumpEventQueue();
      await repository.markAllAsRead('ana');
      await pumpEventQueue();
      await sub.cancel();

      expect(counts.first, 2);
      expect(counts.last, 0);
      final beto = (await firestore.doc('notifications/n4').get()).data()!;
      expect(beto['leido'], isFalse);
    });
  });

  group('DeviceRegistry', () {
    test('guarda el token en users/{uid}/devices/{deviceId} con un id estable', () async {
      final registry = DeviceRegistry(firestore: firestore);
      await registry.register('ana', 'tok-1');
      final id = await registry.deviceId();
      expect(id, hasLength(20));

      final doc = (await firestore.doc('users/ana/devices/$id').get()).data()!;
      expect(doc['fcmToken'], 'tok-1');
      expect(doc['plataforma'], 'android');
      expect(doc['valido'], isTrue);
      expect(doc['updatedAt'], isA<Timestamp>());

      // Otra instancia (la app se reinició) usa el mismo id.
      expect(await DeviceRegistry(firestore: firestore).deviceId(), id);

      await registry.unregister('ana');
      expect((await firestore.doc('users/ana/devices/$id').get()).exists, isFalse);
    });
  });

  group('PushNotificationsController', () {
    late FakePushMessaging messaging;
    late DeviceRegistry devices;
    late List<Map<String, String>> taps;
    late PushNotificationsController controller;

    setUp(() {
      messaging = FakePushMessaging();
      devices = DeviceRegistry(firestore: firestore);
      taps = [];
      controller = PushNotificationsController(
        messaging: messaging,
        devices: devices,
        onTap: taps.add,
      );
    });

    tearDown(() => controller.dispose());

    Future<Map<String, dynamic>?> device(String uid) async =>
        (await firestore.doc('users/$uid/devices/${await devices.deviceId()}').get()).data();

    test('al iniciar sesión pide permiso y registra el token', () async {
      await controller.signedIn('ana');
      expect(messaging.permissionRequests, 1);
      expect((await device('ana'))!['fcmToken'], 'tok-1');
      expect(controller.registeredUid, 'ana');

      // El perfil se vuelve a emitir con el mismo usuario: no repite.
      await controller.signedIn('ana');
      expect(messaging.permissionRequests, 1);
    });

    test('sin permiso igual registra (el centro de notificaciones funciona)', () async {
      messaging.permission = false;
      await controller.signedIn('ana');
      expect((await device('ana'))!['valido'], isTrue);
    });

    test('onTokenRefresh actualiza el token', () async {
      await controller.signedIn('ana');
      messaging.refresh.add('tok-2');
      await pumpEventQueue();
      expect((await device('ana'))!['fcmToken'], 'tok-2');
    });

    test('al cerrar sesión borra el token y deja de actualizarlo', () async {
      await controller.signedIn('ana');
      await controller.signedOut();

      expect(await device('ana'), isNull);
      expect(messaging.deleted, 1);
      expect(controller.registeredUid, isNull);
      messaging.refresh.add('tok-3');
      await pumpEventQueue();
      expect(await device('ana'), isNull);
    });

    test('entrega el toque que abrió la app y los siguientes', () async {
      messaging.initial = {'tipo': 'vacuna', 'referenciaId': 'p1'};
      await controller.start();
      messaging.tapController.add({'tipo': 'cita_aprobada', 'referenciaId': 'a1'});
      await pumpEventQueue();
      expect(taps, [
        {'tipo': 'vacuna', 'referenciaId': 'p1'},
        {'tipo': 'cita_aprobada', 'referenciaId': 'a1'},
      ]);
    });
  });
}
