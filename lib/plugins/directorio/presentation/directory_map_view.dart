import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/domain/map_vet.dart';
import '../../../core/domain/vet_place.dart';
import '../../../core/theme/app_theme.dart';
import 'directory_providers.dart';
import 'vet_marker_icon.dart';

/// Datos que necesita el mapa.
@immutable
class DirectoryMapData {
  const DirectoryMapData({
    required this.center,
    required this.vets,
    required this.radiusKm,
    required this.onTapVet,
    this.onAreaChanged,
  });

  final SearchCenter center;

  /// Aliados y no aliados, ya sin duplicados (Cambio 4).
  final List<MapVet> vets;
  final double radiusKm;
  final ValueChanged<MapVet> onTapVet;

  /// Lo que se ve del mapa después de moverlo o hacer zoom (con espera):
  /// la página vuelve a buscar en esa área.
  final ValueChanged<MapArea>? onAreaChanged;
}

/// Construye el mapa. En las pruebas se reemplaza (los mosaicos del mapa se
/// descargan de internet, y en `flutter test` no hay red).
final directoryMapBuilderProvider = Provider<Widget Function(DirectoryMapData)>(
  (ref) => (data) => DirectoryMapView(data: data),
);

/// Mapa de OpenStreetMap (`flutter_map`) centrado en el punto de búsqueda
/// (RF-09 paso 6), con aliados y otras veterinarias ([VetMarkerIcon]).
/// Al moverlo informa el área visible. No necesita API key.
class DirectoryMapView extends StatefulWidget {
  const DirectoryMapView({super.key, required this.data});

  final DirectoryMapData data;

  /// Mosaicos públicos de OpenStreetMap. Su política de uso exige
  /// identificar la app (userAgentPackageName) y mostrar la atribución.
  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const userAgent = 'co.mascoti.mascoti';

  /// Espera después de mover el mapa antes de volver a buscar.
  static const reloadDelay = Duration(milliseconds: 700);

  /// Etiqueta del marcador para el lector de pantalla.
  static String semanticLabel(MapVet vet) => switch (vet) {
        AllyVet() => 'Aliado Mascoti: ${vet.nombre}',
        OsmVet() => 'Veterinaria sin Mascoti: ${vet.nombre}',
      };

  /// Zoom para que un radio de [radiusKm] quepa en la pantalla.
  static double zoomFor(double radiusKm) => 13.5 - log(radiusKm / 2.5) / ln2;

  @override
  State<DirectoryMapView> createState() => _DirectoryMapViewState();
}

class _DirectoryMapViewState extends State<DirectoryMapView> {
  final _controller = MapController();
  bool _ready = false;
  Timer? _debounce;

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

  void _report(MapCamera camera) {
    _debounce?.cancel();
    _debounce = Timer(DirectoryMapView.reloadDelay, () {
      final b = camera.visibleBounds;
      widget.data.onAreaChanged
          ?.call(MapArea(sur: b.south, oeste: b.west, norte: b.north, este: b.east));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
        onMapReady: () {
          _ready = true;
          _report(_controller.camera);
        },
        onPositionChanged: (camera, _) => _report(camera),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: DirectoryMapView.tileUrl,
          userAgentPackageName: DirectoryMapView.userAgent,
        ),
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
          // Primero las no aliadas: los aliados quedan encima.
          for (final v in [
            ...data.vets.whereType<OsmVet>(),
            ...data.vets.whereType<AllyVet>(),
          ])
            Marker(
              point: LatLng(v.lat, v.lng),
              width: 48,
              height: 48,
              child: _VetMarker(vet: v, onTap: () => data.onTapVet(v)),
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

/// Marcador de una veterinaria. Área táctil de 48 dp y etiqueta para el
/// lector de pantalla que dice si es aliada.
class _VetMarker extends StatelessWidget {
  const _VetMarker({required this.vet, required this.onTap});

  final MapVet vet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vet = this.vet;
    return Semantics(
      button: true,
      label: DirectoryMapView.semanticLabel(vet),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: VetMarkerIcon(
            ally: vet is AllyVet,
            emergency: vet is AllyVet && vet.nearby.clinic.atencionEmergencias,
          ),
        ),
      ),
    );
  }
}
