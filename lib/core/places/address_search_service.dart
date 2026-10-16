import 'place_address.dart';

/// Buscador de direcciones (OpenStreetMap). Lo usan el registro de la clínica
/// (RF-01) y, más adelante, el perfil de la clínica (RF-04) y la dirección de
/// entrega (RF-12). Se reemplaza con un override en las pruebas.
abstract interface class AddressSearchService {
  /// Sugerencias para [query]. [newSession] marca el inicio de una búsqueda
  /// nueva (útil para proveedores que cobran por sesión; OSM lo ignora).
  Future<List<AddressSuggestion>> suggest(String query, {bool newSession});

  /// Coordenadas de la sugerencia, o null si no se pudo geocodificar.
  Future<PlaceAddress?> resolve(AddressSuggestion suggestion);
}

/// El proveedor de direcciones no está disponible (caído o limitando el uso).
class AddressSearchUnavailable implements Exception {
  const AddressSearchUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'AddressSearchUnavailable: $reason';
}
