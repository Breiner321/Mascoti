import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/medical_record.dart';
import '../supabase/supabase_providers.dart';
import 'medical_records_repository.dart';

final medicalRecordsRepositoryProvider = Provider<MedicalRecordsRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return MedicalRecordsRepository(
    functions: supabase?.functions,
    storage: supabase?.storage,
  );
});

/// Timeline de una mascota (RF-08), en tiempo real.
final medicalRecordsProvider =
    StreamProvider.autoDispose.family<List<MedicalRecord>, String>(
  (ref, petId) => ref.watch(medicalRecordsRepositoryProvider).watchRecords(petId),
  retry: (_, __) => null,
);
