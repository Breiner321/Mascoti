import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Resultado de pedir la ubicación del dueño (RF-09 pasos 1-3).
sealed class LocationResult {
  const LocationResult();
}

/// Ubicación del GPS. [accuracyM] es el margen de error en metros.
@immutable
class LocationFound extends LocationResult {
  const LocationFound(
      {required this.lat, required this.lng, required this.accuracyM});

  /// Más de 500 m de margen: aviso no bloqueante de posible imprecisión.
  static const impreciseAfterM = 500.0;

  final double lat;
  final double lng;
  final double accuracyM;

  bool get isImprecise => accuracyM > impreciseAfterM;
}

/// El dueño negó el permiso. [permanently]: ya no se puede volver a pedir
/// desde la app; hay que abrir los ajustes.
class LocationDenied extends LocationResult {
  const LocationDenied({this.permanently = false});

  final bool permanently;
}

/// El GPS del teléfono está apagado o no respondió.
class LocationUnavailable extends LocationResult {
  const LocationUnavailable();
}

/// Ubicación del teléfono. Interfaz para simularla en las pruebas.
abstract interface class LocationService {
  Future<LocationResult> current();

  /// Abre los ajustes de la app (permiso negado para siempre) o de ubicación.
  Future<bool> openSettings({required bool appSettings});
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationUnavailable();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        return const LocationDenied();
      case LocationPermission.deniedForever:
        return const LocationDenied(permanently: true);
      case LocationPermission.whileInUse:
      case LocationPermission.always:
      case LocationPermission.unableToDetermine:
        break;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationFound(
        lat: position.latitude,
        lng: position.longitude,
        accuracyM: position.accuracy,
      );
    } catch (_) {
      // Sin señal a tiempo: se usa la última conocida si hay.
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return const LocationUnavailable();
      return LocationFound(
          lat: last.latitude, lng: last.longitude, accuracyM: last.accuracy);
    }
  }

  @override
  Future<bool> openSettings({required bool appSettings}) => appSettings
      ? Geolocator.openAppSettings()
      : Geolocator.openLocationSettings();
}
