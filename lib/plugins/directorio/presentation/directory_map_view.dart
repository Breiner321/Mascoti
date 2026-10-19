import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/data/clinics_geo_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'directory_providers.dart';

/// Datos que necesita el mapa.
@immutable
class DirectoryMapData {
  const DirectoryMapData({
    required this.center,
    required this.clinics,
    required this.radiusKm,
    required this.onTapClinic,
  });

  final SearchCenter center;
  final List<NearbyClinic> clinics;
  final double radiusKm;
  final ValueChanged<NearbyClinic> onTapClinic;
}

/// Construye el mapa. En las pruebas se reemplaza (GoogleMap es una vista
/// nativa que no existe en `flutter test`).
final directoryMapBuilderProvider = Provider<Widget Function(DirectoryMapData)>(
  (ref) => (data) => DirectoryMapView(data: data),
);

/// Mapa de Google centrado en el punto de búsqueda (RF-09 paso 6), con un
/// marcador por clínica en los colores del tema: morado, y rojo (SOS) las
/// que atienden emergencias.
class DirectoryMapView extends StatefulWidget {
  const DirectoryMapView({super.key, required this.data});

  final DirectoryMapData data;

  /// Zoom para que el círculo del radio quepa en la pantalla.
  static double zoomFor(double radiusKm) => 13.5 - log(radiusKm / 2.5) / ln2;

  @override
  State<DirectoryMapView> createState() => _DirectoryMapViewState();
}

class _DirectoryMapViewState extends State<DirectoryMapView> {
  GoogleMapController? _controller;

  static final _clinicHue = HSVColor.fromColor(AppColors.primary).hue;
  static final _emergencyHue = HSVColor.fromColor(AppColors.sos).hue;

  LatLng get _center => LatLng(widget.data.center.lat, widget.data.center.lng);

  @override
  void didUpdateWidget(DirectoryMapView old) {
    super.didUpdateWidget(old);
    final moved = old.data.center.lat != widget.data.center.lat ||
        old.data.center.lng != widget.data.center.lng;
    if (moved || old.data.radiusKm != widget.data.radiusKm) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(
            _center, DirectoryMapView.zoomFor(widget.data.radiusKm)),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final markers = <Marker>{
      for (final n in data.clinics)
        Marker(
          markerId: MarkerId(n.clinic.id),
          position: LatLng(n.clinic.lat, n.clinic.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            n.clinic.atencionEmergencias ? _emergencyHue : _clinicHue,
          ),
          onTap: () => data.onTapClinic(n),
        ),
      // Sin GPS no hay punto azul: se marca el lugar buscado.
      if (!data.center.fromGps)
        Marker(
          markerId: const MarkerId('centro'),
          position: _center,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: data.center.label),
        ),
    };
    return GoogleMap(
      initialCameraPosition: CameraPosition(
          target: _center, zoom: DirectoryMapView.zoomFor(data.radiusKm)),
      onMapCreated: (controller) => _controller = controller,
      myLocationEnabled: data.center.fromGps,
      myLocationButtonEnabled: data.center.fromGps,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      markers: markers,
      circles: {
        Circle(
          circleId: const CircleId('radio'),
          center: _center,
          radius: data.radiusKm * 1000,
          fillColor: AppColors.primary.withValues(alpha: 0.06),
          strokeColor: AppColors.primary.withValues(alpha: 0.4),
          strokeWidth: 1,
        ),
      },
    );
  }
}
