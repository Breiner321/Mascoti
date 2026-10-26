import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/domain/clinic.dart';
import '../../../../core/domain/clinic_service.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/domain/slot.dart';
import '../../data/dueno/booking_repository.dart';

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => BookingRepository());

/// Hora actual; se reemplaza en las pruebas (regla de las 2 horas).
final bookingClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Abre "Llamar" (tel:) y "Cómo llegar" (geo:/https) fuera de la app.
final bookingUrlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

final bookingClinicProvider = StreamProvider.autoDispose.family<Clinic?, String>(
  (ref, clinicId) => ref.watch(bookingRepositoryProvider).watchClinic(clinicId),
  retry: (_, __) => null,
);

final bookingServicesProvider =
    StreamProvider.autoDispose.family<List<ClinicService>, String>(
  (ref, clinicId) => ref.watch(bookingRepositoryProvider).watchActiveServices(clinicId),
  retry: (_, __) => null,
);

/// Franjas de un mes de la clínica, en tiempo real: si otro dueño toma una,
/// desaparece de las horas disponibles.
final monthSlotsProvider = StreamProvider.autoDispose
    .family<List<Slot>, ({String clinicId, int year, int month})>(
  (ref, q) =>
      ref.watch(bookingRepositoryProvider).watchMonthSlots(q.clinicId, q.year, q.month),
  retry: (_, __) => null,
);

/// Mascotas del dueño con sesión.
final ownerPetsProvider = StreamProvider.autoDispose<List<Pet>>(
  (ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return Stream.value(const []);
    return ref.watch(bookingRepositoryProvider).watchPets(user.uid);
  },
  retry: (_, __) => null,
);
