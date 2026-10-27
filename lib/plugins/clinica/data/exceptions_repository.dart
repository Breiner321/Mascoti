import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/domain/schedule_exception.dart';

/// Excepciones al horario de la clínica (Cambio 2):
/// `clinics/{clinicId}/excepciones/{id}`. Se crean y se borran; no se editan.
class ExceptionsRepository {
  ExceptionsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _exceptions(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).collection('excepciones');

  /// Excepciones que terminan el [desde] ('YYYY-MM-DD') o después, en tiempo real.
  Stream<List<ScheduleException>> watchFrom(String clinicId, String desde) =>
      _exceptions(clinicId)
          .where('fechaFin', isGreaterThanOrEqualTo: desde)
          .snapshots()
          .map((snap) => [
                for (final d in snap.docs) ScheduleException.tryFromMap(d.id, d.data()),
              ].whereType<ScheduleException>().toList());

  /// Guarda varias excepciones en un solo lote (p. ej. un bloqueo por cada
  /// rango de franjas seleccionadas).
  Future<void> addAll(String clinicId, Iterable<ScheduleException> exceptions) async {
    final batch = _firestore.batch();
    for (final e in exceptions) {
      batch.set(_exceptions(clinicId).doc(), e.toMap());
    }
    await batch.commit();
  }

  Future<void> delete(String clinicId, String exceptionId) =>
      _exceptions(clinicId).doc(exceptionId).delete();
}
