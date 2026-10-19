import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mascoti/core/places/address_search_service.dart';
import 'package:mascoti/core/places/google_places_service.dart';
import 'package:mascoti/core/places/place_address.dart';

void main() {
  final requests = <http.Request>[];

  GooglePlacesService service(http.Response Function(http.Request) handler) {
    requests.clear();
    return GooglePlacesService(
      MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
      apiKey: 'clave-prueba',
    );
  }

  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  test('autocompletado: sugerencias en español limitadas a Colombia', () async {
    final places = service((_) => json({
          'suggestions': [
            {
              'placePrediction': {
                'placeId': 'abc',
                'structuredFormat': {
                  'mainText': {'text': 'Medellín'},
                  'secondaryText': {'text': 'Antioquia, Colombia'},
                },
              },
            },
            {'queryPrediction': {}},
          ],
        }));

    final result = await places.suggest('Medel', newSession: true);

    expect(result.single.placeId, 'abc');
    expect(result.single.fullText, 'Medellín, Antioquia, Colombia');
    final request = requests.single;
    expect(request.headers['X-Goog-Api-Key'], 'clave-prueba');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['input'], 'Medel');
    expect(body['languageCode'], 'es');
    expect(body['includedRegionCodes'], ['co']);
    expect(body['sessionToken'], isNotEmpty);
  });

  test('el detalle da las coordenadas y usa la misma sesión', () async {
    final places = service((request) => request.url.path.endsWith(':autocomplete')
        ? json({'suggestions': []})
        : json({
            'formattedAddress': 'Medellín, Antioquia, Colombia',
            'location': {'latitude': 6.2442, 'longitude': -75.5812},
          }));

    await places.suggest('Medel', newSession: true);
    final token = (jsonDecode(requests.single.body) as Map)['sessionToken'];
    final place = await places.resolve(const AddressSuggestion(
      placeId: 'abc',
      primaryText: 'Medellín',
      secondaryText: '',
    ));

    expect(place, isA<PlaceAddress>());
    expect(place!.lat, 6.2442);
    expect(place.lng, -75.5812);
    final detail = requests.last;
    expect(detail.url.path, '/v1/places/abc');
    expect(detail.url.queryParameters['sessionToken'], token);
    expect(detail.headers['X-Goog-FieldMask'], 'location,formattedAddress');
  });

  test('key inválida o sin cuota: el buscador avisa que no está disponible', () {
    final places = service((_) => json({'error': {}}, 403));
    expect(places.suggest('Bogotá'), throwsA(isA<AddressSearchUnavailable>()));
  });
}
