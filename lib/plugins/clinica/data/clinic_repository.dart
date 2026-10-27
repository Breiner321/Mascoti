import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/domain/animal_type.dart';
import '../../../core/domain/clinic.dart';
import '../../../core/domain/weekly_schedule.dart';

/// Las reglas rechazaron la escritura: la clínica no pertenece al usuario o
/// su cuenta no está activa (RF-04, flujo alternativo "Error de autorización").
class ClinicPermissionDenied implements Exception {
  const ClinicPermissionDenied();
}

/// Acceso a `clinics/{clinicId}` desde el plugin clinica (RF-04..06).
class ClinicRepository {
  ClinicRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId);

  /// `estado` de la clínica ('incompleto' | 'activo') en tiempo real.
  /// Emite null si el documento no existe.
  Stream<String?> watchEstado(String clinicId) => _doc(clinicId)
      .snapshots()
      .map((snap) => snap.data()?['estado'] as String?);

  /// La clínica en tiempo real; null si el documento no existe.
  Stream<Clinic?> watchClinic(String clinicId) =>
      _doc(clinicId).snapshots().map((snap) {
        final data = snap.data();
        return data == null ? null : Clinic.fromMap(snap.id, data);
      });

  /// RF-04: guarda el perfil de atención. Si es la primera configuración,
  /// pasa `estado` de 'incompleto' a 'activo' en la misma escritura.
  /// Lanza [ClinicPermissionDenied] si las reglas rechazan el cambio.
  Future<void> saveCareProfile(
    Clinic current, {
    required List<AnimalType> tiposAnimales,
    required bool atencionEmergencias,
    required WeeklySchedule horarioSemanal,
    required BookingSettings reservas,
  }) async {
    final update = <String, dynamic>{
      'tiposAnimales': [for (final t in tiposAnimales) t.value],
      'atencionEmergencias': atencionEmergencias,
      // Cambio 2: reemplaza a horarioBase (que ya no se escribe).
      'horarioSemanal': horarioSemanal.toMap(),
      'reservas': reservas.toMap(),
      if (!current.isActive) 'estado': ClinicStatus.activo.value,
    };
    try {
      await _doc(current.id).update(update);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw const ClinicPermissionDenied();
      rethrow;
    }
  }
}
