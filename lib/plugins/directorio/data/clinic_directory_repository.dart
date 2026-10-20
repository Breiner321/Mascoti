import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/domain/clinic.dart';
import '../../../core/domain/clinic_service.dart';

/// Perfil público de una clínica (RF-09): datos y servicios activos. Las
/// reglas dejan leer `clinics` y sus `services` a cualquier usuario con
/// sesión. La búsqueda por cercanía está en el core (ClinicsGeoRepository).
class ClinicDirectoryRepository {
  ClinicDirectoryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// La clínica, o null si no existe.
  Stream<Clinic?> watchClinic(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : Clinic.fromMap(doc.id, data);
      });

  /// Servicios activos, ordenados por nombre (en el cliente: son pocos).
  Stream<List<ClinicService>> watchActiveServices(String clinicId) => _firestore
      .collection('clinics')
      .doc(clinicId)
      .collection('services')
      .where('activo', isEqualTo: true)
      .snapshots()
      .map((snap) => [
            for (final d in snap.docs) ClinicService.fromMap(d.id, d.data())
          ]..sort((a, b) =>
              a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase())));
}
