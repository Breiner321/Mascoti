import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/domain/clinic.dart';

/// Datos de la clínica para la tienda del dueño (RF-12): nombre del selector,
/// pregunta de "otra clínica" y teléfono para "Llamar". Cualquier usuario con
/// sesión puede leer `clinics`.
class ShopClinicRepository {
  ShopClinicRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// La clínica, o null si no existe.
  Stream<Clinic?> watchClinic(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : Clinic.fromMap(doc.id, data);
      });
}

/// Ubicación del dueño para "Cerca de ti". null si no da permiso o el GPS
/// no responde (entonces solo se ofrecen "Tus clínicas").
abstract interface class OwnerLocation {
  Future<({double lat, double lng})?> current();
}

class GeolocatorOwnerLocation implements OwnerLocation {
  const GeolocatorOwnerLocation();

  @override
  Future<({double lat, double lng})?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(timeLimit: Duration(seconds: 15)),
      );
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : (lat: last.latitude, lng: last.longitude);
    }
  }
}
