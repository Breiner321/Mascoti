import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/domain/pet.dart';

/// Mascota de una cita, vista por la clínica (RF-14): foto, especie,
/// alergias y condiciones. Al solicitar la cita, el servidor agrega la
/// clínica a `clinicasAutorizadas`, así que las reglas la dejan leer.
/// Solo lectura: los cambios de la cita van por AppointmentsRepository.
class ClinicPetRepository {
  ClinicPetRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// La mascota, o null si no existe.
  Stream<Pet?> watchPet(String petId) =>
      _firestore.collection('pets').doc(petId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : Pet.fromMap(doc.id, data);
      });
}
