import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../data/pets_repository.dart';
import '../domain/pet.dart';
import '../mascotas_routes.dart';

final petsRepositoryProvider = Provider<PetsRepository>(
  (ref) => PetsRepository(),
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

/// Paso obligatorio del dueño: el onboarding de 3 pasos, hasta que
/// `users/{uid}.onboardingVisto` sea true. Lo consume el core a través de
/// [MascotasPlugin.requiredStep].
final ownerOnboardingStepProvider =
    Provider.family<AsyncValue<String?>, bool>(
  (ref, onboardingVisto) =>
      AsyncData(onboardingVisto ? null : MascotasRoutes.onboarding),
);
