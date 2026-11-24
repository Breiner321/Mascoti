import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/format/bogota_time.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../data/health_card_repository.dart';
import 'qr_share.dart';

final healthCardRepositoryProvider = Provider<HealthCardRepository>(
  (ref) => HealthCardRepository(functions: ref.watch(supabaseClientProvider)?.functions),
);

/// Último carnet generado de una mascota (fecha que muestra la tarjeta).
final latestHealthCardProvider = StreamProvider.autoDispose.family<HealthCardInfo?, String>(
  (ref, petId) => ref.watch(healthCardRepositoryProvider).watchLatest(petId),
  retry: (_, __) => null,
);

/// Comparte el PDF con el menú del sistema (WhatsApp, correo…). Es un
/// provider para que las pruebas no abran el menú.
typedef HealthCardSharer = Future<void> Function(Uint8List pdf, String fileName);

final healthCardSharerProvider = Provider<HealthCardSharer>(
  (ref) => (pdf, fileName) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(pdf, mimeType: 'application/pdf', name: fileName)],
      fileNameOverrides: [fileName],
      title: 'Carnet de vacunas',
    ));
  },
);

/// "carnet_luna_2026-11-24.pdf" (fecha de Colombia).
String healthCardFileName(String petName, DateTime generatedAt) =>
    'carnet_${fileSlug(petName)}_${BogotaTime.dateKey(generatedAt)}.pdf';

/// Estado de la tarjeta "Carnet de vacunas".
@immutable
sealed class HealthCardState {
  const HealthCardState();
}

class HealthCardIdle extends HealthCardState {
  const HealthCardIdle();
}

class HealthCardGenerating extends HealthCardState {
  const HealthCardGenerating();
}

class HealthCardReady extends HealthCardState {
  const HealthCardReady(this.card);

  final GeneratedHealthCard card;
}

class HealthCardError extends HealthCardState {
  const HealthCardError(this.message);

  final String message;
}

/// Genera el carnet de una mascota: `healthCardControllerProvider(petId)`.
final healthCardControllerProvider =
    NotifierProvider.autoDispose.family<HealthCardController, HealthCardState, String>(
  HealthCardController.new,
);

class HealthCardController extends Notifier<HealthCardState> {
  HealthCardController(this.petId);

  final String petId;

  @override
  HealthCardState build() => const HealthCardIdle();

  Future<void> generate() async {
    if (state is HealthCardGenerating) return;
    state = const HealthCardGenerating();
    final repository = ref.read(healthCardRepositoryProvider);
    try {
      final card = await repository.generate(petId);
      if (ref.mounted) state = HealthCardReady(card);
    } on HealthCardFailure catch (e) {
      if (ref.mounted) state = HealthCardError(e.message);
    } catch (_) {
      if (ref.mounted) state = HealthCardError(HealthCardFailure.generic.message);
    }
  }
}
