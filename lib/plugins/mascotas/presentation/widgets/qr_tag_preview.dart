import 'package:flutter/material.dart';

import '../../../../core/domain/pet.dart';
import '../../../../core/domain/qr_tag.dart';
import '../../../../core/theme/app_theme.dart';
import 'pet_avatar.dart';

/// Vista previa de lo que verá quien escanee la placa (misma información
/// que devuelve la Edge Function `placa-publica`).
class QrTagPreview extends StatelessWidget {
  const QrTagPreview({
    super.key,
    required this.pet,
    required this.display,
    required this.ownerName,
    required this.ownerPhone,
  });

  final Pet pet;
  final QrTagDisplay display;
  final String ownerName;
  final String? ownerPhone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final phone = ownerPhone?.trim() ?? '';
    final mensaje = display.mensaje.trim();

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: value),
                ])),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Esto verá quien escanee la placa',
              style: textTheme.labelLarge?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 10),
          Row(
            children: [
              PetAvatar(photoPath: pet.fotoPath, name: pet.nombre, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pet.nombre,
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(pet.especie.label, style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          if (mensaje.isNotEmpty) row(Icons.chat_bubble_outline, 'Mensaje', mensaje),
          if (display.alergias)
            row(
              Icons.health_and_safety_outlined,
              'Alergias',
              pet.alergias.isEmpty ? 'Sin alergias registradas' : pet.alergias.join(', '),
            ),
          if (display.nombreDueno) row(Icons.person_outline, 'Dueño', ownerName),
          if (display.telefono && phone.isNotEmpty)
            row(Icons.phone_outlined, 'Teléfono', '${maskPhone(phone)} (se ve al pulsar "Ver teléfono")'),
        ],
      ),
    );
  }
}
