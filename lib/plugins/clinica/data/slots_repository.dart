import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/domain/slot.dart';

/// Franjas `clinics/{clinicId}/slots/{fecha}_{hora}` (RF-06). Desde el
/// Cambio 2 solo las escribe la Edge Function `citas` (candado de cada
/// reserva); la agenda las lee para saber qué está ocupado.
class SlotsRepository {
  SlotsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _slots(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).collection('slots');

  /// Franjas del día [fecha] ('YYYY-MM-DD'), por hora, en tiempo real.
  Stream<Map<String, Slot>> watchDay(String clinicId, String fecha) => _slots(clinicId)
      .where('fecha', isEqualTo: fecha)
      .snapshots()
      .map((snap) {
        final slots = [for (final doc in snap.docs) Slot.fromMap(doc.data())];
        return {for (final slot in slots) slot.hora: slot};
      });
}
