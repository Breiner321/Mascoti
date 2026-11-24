import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_palette.dart';

/// Diseño de la placa para imprimir (RF-17 paso 4): QR, nombre de la mascota
/// y la instrucción. Usa SIEMPRE la paleta clara ([AppPalette.light]),
/// también en modo oscuro: un QR claro sobre fondo oscuro se lee mal y la
/// imagen compartida se imprime en papel blanco.
class QrPlate extends StatelessWidget {
  const QrPlate({super.key, required this.url, required this.petName, this.size = 220});

  final String url;
  final String petName;

  /// Lado del código QR.
  final double size;

  static const _palette = AppPalette.light;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _palette.primary, width: 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: url,
            size: size,
            backgroundColor: _palette.surface,
            padding: EdgeInsets.zero,
            // El lector de pantalla lo describe la tarjeta (no "qr code").
            semanticsLabel: '',
            eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: _palette.textPrimary),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: _palette.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          // Fuera del MediaQuery del sistema: la imagen impresa no cambia
          // con el tamaño de letra del teléfono.
          MediaQuery.withNoTextScaling(
            child: Column(
              children: [
                Text(
                  petName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _palette.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Si me encuentras, escanéame 🐾',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _palette.textPrimary, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
