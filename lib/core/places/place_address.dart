import 'package:flutter/foundation.dart';

/// Sugerencia del autocompletado de direcciones.
@immutable
class AddressSuggestion {
  const AddressSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;

  String get fullText =>
      secondaryText.isEmpty ? primaryText : '$primaryText, $secondaryText';
}

/// Dirección elegida de la lista y geocodificada (RF-01, paso 10).
@immutable
class PlaceAddress {
  const PlaceAddress({
    required this.direccion,
    required this.lat,
    required this.lng,
  });

  final String direccion;
  final double lat;
  final double lng;
}
