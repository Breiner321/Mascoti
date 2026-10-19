import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/domain/pet.dart';

/// Pacientes de la clínica: las mascotas que la autorizaron
/// (`pets.clinicasAutorizadas` contiene su id, lo agrega la Edge Function
/// `vincular-mascota`).
///
/// La clínica no puede leer `users/{ownerUid}`, así que el nombre del dueño
/// que devuelve la vinculación se guarda en `clinics/{clinicId}/pacientes/{petId}`
/// para mostrarlo en la lista.
class PatientsRepository {
  PatientsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _owners(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).collection('pacientes');

  /// Mascotas autorizadas en tiempo real, ordenadas por nombre. Se ordena en
  /// el cliente para no necesitar un índice compuesto.
  Stream<List<Pet>> watchPatients(String clinicId) => _firestore
          .collection('pets')
          .where('clinicasAutorizadas', arrayContains: clinicId)
          .snapshots()
          .map((snap) {
        final pets = [for (final d in snap.docs) Pet.fromMap(d.id, d.data())];
        pets.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
        return pets;
      });

  /// Una mascota. null si no existe o si el dueño revocó el acceso (las
  /// reglas niegan la lectura).
  Stream<Pet?> watchPatient(String petId) async* {
    try {
      await for (final d in _firestore.collection('pets').doc(petId).snapshots()) {
        yield d.exists ? Pet.fromMap(d.id, d.data()!) : null;
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      yield null;
    }
  }

  /// Nombre del dueño de cada paciente, por petId.
  Stream<Map<String, String>> watchOwnerNames(String clinicId) =>
      _owners(clinicId).snapshots().map((snap) => {
            for (final d in snap.docs) d.id: d.data()['duenoNombre'] as String? ?? '',
          });

  /// Guarda el nombre del dueño tras vincular la mascota. Las reglas exigen
  /// que la mascota ya haya autorizado a la clínica.
  Future<void> saveOwnerName({
    required String clinicId,
    required String petId,
    required String duenoNombre,
  }) =>
      _owners(clinicId).doc(petId).set({
        'duenoNombre': duenoNombre,
        'vinculadoAt': FieldValue.serverTimestamp(),
      });
}
