import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/clinic_phone_repository.dart';

final clinicPhoneRepositoryProvider = Provider<ClinicPhoneRepository>(
  (ref) => ClinicPhoneRepository(),
);

/// Teléfono de la clínica (botón "Llamar" del dueño); null si no tiene.
final clinicPhoneProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, clinicId) => ref.watch(clinicPhoneRepositoryProvider).fetchPhone(clinicId),
  retry: (_, __) => null,
);

/// Hora actual (separadores "Hoy"/"Ayer", "escribiendo…"). Se reemplaza en
/// las pruebas.
final chatClockProvider = Provider<DateTime Function()>((ref) => () => DateTime.now().toUtc());

/// Si el servidor no confirma un mensaje en este tiempo, se avisa que no hay
/// conexión (el mensaje sigue en la cola y se envía solo al volver la red).
final offlineNoticeDelayProvider = Provider<Duration>((ref) => const Duration(seconds: 3));
