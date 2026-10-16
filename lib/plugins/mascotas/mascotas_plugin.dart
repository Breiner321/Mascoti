import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import '../../core/router/navigator_keys.dart';
import 'mascotas_routes.dart';
import 'presentation/onboarding_page.dart';
import 'presentation/owner_home_page.dart';
import 'presentation/pet_form_page.dart';
import 'presentation/pet_profile_page.dart';
import 'presentation/pets_providers.dart';

/// Plugin del dueño: home, onboarding, mascotas e historial médico (RF-08).
class MascotasPlugin extends MascotiPlugin {
  const MascotasPlugin();

  @override
  String get id => 'mascotas';

  @override
  Set<UserRole> get roles => const {UserRole.dueno};

  @override
  List<RouteBase> routes() => [
        GoRoute(
          path: MascotasRoutes.home,
          builder: (context, state) => const OwnerHomePage(),
        ),
        // A pantalla completa, sin encabezado ni barra inferior.
        GoRoute(
          path: MascotasRoutes.onboarding,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const OnboardingPage(),
        ),
        GoRoute(
          path: MascotasRoutes.newPet,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const PetFormPage(),
        ),
        GoRoute(
          path: MascotasRoutes.profilePattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              PetProfilePage(petId: state.pathParameters['petId']!),
        ),
        GoRoute(
          path: MascotasRoutes.editPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              PetFormPage(petId: state.pathParameters['petId']!),
        ),
      ];

  @override
  List<PluginDestination> destinations(UserRole role) => const [
        PluginDestination(
          label: 'Principal',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          path: MascotasRoutes.home,
          order: 0,
        ),
      ];

  /// RF-01 paso 14: la primera vez, el dueño pasa por el onboarding.
  @override
  ProviderListenable<AsyncValue<String?>>? requiredStep(AppUser user) =>
      ownerOnboardingStepProvider(user.onboardingVisto);
}
