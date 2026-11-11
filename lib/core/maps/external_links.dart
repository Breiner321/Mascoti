/// Enlaces fuera de la app para cualquier veterinaria (aliada o no):
/// "Cómo llegar" y "Llamar". Los usan el directorio (RF-09) y el SOS (RF-10).
abstract final class ExternalLinks {
  /// "Cómo llegar": primero la app de mapas del teléfono (geo:), después la
  /// ruta en openstreetmap.org si no hay ninguna.
  static List<Uri> directions(double lat, double lng, String name) => [
        Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})'),
        Uri.https('www.openstreetmap.org', '/directions', {'route': ';$lat,$lng'}),
      ];

  static Uri call(String phone) => Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
}
