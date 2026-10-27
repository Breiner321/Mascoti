import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/clinics_geo_providers.dart';
import 'package:mascoti/core/data/clinics_geo_repository.dart';
import 'package:mascoti/core/data/vet_places_providers.dart';
import 'package:mascoti/core/data/vet_places_repository.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/map_vet.dart';
import 'package:mascoti/core/domain/vet_place.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/places/places_providers.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/directorio/data/location_service.dart';
import 'package:mascoti/plugins/directorio/directorio_plugin.dart';
import 'package:mascoti/plugins/directorio/presentation/directory_map_view.dart';
import 'package:mascoti/plugins/directorio/presentation/directory_page.dart';
import 'package:mascoti/plugins/directorio/presentation/directory_providers.dart';
import 'package:mascoti/plugins/directorio/presentation/no_clinics_view.dart';
import 'package:mascoti/plugins/directorio/presentation/vet_place_card.dart';

import '../../a11y.dart';
import '../../core/fake_plugins.dart';
import '../../core/fakes/fake_address_search.dart';

class _FakeLocation implements LocationService {
  _FakeLocation(this.result);

  LocationResult result;
  int requests = 0;
  final settings = <bool>[];

  @override
  Future<LocationResult> current() async {
    requests++;
    return result;
  }

  @override
  Future<bool> openSettings({required bool appSettings}) async {
    settings.add(appSettings);
    return true;
  }
}

const _medellin = LocationFound(lat: 6.2088, lng: -75.5674, accuracyM: 20);

/// Grados de latitud por km (la distancia se calcula desde _medellin).
const _degPerKm = 1 / 111.195;

NearbyClinic _nearby(String id, String nombre, double km, {bool emergencias = false}) =>
    NearbyClinic(
      clinic: Clinic(
        id: id,
        ownerUid: 'o',
        nombre: nombre,
        telefono: '6041234567',
        direccion: 'Calle 10',
        lat: _medellin.lat + km * _degPerKm,
        lng: _medellin.lng,
        tiposAnimales: const [AnimalType.perros, AnimalType.gatos],
        atencionEmergencias: emergencias,
        estado: ClinicStatus.activo,
      ),
      distanceKm: km,
    );

/// Veterinaria de OpenStreetMap a [km] al norte de _medellin.
VetPlace _place(String id, String nombre, double km, {String? telefono}) => VetPlace(
      osmId: id,
      nombre: nombre,
      lat: _medellin.lat + km * _degPerKm,
      lng: _medellin.lng,
      telefono: telefono,
      horario: 'Mo-Fr 08:00-18:00',
    );

