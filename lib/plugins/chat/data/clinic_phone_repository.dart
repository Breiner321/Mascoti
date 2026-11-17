import 'package:cloud_firestore/cloud_firestore.dart';

/// Teléfono de la clínica para el botón "Llamar" de la conversación del
/// dueño (RF-15). Cualquier usuario con sesión puede leer `clinics`.
class ClinicPhoneRepository {
  ClinicPhoneRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// El teléfono, o null si no tiene o la clínica no existe.
  Future<String?> fetchPhone(String clinicId) async {
    final data = (await _firestore.collection('clinics').doc(clinicId).get()).data();
    final phone = (data?['telefono'] as String?)?.trim();
    return phone == null || phone.isEmpty ? null : phone;
  }
}
