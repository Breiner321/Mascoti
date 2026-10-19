import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'address_search_service.dart';
import 'osm_address_service.dart';

final addressSearchServiceProvider = Provider<AddressSearchService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return OsmAddressService(client);
});
