import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/clinics_geo_providers.dart';
import 'package:mascoti/core/data/clinics_geo_repository.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/places/places_providers.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/directorio/data/location_service.dart';
import 'package:mascoti/plugins/directorio/directorio_plugin.dart';
import 'package:mascoti/plugins/directorio/presentation/directory_map_view.dart';
import 'package:mascoti/plugins/directorio/presentation/directory_page.dart';
import 'package:mascoti/plugins/directorio/presentation/directory_providers.dart';
import 'package:mascoti/plugins/directorio/presentation/no_clinics_view.dart';

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

NearbyClinic _nearby(String id, String nombre, double km, {bool emergencias = false}) =>
    NearbyClinic(
      clinic: Clinic(
        id: id,
        ownerUid: 'o',
        nombre: nombre,
        telefono: '6041234567',
        direccion: 'Calle 10',
        lat: 6.2,
        lng: -75.5,
        tiposAnimales: const [AnimalType.perros, AnimalType.gatos],
        atencionEmergencias: emergencias,
        estado: ClinicStatus.activo,
      ),
      distanceKm: km,
    );

void main() {
  late List<NearbyQuery> queries;

  Future<_FakeLocation> pumpPage(
    WidgetTester tester, {
    required LocationResult location,
    List<NearbyClinic> Function(NearbyQuery q)? results,
    PluginRegistry? registry,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    queries = [];
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
          // El mapa descarga mosaicos de internet: en las pruebas, un botón por marcador.
          directoryMapBuilderProvider.overrideWithValue(
            (data) => Column(
              children: [
                const Text('MAPA'),
                for (final n in data.clinics)
                  TextButton(
                    onPressed: () => data.onTapClinic(n),
                    child: Text('marcador ${n.clinic.id}'),
                  ),
              ],
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
}
