import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/pet.dart';

/// Acceso a `pets` desde el plugin mascotas.
class PetsRepository {
  PetsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Mascotas del dueño, la más reciente primero.
  ///
  /// Se ordena en el cliente para no necesitar un índice compuesto
  /// (ownerUid + createdAt): un dueño tiene pocas mascotas.
  Stream<List<Pet>> watchPets(String ownerUid) => _firestore
      .collection('pets')
      .where('ownerUid', isEqualTo: ownerUid)
      .snapshots()
      .map((snap) {
        final pets = [for (final d in snap.docs) Pet.fromMap(d.id, d.data())];
        pets.sort((a, b) {
          final ad = a.createdAt, bd = b.createdAt;
          if (ad == null || bd == null) return a.nombre.compareTo(b.nombre);
          return bd.compareTo(ad);
        });
        return pets;
      });
}
