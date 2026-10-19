import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'address_search_service.dart';
import 'google_places_service.dart';
import 'osm_address_service.dart';

final addressSearchServiceProvider = Provider<AddressSearchService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return OsmAddressService(client);
});

/// Buscador de Google Places para el directorio (RF-09). Si no hay
/// GOOGLE_PLACES_API_KEY en env/dev.json, usa OpenStreetMap para que la
/// búsqueda manual siga funcionando.
final placesSearchServiceProvider = Provider<AddressSearchService>((ref) {
  if (!Env.hasGooglePlaces) return ref.watch(addressSearchServiceProvider);
  final client = http.Client();
  ref.onDispose(client.close);
  return GooglePlacesService(client, apiKey: Env.googlePlacesApiKey);
});
