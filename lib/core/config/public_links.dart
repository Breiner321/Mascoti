/// Enlaces públicos de Mascoti (Firebase Hosting del proyecto mascoti-b27cf,
/// plan Spark). Los usa la placa QR (RF-17): el código apunta a
/// [qrTag], que muestra la página `hosting/q.html`.
abstract final class PublicLinks {
  static const hostingBase = 'https://mascoti-b27cf.web.app';

  /// Página pública de una placa: `https://mascoti-b27cf.web.app/q/{qrId}`.
  static String qrTag(String qrId) => '$hostingBase/q/$qrId';
}
