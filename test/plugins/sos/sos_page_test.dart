import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/data/clinics_geo_repository.dart';
import 'package:mascoti/core/data/saved_clinics_store.dart';
import 'package:mascoti/core/data/vet_places_providers.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/vet_place.dart';
import 'package:mascoti/core/location/location_service.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/sos/domain/emergency_ranking.dart';
import 'package:mascoti/plugins/sos/presentation/emergency_clinic_card.dart';
import 'package:mascoti/plugins/sos/presentation/sos_page.dart';
import 'package:mascoti/plugins/sos/presentation/sos_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../a11y.dart';

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
const _degPerKm = 1 / 111.195;

NearbyClinic _ally(String id, String nombre, double km, {bool emergencias = false}) =>
    NearbyClinic(
      clinic: Clinic(
        id: id,
        ownerUid: 'o',
        nombre: nombre,
        telefono: '6041234567',
        direccion: 'Calle 10',
        lat: _medellin.lat + km * _degPerKm,
        lng: _medellin.lng,
        atencionEmergencias: emergencias,
        estado: ClinicStatus.activo,
      ),
      distanceKm: km,
    );

const _savedFavorite = SavedClinic(
  key: 'aliado:fav',
  nombre: 'Clínica Favorita',
  lat: 6.21,
  lng: -75.56,
  telefono: '6047654321',
  aliada: true,
);
const _savedRecent = SavedClinic(
  key: 'osm:node/9',
  nombre: 'Veterinaria Vista en el Mapa',
  lat: 6.22,
  lng: -75.57,
);

