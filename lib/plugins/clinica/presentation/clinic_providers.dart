import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/clinic.dart';
import '../../../core/domain/clinic_service.dart';
import '../../../core/domain/pet.dart';
import '../../../core/domain/slot.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/storage/storage_repository.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../clinica_routes.dart';
import '../data/attachment_picker.dart';
import '../data/clinic_repository.dart';
import '../data/patients_repository.dart';
import '../data/pet_link_api.dart';
import '../data/services_repository.dart';
import '../data/slots_repository.dart';
import '../domain/patient.dart';

final clinicRepositoryProvider = Provider<ClinicRepository>(
  (ref) => ClinicRepository(),
);

/// La clínica `clinicId` en tiempo real (RF-04).
final clinicProvider = StreamProvider.autoDispose.family<Clinic?, String>(
  (ref, clinicId) => ref.watch(clinicRepositoryProvider).watchClinic(clinicId),
);

final servicesRepositoryProvider = Provider<ServicesRepository>(
  (ref) => ServicesRepository(),
);

/// Servicios activos de la clínica en tiempo real (RF-05).
final clinicServicesProvider =
    StreamProvider.autoDispose.family<List<ClinicService>, String>(
  (ref, clinicId) => ref.watch(servicesRepositoryProvider).watchActive(clinicId),
);

final slotsRepositoryProvider = Provider<SlotsRepository>(
  (ref) => SlotsRepository(),
);

/// Franjas guardadas de un día, por hora (RF-06).
final daySlotsProvider = StreamProvider.autoDispose
    .family<Map<String, Slot>, ({String clinicId, String fecha})>(
  (ref, key) => ref.watch(slotsRepositoryProvider).watchDay(key.clinicId, key.fecha),
);

/// Fechas del mes con franjas configuradas (puntos del calendario, RF-06).
final configuredDaysProvider = StreamProvider.autoDispose
    .family<Set<String>, ({String clinicId, DateTime month})>(
  (ref, key) =>
      ref.watch(slotsRepositoryProvider).watchConfiguredDays(key.clinicId, key.month),
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

/// Reloj de la agenda: decide qué franjas ya pasaron. Se reemplaza en pruebas.
final agendaClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Vinculación de mascotas con su código de paciente (semana 3).
final petLinkApiProvider = Provider<PetLinkApi>(
  (ref) => PetLinkApi(ref.watch(supabaseClientProvider)?.functions),
);

final patientsRepositoryProvider = Provider<PatientsRepository>(
  (ref) => PatientsRepository(),
);

/// Mascotas que autorizaron a la clínica, en tiempo real.
final authorizedPetsProvider =
    StreamProvider.autoDispose.family<List<Pet>, String>(
  (ref, clinicId) =>
      ref.watch(patientsRepositoryProvider).watchPatients(clinicId),
  retry: (_, __) => null,
);

/// Nombre del dueño de cada paciente (por petId).
final ownerNamesProvider =
    StreamProvider.autoDispose.family<Map<String, String>, String>(
  (ref, clinicId) =>
      ref.watch(patientsRepositoryProvider).watchOwnerNames(clinicId),
  retry: (_, __) => null,
);

/// Lista de pacientes con el nombre del dueño. Si los nombres no cargan, la
/// lista se muestra igual (sin dueño).
final patientsProvider = Provider.autoDispose
    .family<AsyncValue<List<Patient>>, String>((ref, clinicId) {
  final names = ref.watch(ownerNamesProvider(clinicId)).value ?? const {};
  return ref.watch(authorizedPetsProvider(clinicId)).whenData((pets) => [
        for (final pet in pets)
          Patient(pet: pet, duenoNombre: names[pet.id] ?? ''),
      ]);
});

/// Una mascota autorizada; null si no existe o el dueño revocó el acceso.
final patientProvider = StreamProvider.autoDispose.family<Pet?, String>(
  (ref, petId) => ref.watch(patientsRepositoryProvider).watchPatient(petId),
  retry: (_, __) => null,
);

/// Enlace temporal de la foto de una mascota (bucket `mascotas`).
final patientPhotoUrlProvider =
    FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref
      .watch(storageRepositoryProvider)
      .signedUrl(path, bucketId: StorageRepository.petsBucket),
  retry: (_, __) => null,
);

final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => const AttachmentPicker(),
);

/// Reloj de los registros médicos (fecha por defecto y ventana de 24 h).
final recordsClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);
