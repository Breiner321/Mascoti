import 'dart:convert';

import 'package:http/http.dart' as http;

import 'address_search_service.dart';
import 'place_address.dart';

/// Direcciones con OpenStreetMap a través de Photon (photon.komoot.io), que
/// permite búsqueda mientras se escribe y devuelve las coordenadas con cada
/// resultado. No necesita API key ni cuenta de facturación.
///
/// Uso justo: Photon público es gratuito con límites razonables. Si la app
/// crece, se cambia [baseUrl] por una instancia propia o un proveedor pago
/// sin tocar las pantallas. Los datos son © colaboradores de OpenStreetMap
/// (la UI muestra la atribución).
class OsmAddressService implements AddressSearchService {
  OsmAddressService(
    this._client, {
    this.baseUrl = 'https://photon.komoot.io/api/',
  });

  final http.Client _client;
  final String baseUrl;

  /// Mascoti opera solo en Colombia: caja aproximada del país
  /// (oeste, sur, este, norte) y filtro por código de país.
  static const _colombiaBbox = '-79.1,-4.3,-66.8,13.5';
  static const _timeout = Duration(seconds: 10);
  static const _headers = {'User-Agent': 'Mascoti/0.1 (app veterinaria)'};

  @override
  Future<List<AddressSuggestion>> suggest(
    String query, {
    bool newSession = false,
  }) async {
    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      'q': query,
      'limit': '6',
      'bbox': _colombiaBbox,
    });
    final response = await _client.get(uri, headers: _headers).timeout(_timeout);
    if (response.statusCode == 429 || response.statusCode >= 500) {
      throw AddressSearchUnavailable('HTTP ${response.statusCode}');
    }
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final features = (body['features'] as List?) ?? const [];
    final seen = <String>{};
    final suggestions = <AddressSuggestion>[];
    for (final f in features.cast<Map<String, dynamic>>()) {
      final suggestion = _toSuggestion(f);
      if (suggestion != null && seen.add(suggestion.fullText)) {
        suggestions.add(suggestion);
      }
    }
    return suggestions;
  }

  /// Las sugerencias de OSM ya traen coordenadas: no hay segunda llamada.
  @override
  Future<PlaceAddress?> resolve(AddressSuggestion suggestion) async {
    final lat = suggestion.lat, lng = suggestion.lng;
    if (lat == null || lng == null) return null;
    return PlaceAddress(direccion: suggestion.fullText, lat: lat, lng: lng);
  }

  static AddressSuggestion? _toSuggestion(Map<String, dynamic> feature) {
    final props = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (props['countrycode'] != null && props['countrycode'] != 'CO') return null;

    final coords = ((feature['geometry'] as Map?)?['coordinates'] as List?) ?? const [];
    final lng = coords.isNotEmpty ? (coords[0] as num?)?.toDouble() : null;
    final lat = coords.length > 1 ? (coords[1] as num?)?.toDouble() : null;

    String? text(String key) {
      final value = (props[key] as String?)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final street = [text('street'), text('housenumber')].whereType<String>().join(' # ');
    final name = text('name');
    final primary = name ?? (street.isEmpty ? null : street);
    if (primary == null) return null;

    final secondary = <String?>[
      if (name != null && street.isNotEmpty) street,
      text('locality'),
      text('city'),
    ].whereType<String>().where((part) => part != primary).toSet().join(', ');

    return AddressSuggestion(
      placeId: '${props['osm_type'] ?? ''}${props['osm_id'] ?? ''}',
      primaryText: primary,
      secondaryText: secondary,
      lat: lat,
      lng: lng,
    );
  }
}
