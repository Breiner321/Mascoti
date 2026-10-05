import 'package:flutter/widgets.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';

import 'address_search_service.dart';
import 'place_address.dart';

/// Implementación con el SDK nativo de Places (API nueva). Al ser nativo, la
/// API key puede restringirse al paquete co.mascoti.mascoti + SHA-1.
class GooglePlacesAddressService implements AddressSearchService {
  GooglePlacesAddressService(String apiKey)
      : _places = apiKey.isEmpty
            ? null
            : FlutterGooglePlacesSdk(
                apiKey,
                locale: const Locale('es', 'CO'),
                useNewApi: true,
              );

  final FlutterGooglePlacesSdk? _places;

  /// Mascoti opera solo en Colombia.
  static const _countries = ['co'];

  FlutterGooglePlacesSdk get _sdk => _places ?? (throw const AddressSearchUnavailable());

  @override
  Future<List<AddressSuggestion>> suggest(
    String query, {
    bool newSession = false,
  }) async {
    final response = await _sdk.findAutocompletePredictions(
      query,
      countries: _countries,
      newSessionToken: newSession,
    );
    return [
      for (final p in response.predictions)
        AddressSuggestion(
          placeId: p.placeId,
          primaryText: p.primaryText,
          secondaryText: p.secondaryText,
        ),
    ];
  }

  @override
  Future<PlaceAddress?> resolve(AddressSuggestion suggestion) async {
    // Solo se pide la ubicación: es el campo más barato que da lat/lng.
    final response = await _sdk.fetchPlace(
      suggestion.placeId,
      fields: const [PlaceField.Location],
    );
    final latLng = response.place?.latLng;
    if (latLng == null) return null;
    return PlaceAddress(
      direccion: suggestion.fullText,
      lat: latLng.lat,
      lng: latLng.lng,
    );
  }
}
