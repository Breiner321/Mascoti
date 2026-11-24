import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/domain/pet.dart';

/// Datos de apoyo del chat que no están en `chats`: mascotas vinculadas
/// (bandeja de la clínica y "Desde el historial") y nombre de la clínica
/// (para abrir una conversación).
class ChatLookupRepository {
  ChatLookupRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Mascotas que autorizaron a la clínica (las mismas que su lista de
  /// pacientes), en tiempo real.
  Stream<List<Pet>> watchLinkedPets(String clinicId) => _firestore
      .collection('pets')
      .where('clinicasAutorizadas', arrayContains: clinicId)
      .snapshots()
      .map((snap) => [for (final d in snap.docs) Pet.fromMap(d.id, d.data())]);

  /// Una mascota, o null si no existe o ya no se puede leer.
  Future<Pet?> fetchPet(String petId) async {
    try {
      final d = await _firestore.collection('pets').doc(petId).get();
      return d.exists ? Pet.fromMap(d.id, d.data()!) : null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  /// Nombre y dueño (usuario que la maneja) de la clínica, o null si no
  /// existe.
  Future<({String nombre, String ownerUid})?> fetchClinic(String clinicId) async {
    final d = await _firestore.collection('clinics').doc(clinicId).get();
    final data = d.data();
    if (data == null) return null;
    return (
      nombre: data['nombre'] as String? ?? '',
      ownerUid: data['ownerUid'] as String? ?? '',
    );
  }
}