void main() {
  late List<NearbyQuery> queries;
  late List<MapArea> osmAreas;
  late List<Uri> opened;

  Future<_FakeLocation> pumpPage(
    WidgetTester tester, {
    required LocationResult location,
    List<NearbyClinic> Function(NearbyQuery q)? results,
    List<VetPlace> places = const [],
    VetPlacesFailure? placesError,
    PluginRegistry? registry,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    queries = [];
    osmAreas = [];
    opened = [];
    final fake = _FakeLocation(location);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(fake),
          addressSearchServiceProvider.overrideWithValue(FakeAddressSearch()),
          pluginRegistryProvider.overrideWithValue(
            registry ?? PluginRegistry([const DirectorioPlugin()]),
          ),
          nearbyClinicsProvider.overrideWith((ref, q) {
            queries.add(q);
            return Stream.value(results?.call(q) ?? const []);
          }),
          nearbyVetPlacesProvider.overrideWith((ref, area) async {
            osmAreas.add(area);
            if (placesError != null) throw placesError;
            return places;
          }),
          directoryUrlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
          // El mapa descarga mosaicos de internet: en las pruebas, un botón
          // por marcador y otro que simula mover el mapa.
          directoryMapBuilderProvider.overrideWithValue(
            (data) => SingleChildScrollView(
              child: Column(
                children: [
                  const Text('MAPA'),
                  TextButton(
                    onPressed: () =>
                        data.onAreaChanged?.call(MapArea.around(6.30, -75.56, 3)),
                    child: const Text('mover mapa'),
                  ),
                  for (final v in data.vets)
                    TextButton(
                      onPressed: () => data.onTapVet(v),
                      child: Text('marcador ${switch (v) {
                        AllyVet() => v.nearby.clinic.id,
                        OsmVet() => v.key,
                      }}'),
                    ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => const Scaffold(body: DirectoryPage())),
            GoRoute(
              path: '/reservas/nueva',
              builder: (_, state) =>
                  Scaffold(body: Text('nueva reserva ${state.uri.queryParameters['clinicId']}')),
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  group('sin permiso de ubicación', () {
    testWidgets('explica y ofrece buscar por dirección o ciudad', (tester) async {
      final location = await pumpPage(tester, location: const LocationDenied());

      expect(find.text(DirectoryPage.deniedMessage), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Dirección o ciudad'), findsOneWidget);
      expect(find.text('MAPA'), findsNothing);

      await tester.tap(find.text('Permitir ubicación'));
      await tester.pumpAndSettle();
      expect(location.requests, 2);
    });

    testWidgets('negado para siempre: abre los ajustes', (tester) async {
      final location = await pumpPage(tester, location: const LocationDenied(permanently: true));

      await tester.tap(find.text('Abrir ajustes'));
      expect(location.settings, [true]);
    });

    testWidgets('al elegir una dirección busca clínicas alrededor de ella', (tester) async {
      await pumpPage(
        tester,
        location: const LocationDenied(),
        results: (_) => [_nearby('c1', 'Clínica Norte', 1.2)],
      );

      await tester.enterText(find.widgetWithText(TextField, 'Dirección o ciudad'), 'Calle 100');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calle 100 # 15-20'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cerca de: Calle 100 # 15-20'), findsOneWidget);
      expect(find.text('Clínica Norte'), findsOneWidget);
      expect(queries.last.lat, bogotaAddress.lat);
      expect(queries.last.lng, bogotaAddress.lng);
    });
  });

  group('sin resultados', () {
    testWidgets('muestra el mensaje del RF y el deslizador amplía el radio', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        // Solo hay una clínica a 30 km.
        results: (q) => q.radiusKm >= 30 ? [_nearby('c1', 'Clínica Lejana', 28)] : [],
      );

      expect(find.text(NoClinicsView.message), findsOneWidget);
      expect(find.text('Radio de búsqueda: 10 km'), findsOneWidget);
      expect(queries.last.radiusKm, 10);

      // Arrastrar el deslizador hasta el final (50 km).
      await tester.drag(find.byType(Slider), const Offset(2000, 0));
      await tester.pumpAndSettle();

      expect(queries.last.radiusKm, 50);
      expect(find.text(NoClinicsView.message), findsNothing);
      expect(find.text('Clínica Lejana'), findsOneWidget);
      expect(find.text('Hasta 50 km'), findsOneWidget);
    });
  });

  testWidgets('con ubicación: mapa, lista con distancia y "Agendar" en Próximamente',
      (tester) async {
    await pumpPage(
      tester,
      location: _medellin,
      results: (_) => [
        _nearby('c1', 'Clínica Norte', 0.8),
        _nearby('c2', 'Urgencias 24h', 2.3, emergencias: true),
      ],
    );

    expect(find.text('MAPA'), findsOneWidget);
    expect(find.text('Clínica Norte'), findsOneWidget);
    expect(find.text('Veterinaria · 800 m'), findsOneWidget);
    expect(find.text('Urgencias · 2,3 km'), findsOneWidget);
    expect(find.textContaining('aproximada'), findsNothing);

    await tester.tap(find.text('Agendar').first);
    await tester.pump();
    expect(find.text('Próximamente: agendar citas'), findsOneWidget);
  });

  testWidgets('"24 horas" filtra por emergencias', (tester) async {
    await pumpPage(tester, location: _medellin, results: (_) => [_nearby('c1', 'Vet', 1)]);

    await tester.tap(find.text('24 horas'));
    await tester.pumpAndSettle();

    expect(queries.last.filters.onlyEmergencies, isTrue);
    expect(find.text('Quitar filtros'), findsOneWidget);
  });

  testWidgets('tocar un marcador muestra la tarjeta de la clínica', (tester) async {
    await pumpPage(tester, location: _medellin, results: (_) => [_nearby('c1', 'Clínica Norte', 1.5)]);

    await tester.tap(find.text('marcador c1'));
    await tester.pumpAndSettle();

    expect(find.text('Especies atendidas'), findsOneWidget);
    expect(find.text('Perros'), findsOneWidget);
    expect(find.text('6041234567'), findsOneWidget);
    expect(find.text('1,5 km'), findsOneWidget);
    expect(find.text('Ver perfil'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Agendar'), findsWidgets);
  });

  testWidgets('"Agendar" abre reservas si ya existe /reservas/nueva', (tester) async {
    await pumpPage(
      tester,
      location: _medellin,
      results: (_) => [_nearby('c1', 'Clínica Norte', 1)],
      registry: PluginRegistry([
        const DirectorioPlugin(),
        FakePlugin('reservas', roles: {UserRole.dueno}, paths: ['/reservas', '/reservas/nueva']),
      ]),
    );
    await tester.tap(find.text('Agendar').first);
    await tester.pumpAndSettle();
    expect(find.text('Próximamente: agendar citas'), findsNothing);
    expect(find.text('nueva reserva c1'), findsOneWidget);
  });

  testWidgets('precisión mayor a 500 m: aviso no bloqueante que se puede cerrar',
      (tester) async {
    await pumpPage(
      tester,
      location: const LocationFound(lat: 6.2, lng: -75.5, accuracyM: 820),
      results: (_) => [_nearby('c1', 'Clínica Norte', 1)],
    );

    expect(find.textContaining('Tu ubicación es aproximada (± 820 m)'), findsOneWidget);
    expect(find.text('Clínica Norte'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(find.textContaining('aproximada'), findsNothing);
  });

  group('veterinarias que aún no usan Mascoti (Cambio 4)', () {
    testWidgets('aparecen en la lista y su tarjeta no permite agendar', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        results: (_) => [_nearby('c1', 'Clínica Norte', 0.5)],
        places: [_place('node/9', 'Vet Barrio', 1.2, telefono: '6045550000')],
      );

      expect(find.text('Clínica Norte'), findsOneWidget);
      expect(find.text('Vet Barrio'), findsOneWidget);
      expect(find.text('Sin Mascoti · 1,2 km'), findsOneWidget);
      expect(find.text('Aliado Mascoti'), findsWidgets);
      expect(find.text(DirectoryPage.othersLegend), findsOneWidget);
      // Solo el aliado tiene "Agendar".
      expect(find.widgetWithText(FilledButton, 'Agendar'), findsOneWidget);

      await tester.tap(find.text('marcador osm:node/9'));
      await tester.pumpAndSettle();

      final card = find.byType(VetPlaceCard);
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(VetPlaceCard.notAllyMessage)),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Agendar')), findsNothing);
      expect(find.descendant(of: card, matching: find.text('Lu-Vi 8:00 a. m.–6:00 p. m.')),
          findsOneWidget);

      await tester.tap(find.descendant(of: card, matching: find.text('Cómo llegar')));
      await tester.pump();
      expect(opened.single.scheme, 'geo');

      await tester.tap(find.descendant(of: card, matching: find.text('Llamar')));
      await tester.pump();
      expect(opened.last.toString(), 'tel:6045550000');
    });

    testWidgets('sin teléfono no hay "Llamar"', (tester) async {
      await pumpPage(tester, location: _medellin, places: [_place('node/9', 'Vet Barrio', 1)]);

      await tester.tap(find.text('Vet Barrio'));
      await tester.pumpAndSettle();
      expect(find.text(VetPlaceCard.notAllyMessage), findsOneWidget);
      expect(find.text('Llamar'), findsNothing);
      expect(find.text('Cómo llegar'), findsOneWidget);
    });

    testWidgets('una aliada que también está en OpenStreetMap sale una vez', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        results: (_) => [_nearby('c1', 'Clínica Veterinaria Patitas', 1)],
        places: [_place('node/9', 'Veterinaria Patitas', 1.02)],
      );

      expect(find.textContaining('Patitas'), findsOneWidget);
      expect(find.text('marcador c1'), findsOneWidget);
      expect(find.text('marcador osm:node/9'), findsNothing);
    });

    testWidgets('"Solo aliados" las oculta', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        results: (_) => [_nearby('c1', 'Clínica Norte', 0.5)],
        places: [_place('node/9', 'Vet Barrio', 1)],
      );

      await tester.ensureVisible(find.text('Solo aliados'));
      await tester.tap(find.text('Solo aliados'));
      await tester.pumpAndSettle();

      expect(find.text('Vet Barrio'), findsNothing);
      expect(find.text(DirectoryPage.othersLegend), findsNothing);
      expect(find.text('Clínica Norte'), findsOneWidget);
    });

    testWidgets('con filtros de aliados se ocultan y se explica por qué', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        results: (_) => [_nearby('c1', 'Clínica Norte', 0.5)],
        places: [_place('node/9', 'Vet Barrio', 1)],
      );

      await tester.tap(find.text('24 horas'));
      await tester.pumpAndSettle();

      expect(find.text(DirectoryPage.allyOnlyFiltersNote), findsOneWidget);
      expect(find.text('Vet Barrio'), findsNothing);
    });

    testWidgets('si fallan, los aliados siguen y hay "Reintentar"', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        results: (_) => [_nearby('c1', 'Clínica Norte', 0.5)],
        placesError: VetPlacesFailure.unavailable,
      );

      expect(find.text('Clínica Norte'), findsOneWidget);
      expect(find.text(VetPlacesFailure.unavailable.message), findsOneWidget);
      final before = osmAreas.length;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(osmAreas.length, before + 1);
    });

    testWidgets('área muy grande: pide acercar el mapa, sin "Reintentar"', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        results: (_) => [_nearby('c1', 'Clínica Norte', 0.5)],
        placesError: VetPlacesFailure.tooLargeArea,
      );

      expect(find.text('Acerca el mapa para ver otras veterinarias.'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('sin Supabase configurado no muestra avisos', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        results: (_) => [_nearby('c1', 'Clínica Norte', 0.5)],
        placesError: VetPlacesFailure.notConfigured,
      );

      expect(find.text(VetPlacesFailure.notConfigured.message), findsNothing);
      expect(find.text('Clínica Norte'), findsOneWidget);
    });

    testWidgets('al mover el mapa busca en el área visible', (tester) async {
      await pumpPage(tester, location: _medellin, results: (_) => [_nearby('c1', 'Clínica Norte', 0.5)]);
      expect(queries.last.lat, _medellin.lat);

      await tester.tap(find.text('mover mapa'));
      await tester.pumpAndSettle();

      final area = MapArea.around(6.30, -75.56, 3).rounded();
      expect(osmAreas.last, area);
      expect(queries.last.lat, area.centerLat);
      expect(queries.last.lng, area.centerLng);
      // Radio que cubre las esquinas del área (≈ 3 km × √2).
      expect(queries.last.radiusKm, closeTo(4.3, 0.1));
    });

    testWidgets('accesible: áreas táctiles, etiquetas y contraste', (tester) async {
      await pumpPage(
        tester,
        location: _medellin,
        results: (_) => [_nearby('c1', 'Clínica Norte', 0.5)],
        places: [_place('node/9', 'Vet Barrio', 1, telefono: '6045550000')],
      );
      await expectAccessible(tester);

      await tester.tap(find.text('Vet Barrio'));
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });

    testWidgets('tarjeta con texto al 200 %', (tester) async {
      useLargeText(tester);
      await pumpPage(
        tester,
        location: _medellin,
        places: [_place('node/9', 'Veterinaria del Barrio con nombre largo', 1, telefono: '6045550000')],
      );
      await tester.tap(find.text('marcador osm:node/9'));
      await tester.pumpAndSettle();
      expect(find.text(VetPlaceCard.notAllyMessage), findsOneWidget);
      expectNoOverflow(tester);
    });
  });
}
