import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Descarga un archivo (adjunto del historial, para reenviarlo al chat).
/// Se reemplaza en las pruebas.
typedef FileDownloader = Future<Uint8List> Function(Uri url);

Future<Uint8List> downloadWithHttp(Uri url) async {
  final response = await http.get(url).timeout(const Duration(seconds: 60));
  if (response.statusCode != 200) {
    throw http.ClientException('HTTP ${response.statusCode}', url);
  }
  return response.bodyBytes;
}
