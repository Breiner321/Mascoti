import 'package:mascoti/core/places/address_search_service.dart';
import 'package:mascoti/core/places/place_address.dart';

const bogotaSuggestion = AddressSuggestion(
  placeId: 'p1',
  primaryText: 'Calle 100 # 15-20',
  secondaryText: 'Bogotá, Colombia',
);

const bogotaAddress = PlaceAddress(
  direccion: 'Calle 100 # 15-20, Bogotá, Colombia',
  lat: 4.6867,
  lng: -74.0486,
);

/// Buscador de direcciones en memoria para las pruebas.
class FakeAddressSearch implements AddressSearchService {
  FakeAddressSearch({
    this.suggestions = const [bogotaSuggestion],
    this.resolved = bogotaAddress,
    this.error,
  });

  List<AddressSuggestion> suggestions;
  PlaceAddress? resolved;
  Object? error;
  final queries = <String>[];

  @override
  Future<List<AddressSuggestion>> suggest(
    String query, {
    bool newSession = false,
  }) async {
    queries.add(query);
    final e = error;
    if (e != null) throw e;
    return suggestions;
  }

  @override
  Future<PlaceAddress?> resolve(AddressSuggestion suggestion) async => resolved;
}
