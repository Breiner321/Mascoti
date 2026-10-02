import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/domain/pet.dart';
import 'package:mascoti/plugins/mascotas/mascotas_plugin.dart';
import 'package:mascoti/plugins/mascotas/presentation/owner_home_page.dart';
import 'package:mascoti/plugins/mascotas/presentation/pets_providers.dart';
import 'package:mascoti/plugins/mascotas/presentation/widgets/shortcut_tile.dart';

import '../../core/fake_plugins.dart';

void main() {
  // Igual que hoy en plugin_manifest: mascotas + reservas (sin /reservas/nueva).
  final todayRegistry = PluginRegistry([
    const MascotasPlugin(),
    FakePlugin('reservas', roles: {UserRole.dueno}),
  ]);

  Future<void> pumpHome(
    WidgetTester tester, {
    required Stream<List<Pet>> pets,
    PluginRegistry? registry,
  }) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginRegistryProvider.overrideWithValue(registry ?? todayRegistry),
          myPetsProvider.overrideWith((ref) => pets),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: OwnerHomePage()),
        ),
      ),
    );
    await tester.pump();
  }

  bool comingSoon(String label) => find
      .descendant(
        of: find.widgetWithText(ShortcutTile, label),
        matching: find.text('Próximamente'),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('estado vacío: tarjetas y secciones del mockup', (tester) async {
    await pumpHome(tester, pets: Stream.value(const []));

    expect(find.text('Mi mascota'), findsOneWidget);
    expect(find.text('Registra tu primera mascota'), findsOneWidget);
    expect(find.text('Próxima cita'), findsOneWidget);
    expect(find.text('Sin citas · Agendar'), findsOneWidget);
    expect(find.text('Carnet'), findsOneWidget);
    expect(find.text('Vacunas y controles'), findsOneWidget);
    expect(find.text('Accesos'), findsOneWidget);
    expect(find.text('Servicios'), findsOneWidget);
    for (final label in ['Mapa cercano', 'Tienda', 'Agendar cita', 'Emergencia']) {
      expect(find.widgetWithText(ShortcutTile, label), findsOneWidget);
    }
    for (final label in ['Consulta', 'Peluquería', 'Vacunas']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('los módulos que aún no existen se ven como "Próximamente"',
      (tester) async {
    await pumpHome(tester, pets: Stream.value(const []));

    // directorio, tienda y sos no están en el manifiesto; reservas sí, pero
    // todavía no aporta /reservas/nueva.
    expect(comingSoon('Mapa cercano'), isTrue);
    expect(comingSoon('Tienda'), isTrue);
    expect(comingSoon('Emergencia'), isTrue);
    expect(comingSoon('Agendar cita'), isTrue);
    expect(
      tester.widget<ShortcutTile>(find.widgetWithText(ShortcutTile, 'Tienda')).onTap,
      isNull,
    );
  });

  testWidgets('un módulo habilitado y con su ruta se puede abrir', (tester) async {
    await pumpHome(
      tester,
      pets: Stream.value(const []),
      registry: PluginRegistry([
        const MascotasPlugin(),
        FakePlugin('tienda', roles: {UserRole.dueno}),
        FakePlugin('reservas',
            roles: {UserRole.dueno}, paths: ['/reservas', '/reservas/nueva']),
      ]),
    );

    expect(comingSoon('Tienda'), isFalse);
    expect(comingSoon('Agendar cita'), isFalse);
    expect(comingSoon('Mapa cercano'), isTrue);
  });

  testWidgets('cargando muestra un indicador', (tester) async {
    await pumpHome(tester, pets: const Stream.empty());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error al cargar mascotas muestra "Reintentar"', (tester) async {
    await pumpHome(tester, pets: Stream.error(Exception('permission-denied')));
    expect(find.text('No pudimos cargar tus mascotas. Verifica tu conexión.'),
        findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('con una mascota muestra su nombre y su resumen', (tester) async {
    final birth = DateTime.now().subtract(const Duration(days: 365 * 3 + 30));
    await pumpHome(
      tester,
      pets: Stream.value([
        Pet(
          id: 'p1',
          ownerUid: 'u1',
          nombre: 'Luna',
          especie: 'perro',
          fechaNacimiento: birth,
        ),
      ]),
    );

    expect(find.text('Luna'), findsOneWidget);
    expect(find.text('Perro · 3 años'), findsOneWidget);
    expect(find.text('Registra tu primera mascota'), findsNothing);
  });
}
