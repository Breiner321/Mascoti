import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'address_search_service.dart';
import 'place_address.dart';

/// Direcciones y ciudades con Google Places API (New): autocompletado y
/// detalle del lugar para obtener sus coordenadas. La usa el directorio
/// (RF-09) cuando el dueño no da permiso de ubicación.
///
/// Cobra por sesión: desde la primera letra hasta escoger un lugar se manda
/// el mismo `sessionToken`. La key va en env/dev.json
/// (`GOOGLE_PLACES_API_KEY`), restringida a Places API (New).
class GooglePlacesService implements AddressSearchService {
  GooglePlacesService(this._client, {required this.apiKey, Random? random})
      : _random = random ?? Random.secure();

  final http.Client _client;
  final String apiKey;
  final Random _random;

  static const attribution = 'Resultados de Google';
  static const _timeout = Duration(seconds: 10);
  static final _autocomplete = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');

  String? _sessionToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
      };

  String _newToken() =>
      List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join();

  @override
  Future<List<AddressSuggestion>> suggest(String query, {bool newSession = false}) async {
    if (newSession || _sessionToken == null) _sessionToken = _newToken();
    final response = await _client
        .post(
          _autocomplete,
          headers: _headers,
          body: jsonEncode({
            'input': query,
            'languageCode': 'es',
            // Mascoti opera solo en Colombia.
            'includedRegionCodes': ['co'],
            'sessionToken': _sessionToken,
          }),
        )
        .timeout(_timeout);
    _check(response);

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final suggestions = <AddressSuggestion>[];
    for (final s in ((body['suggestions'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final prediction = s['placePrediction'];
      if (prediction is! Map) continue;
      final format = prediction['structuredFormat'] as Map? ?? const {};
      final main = (format['mainText'] as Map?)?['text'] as String? ??
          (prediction['text'] as Map?)?['text'] as String? ??
          '';
      if (main.isEmpty) continue;
      suggestions.add(AddressSuggestion(
        placeId: prediction['placeId'] as String? ?? '',
        primaryText: main,
        secondaryText: (format['secondaryText'] as Map?)?['text'] as String? ?? '',
      ));
    }
    return suggestions;
  }

  @override
  Future<PlaceAddress?> resolve(AddressSuggestion suggestion) async {
    final uri = Uri.parse('https://places.googleapis.com/v1/places/${suggestion.placeId}')
        .replace(queryParameters: {
      'languageCode': 'es',
      if (_sessionToken != null) 'sessionToken': _sessionToken!,
    });
    final response = await _client
        .get(uri, headers: {..._headers, 'X-Goog-FieldMask': 'location,formattedAddress'})
        .timeout(_timeout);
    // El detalle cierra la sesión de facturación.
    _sessionToken = null;
    _check(response);

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final location = body['location'];
    if (location is! Map) return null;
    final lat = (location['latitude'] as num?)?.toDouble();
    final lng = (location['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return PlaceAddress(
      direccion: body['formattedAddress'] as String? ?? suggestion.fullText,
      lat: lat,
      lng: lng,
    );
  }

  static void _check(http.Response response) {
    final code = response.statusCode;
    if (code == 200) return;
    // 403: key inválida o sin Places API habilitada; 429: cuota.
    if (code == 403 || code == 429 || code >= 500) {
      throw AddressSearchUnavailable('Google Places HTTP $code');
    }
    throw http.ClientException('Google Places HTTP $code');
  }
}
