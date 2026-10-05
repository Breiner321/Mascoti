import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clinica_routes.dart';
import '../data/clinic_repository.dart';

final clinicRepositoryProvider = Provider<ClinicRepository>(
  (ref) => ClinicRepository(),
);

/// RF-01 paso 14: una clínica en estado 'incompleto' debe configurar su
/// perfil de atención (RF-04) antes de usar el panel. Lo consume el core a
/// través de [ClinicaPlugin.requiredStep].
final clinicSetupStepProvider =
    StreamProvider.autoDispose.family<String?, String>(
  (ref, clinicId) => ref
      .watch(clinicRepositoryProvider)
      .watchEstado(clinicId)
      .map((estado) => estado == 'incompleto' ? ClinicaRoutes.setup : null),
  // Si falla, el core deja usar la app; no se reintenta en bucle.
  retry: (_, __) => null,
);
