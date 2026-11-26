import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/pet.dart';
import '../../../../core/format/bogota_time.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/health_card_repository.dart';
import '../date_label.dart';
import '../health_card_providers.dart';
import '../pets_providers.dart';

/// Tarjeta "Carnet de vacunas" de la pestaña Documentos (RF-18): genera el
/// PDF en el servidor, lo abre en el visor del teléfono y lo comparte.
class HealthCardPdfCard extends ConsumerStatefulWidget {
  const HealthCardPdfCard({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<HealthCardPdfCard> createState() => _HealthCardPdfCardState();
}

class _HealthCardPdfCardState extends ConsumerState<HealthCardPdfCard> {
  /// El enlace firmado dura 15 min; pasado este tiempo se genera de nuevo.
  static const _linkLifetime = Duration(minutes: 14);

  bool _sharing = false;

  Pet get pet => widget.pet;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  bool _expired(GeneratedHealthCard card) =>
      DateTime.now().difference(card.generadoEn) > _linkLifetime;

  void _generate() => ref.read(healthCardControllerProvider(pet.id).notifier).generate();

  Future<void> _open(GeneratedHealthCard card) async {
    if (_expired(card)) return _generate();
    var opened = false;
    try {
      opened = await ref.read(externalUrlOpenerProvider)(Uri.parse(card.url));
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) _snack('No se pudo abrir el PDF. Intenta de nuevo.');
  }

  Future<void> _share(GeneratedHealthCard card) async {
    if (_expired(card)) return _generate();
    setState(() => _sharing = true);
    try {
      final bytes = await ref.read(healthCardRepositoryProvider).download(card.url);
      await ref.read(healthCardSharerProvider)(bytes, healthCardFileName(pet.nombre, card.generadoEn));
    } on HealthCardFailure catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('No se pudo compartir el carnet. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(healthCardControllerProvider(pet.id));
    final latest = ref.watch(latestHealthCardProvider(pet.id));

    // Recién generado: se abre en el visor de PDF del teléfono.
    ref.listen(healthCardControllerProvider(pet.id), (previous, next) {
      if (previous is HealthCardGenerating && next is HealthCardReady) _open(next.card);
    });

    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.vaccines_outlined, color: AppColors.primary, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Carnet de vacunas',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Todas las vacunas de ${pet.nombre} en un PDF para llevar a la clínica '
              'o compartir por WhatsApp o correo.',
              style: textTheme.bodyMedium,
            ),
            if (latest.value case final HealthCardInfo info) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.history, size: 20, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Último carnet: ${dateLabel(context, BogotaTime.wallClock(info.generadoAt))}',
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            switch (state) {
              HealthCardIdle() => FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generar carnet PDF'),
                ),
              HealthCardGenerating() => Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Generando tu carnet…', style: textTheme.bodyMedium)),
                    ],
                  ),
                ),
              HealthCardReady(:final card) => _ready(card, textTheme),
              HealthCardError(:final message) => _error(message, textTheme),
            },
          ],
        ),
      ),
    );
  }

  Widget _ready(GeneratedHealthCard card, TextTheme textTheme) {
    final vaccines = switch (card.vacunas) {
      0 => 'sin vacunas registradas',
      1 => '1 vacuna',
      final n => '$n vacunas',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: AppColors.success, size: 22),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Carnet listo · $vaccines',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('El enlace vence en 15 minutos.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _open(card),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Abrir PDF'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _sharing ? null : () => _share(card),
          icon: _sharing
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share_outlined),
          label: Text(_sharing ? 'Preparando…' : 'Compartir'),
        ),
        TextButton(onPressed: _generate, child: const Text('Generar de nuevo')),
      ],
    );
  }

  Widget _error(String message, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: AppColors.sosText, size: 22),
              const SizedBox(width: 6),
              Expanded(
                child: Text(message, style: textTheme.bodyMedium?.copyWith(color: AppColors.sosText)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}
