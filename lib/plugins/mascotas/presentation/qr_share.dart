import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Comparte la imagen PNG de la placa (RF-17 paso 4: imprimir). Es un
/// provider para que las pruebas no abran el menú del sistema.
typedef QrImageSharer = Future<void> Function(Uint8List png, String fileName);

final qrImageSharerProvider = Provider<QrImageSharer>(
  (ref) => (png, fileName) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
      fileNameOverrides: [fileName],
      title: 'Placa QR',
    ));
  },
);

/// PNG en alta resolución del widget dentro de [boundary] (×4: ~1000 px de
/// lado, suficiente para imprimir la placa).
Future<Uint8List> capturePng(RenderRepaintBoundary boundary, {double pixelRatio = 4}) async {
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('No se pudo crear la imagen');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// "placa_luna.png" (sin acentos ni espacios).
String plateFileName(String petName) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunAEIOUUN';
  final buffer = StringBuffer();
  for (final ch in petName.trim().split('')) {
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  final clean = buffer
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'placa_${clean.isEmpty ? 'mascota' : clean}.png';
}
