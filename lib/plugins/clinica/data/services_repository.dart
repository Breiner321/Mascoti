import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/domain/clinic_service.dart';

/// Las reglas rechazaron la escritura: el servicio no es de una clínica del
/// usuario o su cuenta no está activa.
class ServicePermissionDenied implements Exception {
  const ServicePermissionDenied();
}

/// Catálogo `clinics/{clinicId}/services` (RF-05). Nunca se borra un
/// documento: se desactiva con `activo: false` (soft delete).
class ServicesRepository {
  ServicesRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _services(String clinicId) =>
      _firestore.collection('clinics').doc(clinicId).collection('services');

  /// Servicios activos en tiempo real, ordenados por nombre. Se ordena en el
  /// cliente para no necesitar un índice compuesto (activo + nombre).
  Stream<List<ClinicService>> watchActive(String clinicId) => _services(clinicId)
      .where('activo', isEqualTo: true)
      .snapshots()
      .map((snap) {
        final list = [
          for (final doc in snap.docs) ClinicService.fromMap(doc.id, doc.data()),
        ];
        list.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
        return list;
      });

  /// Id para un servicio nuevo. Se genera antes de guardar para que
  /// reintentar tras un fallo de red escriba el mismo documento y no duplique.
  String newId(String clinicId) => _services(clinicId).doc().id;

  /// Crea ([isNew]) o actualiza el servicio. Al editar solo se envían los
  /// campos editables; `createdAt` y `activo` no cambian.
  Future<void> save(
    String clinicId,
    ClinicService service, {
    required bool isNew,
  }) {
    final doc = _services(clinicId).doc(service.id);
    final fields = <String, dynamic>{
      'nombre': service.nombre,
      'categoria': service.categoria.value,
      'descripcion': service.descripcion,
      'precio': service.precio,
      'duracionMin': service.duracionMin,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    return _guard(
      isNew
          ? doc.set({
              ...fields,
              'activo': true,
              'createdAt': FieldValue.serverTimestamp(),
            })
          : doc.update(fields),
    ).then((_) => syncCategories(clinicId));
  }

  /// Borrado lógico (RF-05 paso 12): conserva el documento para el historial
  /// de citas.
  Future<void> deactivate(String clinicId, String serviceId) => _guard(
        _services(clinicId).doc(serviceId).update({
          'activo': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      ).then((_) => syncCategories(clinicId));

  /// Actualiza `clinics/{clinicId}.categoriasServicio` con las categorías de
  /// los servicios activos, para que el directorio (RF-09) filtre por
  /// servicio sin leer la subcolección de cada clínica. Si falla, el
  /// servicio ya quedó guardado: se vuelve a sincronizar en el próximo
  /// cambio.
  Future<void> syncCategories(String clinicId) async {
    try {
      final active = await _services(clinicId).where('activo', isEqualTo: true).get();
      final categories = {
        for (final doc in active.docs) ServiceCategory.fromValue(doc.data()['categoria']),
      }.toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      await _firestore.collection('clinics').doc(clinicId).update({
        'categoriasServicio': [for (final c in categories) c.value],
      });
    } on FirebaseException {
      // No bloquea al usuario: el catálogo ya se actualizó.
    }
  }

  /// Citas 'pendiente' o 'confirmada' del servicio (flujo alternativo de
  /// RF-05 al eliminar).
  // TODO(RF-14, semana 4): contar en `appointments` donde clinicId y
  // serviceId coinciden y estado ∈ {pendiente, confirmada}.
  Future<int> activeAppointmentsCount(String clinicId, String serviceId) async => 0;

  Future<void> _guard(Future<void> write) async {
    try {
      await write;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw const ServicePermissionDenied();
      rethrow;
    }
  }
}
