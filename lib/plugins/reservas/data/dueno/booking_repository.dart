import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/domain/clinic.dart';
import '../../../../core/domain/clinic_service.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/domain/slot.dart';

/// Lecturas que necesita el dueño para agendar (RF-14): la clínica, sus
/// servicios activos, las franjas del mes y sus mascotas. Las escrituras van
/// por `AppointmentsRepository` (Edge Function `citas`).
class BookingRepository {
  BookingRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _clinic(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId);

  /// La clínica, o null si no existe.
  Stream<Clinic?> watchClinic(String clinicId) => _clinic(clinicId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : Clinic.fromMap(doc.id, data);
      });

  /// Servicios activos, ordenados por nombre (en el cliente: son pocos).
  Stream<List<ClinicService>> watchActiveServices(String clinicId) => _clinic(clinicId)
      .collection('services')
      .where('activo', isEqualTo: true)
      .snapshots()
      .map((snap) => [for (final d in snap.docs) ClinicService.fromMap(d.id, d.data())]
        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase())));

  /// Todas las franjas del mes [year]-[month], en tiempo real. Se filtran por
  /// servicio y estado en el cliente (`booking_logic.dart`) para no necesitar
  /// un índice compuesto: una clínica tiene pocos cientos de franjas al mes.
  Stream<List<Slot>> watchMonthSlots(String clinicId, int year, int month) {
    final first = Slot.dateKey(DateTime(year, month));
    final last = Slot.dateKey(DateTime(year, month + 1, 0));
    return _clinic(clinicId)
        .collection('slots')
        .where('fecha', isGreaterThanOrEqualTo: first)
        .where('fecha', isLessThanOrEqualTo: last)
        .snapshots()
        .map((snap) => [for (final d in snap.docs) Slot.fromMap(d.data())]);
  }

  /// Mascotas del dueño, por nombre.
  Stream<List<Pet>> watchPets(String ownerUid) => _firestore
      .collection('pets')
      .where('ownerUid', isEqualTo: ownerUid)
      .snapshots()
      .map((snap) => [for (final d in snap.docs) Pet.fromMap(d.id, d.data())]
        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase())));
}
