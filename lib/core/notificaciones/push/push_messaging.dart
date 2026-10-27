import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Lo que la app necesita del sistema de push. Las pruebas usan un falso;
/// [FirebasePushMessaging] es la implementación real.
abstract class PushMessaging {
  /// Prepara los canales y los listeners. Se llama una vez.
  Future<void> initialize();

  /// Pide el permiso de notificaciones (Android 13+: POST_NOTIFICATIONS).
  /// false si el usuario lo negó: el centro de notificaciones sigue
  /// funcionando, solo no llega el push nativo.
  Future<bool> requestPermission();

  Future<String?> getToken();
  Stream<String> get onTokenRefresh;

  /// Invalida el token en FCM (al cerrar sesión).
  Future<void> deleteToken();

  /// `data` de la notificación que abrió la app cuando estaba cerrada.
  Future<Map<String, String>?> initialTap();

  /// `data` de cada notificación tocada con la app abierta o en segundo plano.
  Stream<Map<String, String>> get taps;
}

/// FCM + flutter_local_notifications.
///
/// - App cerrada o en segundo plano: el sistema muestra el push (canal del
///   mensaje) y FCM avisa el toque con getInitialMessage / onMessageOpenedApp.
/// - App abierta: FCM no muestra nada, así que se muestra una notificación
///   local con el mismo `data` como payload.
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging({FirebaseMessaging? messaging, FlutterLocalNotificationsPlugin? local})
      : _messaging = messaging ?? FirebaseMessaging.instance,
        _local = local ?? FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local;
  final _taps = StreamController<Map<String, String>>.broadcast();

  /// Canales de Android; iguales a CANAL_GENERAL / CANAL_URGENTE del servidor.
  static final general = const AndroidNotificationChannel(
    'mascoti_general',
    'Citas y recordatorios',
    description: 'Cambios de tus citas y recordatorios de citas y vacunas',
    importance: Importance.high,
  );
  static final urgent = const AndroidNotificationChannel(
    'mascoti_urgente',
    'Avisos urgentes',
    description: 'Citas canceladas por la clínica',
    importance: Importance.max,
  );

  @override
  Future<void> initialize() async {
    final android =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(general);
    await android?.createNotificationChannel(urgent);
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final data = decodePayload(response.payload);
        if (data != null) _taps.add(data);
      },
    );
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(stringData(m.data)));
    FirebaseMessaging.onMessage.listen(_showInForeground);
  }

  Future<void> _showInForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final channel =
        message.notification?.android?.channelId == urgent.id ? urgent : general;
    await _local.show(
      id: message.messageId.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: channel == urgent ? Priority.max : Priority.high,
        ),
      ),
      payload: jsonEncode(stringData(message.data)),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Future<Map<String, String>?> initialTap() async {
    final message = await _messaging.getInitialMessage();
    if (message != null) return stringData(message.data);
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      return decodePayload(launch!.notificationResponse?.payload);
    }
    return null;
  }

  @override
  Stream<Map<String, String>> get taps => _taps.stream;

  @visibleForTesting
  static Map<String, String> stringData(Map<String, dynamic> data) =>
      {for (final e in data.entries) e.key: '${e.value}'};

  @visibleForTesting
  static Map<String, String>? decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map ? {for (final e in decoded.entries) '${e.key}': '${e.value}'} : null;
    } on FormatException {
      return null;
    }
  }
}
