import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/qr_tag.dart';

/// Placas QR (RF-17): `qrTags`, escritas directo desde la app (firestore.rules
/// valida que la mascota sea del usuario). La página pública no las lee:
/// usa la Edge Function `placa-publica`.
class QrTagsRepository {
  QrTagsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tags => _firestore.collection('qrTags');

  /// Placa vigente de la mascota: la activa más reciente o, si no hay
  /// activa, la más reciente (desactivada). null si nunca tuvo placa.
  ///
  /// Solo filtros de igualdad (sin orderBy): no necesita índice compuesto.
  Stream<QrTag?> watchPetTag(String ownerUid, String petId) => _tags
      .where('ownerUid', isEqualTo: ownerUid)
      .where('petId', isEqualTo: petId)
      .snapshots()
      .map((snap) {
        final tags = [for (final d in snap.docs) QrTag.fromMap(d.id, d.data())]
          ..sort((a, b) {
            if (a.activo != b.activo) return a.activo ? -1 : 1;
            return (b.createdAt ?? DateTime(9999)).compareTo(a.createdAt ?? DateTime(9999));
          });
        return tags.isEmpty ? null : tags.first;
      });

  /// Crea una placa activa con un id aleatorio nuevo. Devuelve el id.
  Future<String> create({
    required String ownerUid,
    required String petId,
    required QrTagDisplay mostrar,
  }) async {
    final id = QrTag.newId();
    await _tags.doc(id).set({
      'petId': petId,
      'ownerUid': ownerUid,
      'activo': true,
      'mostrar': mostrar.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  /// "Desactivar placa" (perdida o reemplazada) o volver a activarla.
  Future<void> setActive(String qrId, bool activo) =>
      _tags.doc(qrId).update({'activo': activo});

  /// Cambia qué ve quien escanea.
  Future<void> updateDisplay(String qrId, QrTagDisplay mostrar) =>
      _tags.doc(qrId).update({'mostrar': mostrar.toMap()});
}
