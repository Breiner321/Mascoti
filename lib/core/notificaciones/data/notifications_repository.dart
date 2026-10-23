import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/app_notification.dart';

/// Centro de notificaciones (RF-13): `notifications` del usuario, en tiempo
/// real. Las crea el servidor; la app solo las marca como leídas.
class NotificationsRepository {
  NotificationsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Cuántas se muestran en la lista (las más recientes).
  static const pageSize = 50;

  /// Tope del contador de la campana ("99+").
  static const maxUnread = 100;

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');

  /// Las más recientes primero.
  Stream<List<AppNotification>> watchNotifications(String uid) => _notifications
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(pageSize)
      .snapshots()
      .map((snap) => [for (final d in snap.docs) AppNotification.fromMap(d.id, d.data())]);

  /// Número de no leídas, hasta [maxUnread].
  Stream<int> watchUnreadCount(String uid) => _notifications
      .where('uid', isEqualTo: uid)
      .where('leido', isEqualTo: false)
      .limit(maxUnread)
      .snapshots()
      .map((snap) => snap.size);

  Future<void> markAsRead(String notificationId) =>
      _notifications.doc(notificationId).update({'leido': true});

  /// Marca como leídas todas las no leídas del usuario.
  Future<void> markAllAsRead(String uid) async {
    final unread = await _notifications
        .where('uid', isEqualTo: uid)
        .where('leido', isEqualTo: false)
        .limit(500)
        .get();
    if (unread.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final d in unread.docs) {
      batch.update(d.reference, {'leido': true});
    }
    await batch.commit();
  }
}
