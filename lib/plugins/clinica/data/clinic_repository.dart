import 'package:cloud_firestore/cloud_firestore.dart';

/// Acceso a `clinics/{clinicId}` desde el plugin clinica (RF-04..06).
class ClinicRepository {
  ClinicRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// `estado` de la clínica ('incompleto' | 'activo') en tiempo real.
  /// Emite null si el documento no existe.
  Stream<String?> watchEstado(String clinicId) => _firestore
      .collection('clinics')
      .doc(clinicId)
      .snapshots()
      .map((snap) => snap.data()?['estado'] as String?);
}
