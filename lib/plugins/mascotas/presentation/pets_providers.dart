import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/domain/pet.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/storage/storage_repository.dart';
import '../data/pet_photo_service.dart';
import '../data/pets_repository.dart';
import '../mascotas_routes.dart';

final petsRepositoryProvider = Provider<PetsRepository>(
  (ref) => PetsRepository(storage: ref.watch(storageRepositoryProvider)),
);

final petPhotoPickerProvider = Provider<PetPhotoPicker>(
  (ref) => DevicePetPhotoPicker(),
);

/// Mascotas del dueño con sesión. autoDispose: al cerrar sesión se cancela
/// el listener (RF-03). Sin reintento automático, para que la UI muestre el
/// error con "Reintentar".
final myPetsProvider = StreamProvider.autoDispose<List<Pet>>(
  (ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Stream.empty();
    return ref.watch(petsRepositoryProvider).watchPets(user.uid);
  },
  retry: (_, __) => null,
);

/// Una mascota por id (perfil y edición); null si no existe.
final petProvider = StreamProvider.autoDispose.family<Pet?, String>(
  (ref, petId) => ref.watch(petsRepositoryProvider).watchPet(petId),
  retry: (_, __) => null,
);

/// Mascota que el dueño eligió en el home. null = la más reciente.
final selectedPetIdProvider = NotifierProvider<SelectedPetId, String?>(
  SelectedPetId.new,
);

class SelectedPetId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String petId) => state = petId;
}

/// Paso obligatorio del dueño: el onboarding de 3 pasos, hasta que
/// `users/{uid}.onboardingVisto` sea true. Lo consume el core a través de
/// [MascotasPlugin.requiredStep].
final ownerOnboardingStepProvider =
    Provider.family<AsyncValue<String?>, bool>(
  (ref, onboardingVisto) =>
      AsyncData(onboardingVisto ? null : MascotasRoutes.onboarding),
);

/// Enlace temporal (1 h) para mostrar la foto de una mascota guardada en
/// Supabase Storage. Se cachea mientras la pantalla lo use.
final petPhotoUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref
      .watch(storageRepositoryProvider)
      .signedUrl(path, bucketId: StorageRepository.petsBucket),
  retry: (_, __) => null,
);
