import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/domain/slot.dart';
import '../domain/day_schedule.dart';

/// El lote fue rechazado: alguna franja cambió mientras se editaba (p. ej. un
/// dueño la reservó) o la cuenta no tiene permisos.
class SlotsSaveRejected implements Exception {
  const SlotsSaveRejected();
}

/// Agenda `clinics/{clinicId}/slots/{fecha}_{hora}` (RF-06).
class SlotsRepository {
  SlotsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _slots(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).collection('slots');

  /// Franjas guardadas del día [fecha] ('YYYY-MM-DD'), por hora, en tiempo real.
  Stream<Map<String, Slot>> watchDay(String clinicId, String fecha) => _slots(clinicId)
      .where('fecha', isEqualTo: fecha)
      .snapshots()
      .map((snap) {
        final slots = [for (final doc in snap.docs) Slot.fromMap(doc.data())];
        return {for (final slot in slots) slot.hora: slot};
      });

  /// Fechas del mes de [month] que tienen alguna franja (puntos del calendario).
  Stream<Set<String>> watchConfiguredDays(String clinicId, DateTime month) {
    final first = Slot.dateKey(DateTime(month.year, month.month));
    final last = Slot.dateKey(DateTime(month.year, month.month + 1, 0));
    return _slots(clinicId)
        .where('fecha', isGreaterThanOrEqualTo: first)
        .where('fecha', isLessThanOrEqualTo: last)
        .snapshots()
        .map((snap) => {for (final doc in snap.docs) doc.data()['fecha'] as String});
  }

  /// "Guardar Disponibilidad": escribe todos los cambios del día en un solo
  /// [WriteBatch]. Si las reglas rechazan alguno (p. ej. una franja que acaba
  /// de reservarse), no se aplica ninguno y lanza [SlotsSaveRejected].
  Future<void> saveDay(String clinicId, String fecha, DayChanges changes) async {
    if (changes.isEmpty) return;
    final batch = _firestore.batch();
    for (final slot in changes.upserts) {
      batch.set(_slots(clinicId).doc(slot.id), slot.toMap());
    }
    for (final hora in changes.deletes) {
      batch.delete(_slots(clinicId).doc(Slot.idFor(fecha, hora)));
    }
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw const SlotsSaveRejected();
      rethrow;
    }
  }
}