void main() {
  late List<Uri> opened;

  tearDown(() => AppTheme.light());

  Future<_FakeLocation> pumpPage(
    WidgetTester tester, {
    required LocationResult location,
    Map<String, Object> saved = const {},
    Future<List<NearbyClinic>> Function()? allies,
    List<VetPlace> places = const [],
    ThemeData? theme,
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    opened = [];
    final fake = _FakeLocation(location);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          locationServiceProvider.overrideWithValue(fake),
          sosAlliesProvider.overrideWith((ref, p) => allies?.call() ?? Future.value(const [])),
          nearbyVetPlacesProvider.overrideWith((ref, area) async => places),
          sosUrlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(theme: theme ?? AppTheme.light(), home: const SosPage()),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  String savedJson(List<SavedClinic> list) => jsonEncode([for (final c in list) c.toMap()]);

  testWidgets('sin permiso de ubicación muestra las clínicas guardadas y "Activar ubicación"',
      (tester) async {
    final fake = await pumpPage(
      tester,
      location: const LocationDenied(),
      saved: {
        SavedClinicsStore.favoritesKey: savedJson([_savedFavorite]),
        SavedClinicsStore.recentKey: savedJson([_savedRecent, _savedFavorite]),
      },
    );

    expect(find.text(SosPage.noLocation), findsOneWidget);
    expect(find.byType(EmergencyClinicCard), findsNWidgets(2));
    expect(find.text('Clínica Favorita'), findsOneWidget);
    expect(find.text('Ya fuiste'), findsOneWidget);
    expect(find.text('Distancia desconocida'), findsNWidgets(2));
    // La guardada sin teléfono solo tiene "Cómo llegar".
    expect(find.text('Llamar'), findsOneWidget);

    await tester.tap(find.text('Llamar'));
    expect(opened.single, Uri(scheme: 'tel', path: '6047654321'));

    await tester.ensureVisible(find.text(SosPage.enableLocation));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SosPage.enableLocation));
    await tester.pumpAndSettle();
    expect(fake.requests, 2);
  });

  testWidgets('sin nada guardado ni ubicación nunca queda vacía', (tester) async {
    final fake = await pumpPage(tester, location: const LocationDenied(permanently: true));

    expect(find.text(SosPage.title), findsOneWidget);
    expect(find.textContaining('Aún no hay clínicas guardadas'), findsOneWidget);
    await tester.tap(find.text(SosPage.enableLocation));
    await tester.pumpAndSettle();
    expect(fake.settings, [true]);
  });

  testWidgets('con ubicación: aliadas con emergencias primero, luego OSM 24 h, luego las demás',
      (tester) async {
    await pumpPage(
      tester,
      location: _medellin,
      allies: () async => [
        _ally('a', 'Clínica Cercana', 0.5),
        _ally('u', 'Clínica Urgencias', 4, emergencias: true),
      ],
      places: [
        VetPlace(
          osmId: 'node/1',
          nombre: 'Veterinaria Nocturna',
          lat: _medellin.lat + 2 * _degPerKm,
          lng: _medellin.lng,
          horario: '24/7',
        ),
      ],
    );

    final names = [
      for (final card in tester.widgetList<EmergencyClinicCard>(find.byType(EmergencyClinicCard)))
        card.vet.nombre,
    ];
    expect(names, ['Clínica Urgencias', 'Veterinaria Nocturna', 'Clínica Cercana']);
    expect(find.text('A 4,0 km'), findsOneWidget);
    expect(find.text(SosPage.noLocation), findsNothing);
  });

  testWidgets('sin conexión con ubicación: las guardadas con su distancia y "Reintentar"',
      (tester) async {
    await pumpPage(
      tester,
      location: _medellin,
      saved: {SavedClinicsStore.recentKey: savedJson([_savedFavorite])},
      allies: () async => throw Exception('sin red'),
    );

    expect(find.text(SosPage.offline), findsOneWidget);
    expect(find.text('Clínica Favorita'), findsOneWidget);
    // A ~800 m de la ubicación (antes, "Distancia desconocida").
    expect(find.textContaining(RegExp(r'^A \d+ m$')), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('con TalkBack la primera acción es "Llamar a" la más cercana', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPage(
      tester,
      location: _medellin,
      allies: () async => [_ally('u', 'Clínica Urgencias', 4, emergencias: true)],
    );

    final firstAction = tester.semantics
        .simulatedAccessibilityTraversal()
        .firstWhere((node) => node.getSemanticsData().hasAction(SemanticsAction.tap));
    expect(firstAction.label, 'Llamar a Clínica Urgencias');
    handle.dispose();
  });

  testWidgets('accesible, al 200 % y en modo oscuro', (tester) async {
    useLargeText(tester);
    await pumpPage(
      tester,
      location: _medellin,
      theme: AppTheme.of(AppPalette.dark),
      allies: () async => [
        _ally('u', 'Clínica Veterinaria de Urgencias del Poblado', 4, emergencias: true),
      ],
    );

    expectNoOverflow(tester);
    await expectAccessible(tester);
  });

  testWidgets('accesible en tema claro con las guardadas', (tester) async {
    await pumpPage(
      tester,
      location: const LocationUnavailable(),
      saved: {SavedClinicsStore.favoritesKey: savedJson([_savedFavorite, _savedRecent])},
    );
    await expectAccessible(tester);
  });

  group('EmergencyClinicCard', () {
    Future<void> pumpCard(WidgetTester tester, EmergencyVet vet) => tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: EmergencyClinicCard(vet: vet, onCall: () {}, onDirections: () {}),
              ),
            ),
          ),
        );

    testWidgets('sin teléfono no tiene botón Llamar, solo "Cómo llegar"', (tester) async {
      await pumpCard(tester, const EmergencyVet(_savedRecent, distanceKm: 1.2));
      expect(find.text('Llamar'), findsNothing);
      expect(find.text('Cómo llegar'), findsOneWidget);
      expect(find.text('A 1,2 km'), findsOneWidget);
      expect(find.text(EmergencyClinicCard.allyLabel), findsNothing);
    });

    testWidgets('la aliada lleva la huella y el texto "Aliado Mascoti"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester, const EmergencyVet(_savedFavorite, distanceKm: 0.3));
      expect(find.text(EmergencyClinicCard.allyLabel), findsOneWidget);
      expect(find.byIcon(Icons.pets), findsNWidgets(2));
      expect(find.bySemanticsLabel('Llamar a Clínica Favorita'), findsOneWidget);
      expect(find.bySemanticsLabel('Cómo llegar a Clínica Favorita'), findsOneWidget);
      handle.dispose();
    });
  });
}
