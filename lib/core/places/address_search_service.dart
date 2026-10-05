import 'place_address.dart';

/// Buscador de direcciones (Google Places). Lo usan el registro de la clínica
/// (RF-01) y, más adelante, el perfil de la clínica (RF-04) y la dirección de
/// entrega (RF-12). Se reemplaza con un override en las pruebas.
abstract interface class AddressSearchService {
  /// Sugerencias para [query]. [newSession] inicia una sesión de facturación
  /// nueva (una por dirección escogida).
  Future<List<AddressSuggestion>> suggest(String query, {bool newSession});

  /// Coordenadas de la sugerencia, o null si no se pudo geocodificar.
  Future<PlaceAddress?> resolve(AddressSuggestion suggestion);
}

/// No hay API key configurada (ver docs/configuracion-inicial.md).
class AddressSearchUnavailable implements Exception {
  const AddressSearchUnavailable();

  @override
  String toString() => 'AddressSearchUnavailable: falta MAPS_API_KEY';
}
