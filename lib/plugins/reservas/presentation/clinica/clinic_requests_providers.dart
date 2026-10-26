import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/data/appointments_providers.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/storage/storage_providers.dart';
import '../../../../core/storage/storage_repository.dart';
import '../../data/clinica/clinic_pet_repository.dart';

final clinicPetRepositoryProvider = Provider<ClinicPetRepository>(
  (ref) => ClinicPetRepository(),
);

/// Mascota de una cita (foto, especie, alergias).
final clinicPetProvider = StreamProvider.autoDispose.family<Pet?, String>(
  (ref, petId) => ref.watch(clinicPetRepositoryProvider).watchPet(petId),
  retry: (_, __) => null,
);

/// Enlace temporal de la foto de la mascota (bucket `mascotas`).
final clinicPetPhotoUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref
      .watch(storageRepositoryProvider)
      .signedUrl(path, bucketId: StorageRepository.petsBucket),
  retry: (_, __) => null,
);

/// Hora actual (para decidir si ya se puede "Marcar como atendida").
/// Se reemplaza en las pruebas.
final appointmentClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Contador de la pestaña "Solicitudes": citas pendientes de la clínica.
final pendingRequestsCountProvider = Provider.autoDispose<int>((ref) {
  final clinicId = ref.watch(currentUserProvider)?.clinicId;
  if (clinicId == null) return 0;
  return ref.watch(pendingRequestsProvider(clinicId)).value?.length ?? 0;
});
