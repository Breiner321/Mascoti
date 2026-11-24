import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/config/public_links.dart';
import '../../../../core/data/qr_tags_providers.dart';
import '../../../../core/domain/pet.dart';
import '../../../../core/domain/qr_tag.dart';
import '../../../../core/theme/app_theme.dart';
import '../../mascotas_routes.dart';
import '../qr_share.dart';
import 'qr_plate.dart';
import 'qr_tag_form_sheet.dart';

/// Tarjeta "Placa QR" de la pestaña Documentos (RF-17): crear la placa,
/// ver el código, compartir la imagen para imprimir y desactivarla.
class QrTagCard extends ConsumerStatefulWidget {
  const QrTagCard({super.key, required this.pet});

  final Pet pet;

  @override
  ConsumerState<QrTagCard> createState() => _QrTagCardState();
}

class _QrTagCardState extends ConsumerState<QrTagCard> {
  final _plateKey = GlobalKey();
  bool _busy = false;

  Pet get pet => widget.pet;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Ejecuta [action] mostrando el progreso y un error en español si falla.
  Future<void> _run(Future<void> Function() action, {required String done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _snack(done);
    } catch (_) {
      if (mounted) _snack('No se pudo guardar. Verifica tu conexión e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final display = await showQrTagForm(
      context,
      pet: pet,
      ownerName: user.nombreVisible,
      ownerPhone: user.telefono,
      submitLabel: 'Crear placa QR',
    );
    if (display == null) return;
    await _run(
      () => ref
          .read(qrTagsRepositoryProvider)
          .create(ownerUid: user.uid, petId: pet.id, mostrar: display),
      done: 'Placa QR creada',
    );
  }

  Future<void> _edit(QrTag tag) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final display = await showQrTagForm(
      context,
      pet: pet,
      ownerName: user.nombreVisible,
      ownerPhone: user.telefono,
      initial: tag.mostrar,
      submitLabel: 'Guardar cambios',
    );
    if (display == null) return;
    await _run(() => ref.read(qrTagsRepositoryProvider).updateDisplay(tag.id, display),
        done: 'Cambios guardados');
  }

  Future<void> _deactivate(QrTag tag) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desactivar la placa?'),
        content: Text(
          'Quien escanee la placa de ${pet.nombre} verá "Esta placa no está activa". '
          'Úsalo si la placa se perdió. Puedes volver a activarla después.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desactivar placa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(qrTagsRepositoryProvider).setActive(tag.id, false),
        done: 'Placa desactivada');
  }

  Future<void> _share() async {
    final boundary = _plateKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    setState(() => _busy = true);
    try {
      final png = await capturePng(boundary);
      await ref.read(qrImageSharerProvider)(png, plateFileName(pet.nombre));
    } catch (_) {
      if (mounted) _snack('No se pudo compartir la imagen. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final textTheme = Theme.of(context).textTheme;
    final tag = user == null
        ? const AsyncValue<QrTag?>.data(null)
        : ref.watch(petQrTagProvider((ownerUid: user.uid, petId: pet.id)));

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
                Icon(Icons.qr_code_2, color: AppColors.primary, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Placa QR',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (tag.value case final QrTag t) _StatusChip(active: t.activo),
              ],
            ),
            const SizedBox(height: 8),
            switch (tag) {
              AsyncData(value: null) => _empty(textTheme),
              AsyncData(value: final QrTag t) => _withTag(t, textTheme),
              AsyncError() => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('No pudimos cargar la placa. Verifica tu conexión.'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(petQrTagProvider),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              _ => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            },
          ],
        ),
      ),
    );
  }

  Widget _empty(TextTheme textTheme) {
    final hasPhoto = pet.fotoPath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Si ${pet.nombre} se pierde, quien encuentre la placa podrá escanearla y contactarte. '
          'Tú eliges qué datos se ven.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (!hasPhoto) ...[
          Text('Para crear la placa, agrega primero una foto de ${pet.nombre}.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(MascotasRoutes.edit(pet.id)),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Agregar foto'),
          ),
        ] else
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Crear placa QR'),
          ),
      ],
    );
  }

  Widget _withTag(QrTag tag, TextTheme textTheme) {
    final url = PublicLinks.qrTag(tag.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!tag.activo)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Quien escanee esta placa verá "Esta placa no está activa".',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ),
        Center(
          child: Semantics(
            image: true,
            label: 'Código QR de la placa de ${pet.nombre}. Al escanearlo se abre su ficha pública.',
            excludeSemantics: true,
            child: Opacity(
              opacity: tag.activo ? 1 : 0.4,
              child: RepaintBoundary(
                key: _plateKey,
                child: LayoutBuilder(
                  builder: (context, c) => QrPlate(
                    url: url,
                    petName: pet.nombre,
                    size: (c.maxWidth - 40).clamp(120, 220).toDouble(),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (tag.activo) ...[
          FilledButton.icon(
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartir imagen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _edit(tag),
            icon: const Icon(Icons.tune),
            label: const Text('Qué se muestra'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : () => _deactivate(tag),
            icon: Icon(Icons.block, color: AppColors.sosText),
            label: Text('Desactivar placa', style: TextStyle(color: AppColors.sosText)),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() => ref.read(qrTagsRepositoryProvider).setActive(tag.id, true),
                    done: 'Placa activada'),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Volver a activar'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || pet.fotoPath == null ? null : _create,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Crear una placa nueva'),
          ),
        ],
      ],
    );
  }
}

/// "Activa" / "Desactivada" con ícono además del color (Cambio 3).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.textMuted;
    return Semantics(
      label: active ? 'Estado: Activa' : 'Estado: Desactivada',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.check_circle : Icons.block, size: 16, color: color),
            const SizedBox(width: 4),
            Text(active ? 'Activa' : 'Desactivada',
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
