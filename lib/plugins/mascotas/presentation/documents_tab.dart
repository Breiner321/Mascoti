import 'package:flutter/material.dart';

import '../../../core/domain/pet.dart';
import 'widgets/health_card_pdf_card.dart';
import 'widgets/qr_tag_card.dart';

/// Pestaña "Documentos" de la ficha de la mascota: una tarjeta por documento.
/// - Placa QR (RF-17, Dev A): [QrTagCard].
/// - Carnet de vacunas en PDF (RF-18, Dev C): [HealthCardPdfCard].
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
        HealthCardPdfCard(pet: pet),
      ],
    );
  }
}
