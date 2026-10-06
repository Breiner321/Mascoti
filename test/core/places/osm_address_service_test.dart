import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mascoti/core/places/address_search_service.dart';
import 'package:mascoti/core/places/osm_address_service.dart';
import 'package:mascoti/core/places/place_address.dart';

/// Respuesta real de Photon (recortada) para "Calle 100 Bogota".
const _photon = {
  'features': [
    {
      'geometry': {'coordinates': [-74.0754922, 4.6947519]},
      'properties': {
        'osm_type': 'W',
        'osm_id': 40617690,
        'name': 'Calle 100',
        'locality': 'Santa Rosa',
        'city': 'Bogotá',
        'countrycode': 'CO',
      },
    },
    {
      'geometry': {'coordinates': [-74.0563304, 4.6857128]},
      'properties': {
        'osm_type': 'N',
        'osm_id': 14077940901,
        'name': 'Mercure Bogotá Calle 100',
        'street': 'Transversal 23',
        'housenumber': '98-27',
        'locality': 'Chicó Lago',
        'city': 'Bogotá',
        'countrycode': 'CO',
      },
    },
    {
      'geometry': {'coordinates': [-79.5, 9.0]},
      'properties': {'name': 'Calle 100', 'city': 'Panamá', 'countrycode': 'PA'},
    },
  ],
};

void main() {
  late Uri requested;

  OsmAddressService serviceReturning(int status, [Object? body]) =>
      OsmAddressService(MockClient((request) async {
        requested = request.url;
        return http.Response.bytes(
          utf8.encode(jsonEncode(body ?? _photon)),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));

  test('convierte los resultados de Photon y descarta otros países', () async {
    final suggestions = await serviceReturning(200).suggest('Calle 100 Bogota');

    expect(requested.queryParameters['q'], 'Calle 100 Bogota');
    expect(requested.queryParameters['bbox'], isNotEmpty);
    expect(suggestions, hasLength(2));

    expect(suggestions[0].primaryText, 'Calle 100');
    expect(suggestions[0].secondaryText, 'Santa Rosa, Bogotá');
    expect(suggestions[0].lat, 4.6947519);
    expect(suggestions[0].lng, -74.0754922);

    expect(suggestions[1].primaryText, 'Mercure Bogotá Calle 100');
    expect(suggestions[1].secondaryText, 'Transversal 23 # 98-27, Chicó Lago, Bogotá');
  });

  test('resolve usa las coordenadas de la sugerencia sin otra llamada', () async {
    final service = serviceReturning(200);
    final suggestion = (await service.suggest('Calle 100')).first;

    final address = await service.resolve(suggestion);
    expect(address?.direccion, 'Calle 100, Santa Rosa, Bogotá');
    expect(address?.lat, 4.6947519);
  });

  test('una sugerencia sin coordenadas no se puede geocodificar', () async {
    const noCoords = AddressSuggestion(
      placeId: 'x',
      primaryText: 'Sin coordenadas',
      secondaryText: '',
    );
    expect(await serviceReturning(200).resolve(noCoords), isNull);
  });

  test('servicio caído o limitando el uso → AddressSearchUnavailable', () async {
    await expectLater(
      serviceReturning(429, {}).suggest('Calle 100'),
      throwsA(isA<AddressSearchUnavailable>()),
    );
    await expectLater(
      serviceReturning(503, {}).suggest('Calle 100'),
      throwsA(isA<AddressSearchUnavailable>()),
    );
  });

  test('sin resultados devuelve una lista vacía', () async {
    expect(await serviceReturning(200, {'features': []}).suggest('zzzz'), isEmpty);
  });
}
