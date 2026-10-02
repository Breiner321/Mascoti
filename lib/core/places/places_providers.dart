import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import 'address_search_service.dart';
import 'google_places_address_service.dart';

final addressSearchServiceProvider = Provider<AddressSearchService>(
  (ref) => GooglePlacesAddressService(Env.mapsApiKey),
);
