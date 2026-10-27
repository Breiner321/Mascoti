import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

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

/// Construye el mapa. En las pruebas se reemplaza (los mosaicos del mapa se
/// descargan de internet, y en `flutter test` no hay red).
final directoryMapBuilderProvider = Provider<Widget Function(DirectoryMapData)>(
  (ref) => (data) => DirectoryMapView(data: data),
);

/// Mapa de OpenStreetMap (`flutter_map`) centrado en el punto de búsqueda
/// (RF-09 paso 6), con un marcador por clínica en los colores del tema:
/// morado, y rojo (SOS) las que atienden emergencias. No necesita API key.
class DirectoryMapView extends StatefulWidget {
  const DirectoryMapView({super.key, required this.data});

  final DirectoryMapData data;

  /// Mosaicos públicos de OpenStreetMap. Su política de uso exige
  /// identificar la app (userAgentPackageName) y mostrar la atribución.
  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const userAgent = 'co.mascoti.mascoti';

  /// Zoom para que el círculo del radio quepa en la pantalla.
  static double zoomFor(double radiusKm) => 13.5 - log(radiusKm / 2.5) / ln2;

  @override
  State<DirectoryMapView> createState() => _DirectoryMapViewState();
}

class _DirectoryMapViewState extends State<DirectoryMapView> {
  final _controller = MapController();
  bool _ready = false;

  LatLng get _center => LatLng(widget.data.center.lat, widget.data.center.lng);

  @override
  void didUpdateWidget(DirectoryMapView old) {
    super.didUpdateWidget(old);
    final moved = old.data.center.lat != widget.data.center.lat ||
        old.data.center.lng != widget.data.center.lng;
    if (_ready && (moved || old.data.radiusKm != widget.data.radiusKm)) {
      _controller.move(_center, DirectoryMapView.zoomFor(widget.data.radiusKm));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: DirectoryMapView.zoomFor(data.radiusKm),
        minZoom: 5,
        maxZoom: 18,
        onMapReady: () => _ready = true,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: DirectoryMapView.tileUrl,
          userAgentPackageName: DirectoryMapView.userAgent,
        ),
        CircleLayer(circles: [
          CircleMarker(
            point: _center,
            radius: data.radiusKm * 1000,
            useRadiusInMeter: true,
            color: AppColors.primary.withValues(alpha: 0.06),
            borderColor: AppColors.primary.withValues(alpha: 0.4),
            borderStrokeWidth: 1,
          ),
        ]),
        MarkerLayer(markers: [
          // Punto de búsqueda: azul con GPS ("estás aquí"); pin sin GPS.
          Marker(
            point: _center,
            width: 24,
            height: 24,
            child: data.center.fromGps
                ? Container(
                    decoration: BoxDecoration(
                      color: AppColors.mapUser,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 3),
                    ),
                  )
                : Icon(Icons.person_pin_circle,
                    color: AppColors.mapUser, size: 24),
          ),
          for (final n in data.clinics)
            Marker(
              point: LatLng(n.clinic.lat, n.clinic.lng),
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => data.onTapClinic(n),
                child: Tooltip(
                  message: n.clinic.nombre,
                  child: Icon(
                    Icons.location_on,
                    size: 44,
                    color: n.clinic.atencionEmergencias
                        ? AppColors.sos
                        : AppColors.primary,
                  ),
                ),
              ),
            ),
        ]),
        const SimpleAttributionWidget(
          // La librería ya antepone "©".
          source: Text('colaboradores de OpenStreetMap'),
        ),
      ],
    );
  }
}
