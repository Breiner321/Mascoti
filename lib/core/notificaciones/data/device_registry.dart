import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tokens FCM de cada dispositivo del usuario (RF-13):
/// `users/{uid}/devices/{deviceId}` `{fcmToken, plataforma, updatedAt, valido}`.
///
/// [deviceId] es un id aleatorio que se guarda en el teléfono la primera vez,
/// así cada instalación tiene un solo documento aunque el token cambie.
class DeviceRegistry {
  DeviceRegistry({
    FirebaseFirestore? firestore,
    Future<SharedPreferences> Function()? preferences,
    String platform = 'android',
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _preferences = preferences ?? SharedPreferences.getInstance,
        _platform = platform;

  final FirebaseFirestore _firestore;
  final Future<SharedPreferences> Function() _preferences;
  final String _platform;

  static const _deviceIdKey = 'mascoti.deviceId';
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  String? _deviceId;

  /// Id de esta instalación (se crea la primera vez).
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await _preferences();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      final random = Random.secure();
      id = List.generate(20, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
      await prefs.setString(_deviceIdKey, id);
    }
    return _deviceId = id;
  }

  DocumentReference<Map<String, dynamic>> _doc(String uid, String deviceId) =>
      _firestore.collection('users').doc(uid).collection('devices').doc(deviceId);

  /// Guarda (o actualiza) el token de este dispositivo como válido. Si el
  /// servidor lo había marcado inválido, vuelve a quedar válido con el token
  /// nuevo (RF-13: "regenerarlo en el próximo inicio de sesión").
  Future<void> register(String uid, String token) async {
    await _doc(uid, await deviceId()).set({
      'fcmToken': token,
      'plataforma': _platform,
      'updatedAt': FieldValue.serverTimestamp(),
      'valido': true,
    });
  }

  /// Borra el token de este dispositivo (al cerrar sesión, RF-03).
  Future<void> unregister(String uid) async {
    await _doc(uid, await deviceId()).delete();
  }
}
