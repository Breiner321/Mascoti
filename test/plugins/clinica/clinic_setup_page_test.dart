import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:mascoti/core/domain/opening_hours.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/plugins/clinica/clinica_plugin.dart';
import 'package:mascoti/plugins/clinica/clinica_routes.dart';
import 'package:mascoti/plugins/clinica/data/clinic_repository.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_providers.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_setup_page.dart';

class _DeniedRepository extends ClinicRepository {
  _DeniedRepository(FakeFirebaseFirestore firestore) : super(firestore: firestore);

  int calls = 0;

  @override
  Future<void> saveCareProfile(
    Clinic current, {
    required List<AnimalType> tiposAnimales,
    required bool atencionEmergencias,
    required OpeningHours horarioBase,
  }) async {
    calls++;
    throw const ClinicPermissionDenied();
  }
}

void main() {
  late FakeFirebaseFirestore firestore;

  const clinicUser = AppUser(
    uid: 'vet',
    email: 'vet@correo.co',
    displayName: 'Vet',
    role: UserRole.clinica,
    clinicId: 'c1',
  );

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('clinics/c1').set({
      'ownerUid': 'vet',
      'nombre': 'Vet Central',
      'estado': 'incompleto',
    });
  });

  Future<void> pumpPage(WidgetTester tester, {ClinicRepository? repo}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: ClinicaRoutes.setup,
      routes: [
        GoRoute(
          path: ClinicaRoutes.setup,
          builder: (context, state) => const ClinicSetupPage(),
        ),
        GoRoute(
          path: ClinicaRoutes.agenda,
          builder: (context, state) => const Scaffold(body: Text('Panel clínica')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(clinicUser),
          clinicRepositoryProvider
              .overrideWithValue(repo ?? ClinicRepository(firestore: firestore)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder saveButton() => find.widgetWithText(FilledButton, 'Guardar Configuración');

  /// El botón está al final de una lista perezosa: hay que desplazarse a él.
  Future<void> scrollToSave(WidgetTester tester) async {
    await tester.scrollUntilVisible(saveButton(), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  Future<bool> isEnabled(WidgetTester tester) async {
    await scrollToSave(tester);
    return tester.widget<FilledButton>(saveButton()).onPressed != null;
  }

  Future<void> tapSave(WidgetTester tester) async {
    await scrollToSave(tester);
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
  }

  testWidgets('muestra las 7 especies, emergencias y horario base', (tester) async {
    await pumpPage(tester);

    for (final type in AnimalType.values) {
      expect(find.widgetWithText(CheckboxListTile, type.label), findsOneWidget);
    }
    expect(find.text('Atendemos emergencias'), findsOneWidget);
    // Se muestran en AM/PM; en Firestore siguen en 24 h.
    expect(find.text('8:00 a. m.'), findsOneWidget);
    expect(find.text('6:00 p. m.'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
  });

  testWidgets('"Guardar Configuración" deshabilitado sin especies', (tester) async {
    await pumpPage(tester);
    expect(await isEnabled(tester), isFalse);

    await tester.ensureVisible(find.text('Perros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perros'));
    await tester.pump();
    expect(await isEnabled(tester), isTrue);

    await tester.ensureVisible(find.text('Perros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perros'));
    await tester.pump();
    expect(await isEnabled(tester), isFalse);
  });

  testWidgets('primer guardado: escribe, activa la clínica y abre el panel',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Gatos'));
    await tester.pump();
    await tester.ensureVisible(find.text('Atendemos emergencias'));
    await tester.tap(find.text('Atendemos emergencias'));
    await tester.pump();
    await tester.ensureVisible(find.text('60 min'));
    await tester.tap(find.text('60 min'));
    await tester.pump();
    await tapSave(tester);

    final data = (await firestore.doc('clinics/c1').get()).data()!;
    expect(data['tiposAnimales'], ['gatos']);
    expect(data['atencionEmergencias'], isTrue);
    expect(data['horarioBase'],
        {'apertura': '08:00', 'cierre': '18:00', 'duracionSlotMin': 60});
    expect(data['estado'], 'activo');
    expect(find.text('Perfil actualizado'), findsOneWidget);
    expect(find.text('Panel clínica'), findsOneWidget);
  });

  testWidgets('edición posterior: carga lo guardado y no exige cerrar sesión',
      (tester) async {
    await firestore.doc('clinics/c1').update({
      'estado': 'activo',
      'tiposAnimales': ['aves'],
      'horarioBase': {'apertura': '07:00', 'cierre': '15:00', 'duracionSlotMin': 15},
    });
    await pumpPage(tester);

    final aves = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Aves'));
    expect(aves.value, isTrue);
    expect(find.text('7:00 a. m.'), findsOneWidget);
    expect(await isEnabled(tester), isTrue);
    expect(find.text('Cerrar sesión'), findsNothing);
  });

  testWidgets('error de permisos muestra el mensaje del RF', (tester) async {
    final repo = _DeniedRepository(firestore);
    await pumpPage(tester, repo: repo);

    await tester.tap(find.text('Perros'));
    await tester.pump();
    await tapSave(tester);

    expect(repo.calls, 1);
    expect(find.text('No tienes permisos para editar este perfil'), findsOneWidget);
    expect(find.byType(ClinicSetupPage), findsOneWidget);
  });

  testWidgets('sin la clínica muestra un mensaje', (tester) async {
    await firestore.doc('clinics/c1').delete();
    await pumpPage(tester);
    expect(find.text('No encontramos tu clínica.'), findsOneWidget);
  });

  test('el perfil de la clínica enlaza al perfil de atención; el dueño no', () {
    final registry = PluginRegistry([const ClinicaPlugin()]);
    expect(registry.profileLinksFor(clinicUser).single.path, ClinicaRoutes.setup);

    const owner = AppUser(
      uid: 'ana',
      email: 'ana@correo.co',
      displayName: 'Ana',
      role: UserRole.dueno,
    );
    expect(registry.profileLinksFor(owner), isEmpty);
  });
}
