import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/data/saved_clinics_store.dart';
import '../../../core/domain/clinic.dart';
import '../domain/emergency_ranking.dart';

/// Datos del SOS (RF-10): aliadas cercanas con radio creciente, clínicas
/// favoritas del dueño y el evento de auditoría `emergencyTriggered`.
class SosRepository {
  SosRepository({required ClinicsGeoRepository geo, FirebaseFirestore? firestore})
      : _geo = geo,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final ClinicsGeoRepository _geo;
  final FirebaseFirestore _firestore;

  /// Sin respuesta en este tiempo se trata como sin conexión: la pantalla
  /// sigue con las clínicas guardadas.
  static const timeout = Duration(seconds: 10);

  /// Favoritas: las clínicas de las citas más recientes del dueño.
  static const maxFavorites = SavedClinicsStore.maxFavorites;

  /// Aliadas activas alrededor de ([lat], [lng]), de 10 en 10 km hasta
  /// tener al menos 3 o llegar a 50 km. Lanza si no hay conexión.
  Future<List<NearbyClinic>> fetchAllies(double lat, double lng) async {
    var radius = EmergencyRanking.radiiKm.first;
    while (true) {
      final found =
          await _geo.fetchNearby(lat: lat, lng: lng, radiusKm: radius).timeout(timeout);
      final next = EmergencyRanking.nextRadius(radius, found.length);
      if (next == null) return found;
      radius = next;
    }
  }

  /// Clínicas de las citas del dueño (la más reciente primero), para
  /// guardarlas en el teléfono como favoritas.
  Future<List<SavedClinic>> fetchFavorites(String ownerUid) async {
    final appointments = await _firestore
        .collection('appointments')
        .where('ownerUid', isEqualTo: ownerUid)
        .orderBy('inicio', descending: true)
        .limit(30)
        .get()
        .timeout(timeout);
    final ids = <String>[];
    for (final doc in appointments.docs) {
      final id = doc.data()['clinicId'];
      if (id is String && id.isNotEmpty && !ids.contains(id)) ids.add(id);
      if (ids.length == maxFavorites) break;
    }
    final clinics = await Future.wait(
      ids.map((id) => _firestore.collection('clinics').doc(id).get().timeout(timeout)),
    );
    return [
      for (final doc in clinics)
        if (doc.data() case final data?)
          if (Clinic.fromMap(doc.id, data) case final clinic when clinic.isActive)
            SavedClinic.fromClinic(clinic),
    ];
  }

  /// Registra `auditEvents` con la ubicación aproximada (~1 km) si se
  /// conoce. Las reglas solo dejan crear eventos propios.
  Future<void> logEmergency({required String uid, double? lat, double? lng}) =>
      _firestore.collection('auditEvents').add({
        'tipo': 'emergencyTriggered',
        'uid': uid,
        if (lat != null && lng != null) ...{'lat': approximate(lat), 'lng': approximate(lng)},
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// Dos decimales: ~1 km, suficiente para estadísticas.
  static double approximate(double degrees) => (degrees * 100).roundToDouble() / 100;
}
