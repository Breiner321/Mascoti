import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/vet_place.dart';
import '../supabase/supabase_providers.dart';
import 'vet_places_repository.dart';

final vetPlacesRepositoryProvider = Provider<VetPlacesRepository>(
  (ref) => VetPlacesRepository(functions: ref.watch(supabaseClientProvider)?.functions),
);

/// Veterinarias de OpenStreetMap (no aliadas) del área [MapArea] (Cambio 4).
/// Lo usan el mapa del directorio y el SOS. Se guarda un minuto después de
/// dejar de usarse: volver a una zona vista no repite la consulta.
final nearbyVetPlacesProvider =
    FutureProvider.autoDispose.family<List<VetPlace>, MapArea>(
  (ref, area) async {
    final link = ref.keepAlive();
    final timer = Future.delayed(const Duration(minutes: 1));
    ref.onCancel(() => timer.then((_) => link.close()));
    return ref.watch(vetPlacesRepositoryProvider).fetchIn(area);
  },
  retry: (_, __) => null,
);
