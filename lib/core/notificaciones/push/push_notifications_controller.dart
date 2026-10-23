import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/device_registry.dart';
import 'push_messaging.dart';

/// Conecta el push con la sesión (RF-13):
/// - al iniciar sesión pide el permiso, registra el token del dispositivo y
///   lo actualiza cuando FCM lo cambia;
/// - al cerrar sesión borra el token (RF-03);
/// - entrega a [onTap] el `data` de cada notificación tocada.
class PushNotificationsController {
  PushNotificationsController({
    required PushMessaging messaging,
    required DeviceRegistry devices,
    required void Function(Map<String, String> data) onTap,
  })  : _messaging = messaging,
        _devices = devices,
        _onTap = onTap;

  final PushMessaging _messaging;
  final DeviceRegistry _devices;
  final void Function(Map<String, String> data) _onTap;

  static const _signOutTimeout = Duration(seconds: 3);

  StreamSubscription<Map<String, String>>? _tapSubscription;
  StreamSubscription<String>? _refreshSubscription;
  Future<void>? _started;
  String? _uid;

  /// Usuario cuyo token está registrado en este dispositivo.
  String? get registeredUid => _uid;

  /// Prepara el push y entrega el toque que abrió la app, si lo hubo.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    try {
      await _messaging.initialize();
      _tapSubscription = _messaging.taps.listen(_onTap);
      final initial = await _messaging.initialTap();
      if (initial != null) _onTap(initial);
    } catch (e) {
      debugPrint('RF-13: no se pudo iniciar el push: $e');
    }
  }

  /// Registra el token de [uid]. Si el usuario niega el permiso igual se
  /// registra: el centro de notificaciones funciona y, si luego lo activa en
  /// Ajustes, los push llegan sin volver a iniciar sesión.
  Future<void> signedIn(String uid) async {
    if (_uid == uid) return;
    _uid = uid;
    await _refreshSubscription?.cancel();
    _refreshSubscription = _messaging.onTokenRefresh.listen((token) {
      final current = _uid;
      if (current != null) unawaited(_register(current, token));
    });
    try {
      await start();
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null && _uid == uid) await _register(uid, token);
    } catch (e) {
      debugPrint('RF-13: no se pudo registrar el dispositivo: $e');
    }
  }

  Future<void> _register(String uid, String token) async {
    try {
      await _devices.register(uid, token);
    } catch (e) {
      debugPrint('RF-13: no se pudo guardar el token: $e');
    }
  }

  /// Cierre de sesión (RF-03): borra el documento del dispositivo e invalida
  /// el token en FCM. Se llama ANTES de salir de Firebase Auth (las reglas
  /// exigen la sesión). Sin red no bloquea el logout: el servidor marcará el
  /// token inválido cuando FCM lo rechace.
  Future<void> signedOut() async {
    final uid = _uid;
    forget();
    if (uid == null) return;
    await Future.wait([
      _quietly(() => _devices.unregister(uid)),
      _quietly(_messaging.deleteToken),
    ]);
  }

  /// La sesión terminó sin pasar por [signedOut] (p. ej. cuenta suspendida):
  /// deja de actualizar el token.
  void forget() {
    _uid = null;
    unawaited(_refreshSubscription?.cancel());
    _refreshSubscription = null;
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action().timeout(_signOutTimeout);
    } catch (_) {
      // Sin red o sin permiso: no impide cerrar sesión.
    }
  }

  void dispose() {
    unawaited(_tapSubscription?.cancel());
    unawaited(_refreshSubscription?.cancel());
  }
}
