import 'package:flutter/material.dart';

import '../../../core/domain/pet.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/qr_tag_card.dart';

/// Pestaña "Documentos" de la ficha de la mascota: una tarjeta por documento.
/// - Placa QR (RF-17, Dev A): [QrTagCard].
/// - Carnet de vacunas en PDF (RF-18, Dev C): reemplazar
///   [_HealthCardPlaceholder] por la tarjeta real, en la misma lista.
class DocumentsTab extends StatelessWidget {
  const DocumentsTab({super.key, required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        QrTagCard(pet: pet),
        const SizedBox(height: 16),
        const _HealthCardPlaceholder(),
      ],
    );
  }
}

/// Lugar de la tarjeta del carnet PDF (RF-18) hasta que el Dev C la construya.
class _HealthCardPlaceholder extends StatelessWidget {
  const _HealthCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.description_outlined, color: AppColors.primary, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Carnet de vacunas (PDF)',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('Próximamente', style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
