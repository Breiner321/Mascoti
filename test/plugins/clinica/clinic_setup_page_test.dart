import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/domain/animal_type.dart';
import 'package:mascoti/core/domain/clinic.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mascoti/core/data/appointments_providers.dart';
import 'package:mascoti/core/data/appointments_repository.dart';
import 'package:mascoti/core/domain/weekly_schedule.dart';
import 'package:mascoti/core/format/bogota_time.dart';
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
    required WeeklySchedule horarioSemanal,
    required BookingSettings reservas,
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
          appointmentsRepositoryProvider
              .overrideWithValue(AppointmentsRepository(firestore: firestore)),
          // Domingo 1 de noviembre de 2026, 9:00 a. m.
          agendaClockProvider.overrideWithValue(() => BogotaTime.at(2026, 11, 1, 9)),
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

  /// Desplaza la lista (hacia arriba o abajo) hasta [finder].
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    final list = find.byType(Scrollable).first;
    for (final delta in [-300.0, 300.0]) {
      if (finder.evaluate().isNotEmpty) break;
      await tester.scrollUntilVisible(finder, delta, scrollable: list, maxScrolls: 30)
          .catchError((_) {});
    }
    await tester.ensureVisible(finder);
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

  testWidgets('muestra las 7 especies, emergencias, horario semanal y reservas', (tester) async {
    await pumpPage(tester);

    for (final type in AnimalType.values) {
      expect(find.widgetWithText(CheckboxListTile, type.label), findsOneWidget);
    }
    expect(find.text('Atendemos emergencias'), findsOneWidget);
    // Clínica nueva: lunes a sábado de 8 a 18 con almuerzo; domingo cerrado.
    // Se muestran en AM/PM; en Firestore siguen en 24 h.
    expect(find.text('Abre 8:00 a. m.'), findsNWidgets(6));
    expect(find.text('Cierra 6:00 p. m.'), findsNWidgets(6));
    expect(find.text('Desde 12:00 p. m.'), findsNWidgets(6));
    expect(find.text('Cerrado'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('30 min'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('30 días antes'), findsOneWidget);
    expect(find.text('2 horas'), findsOneWidget);
  });

  testWidgets('"Guardar Configuración" deshabilitado sin especies', (tester) async {
    await pumpPage(tester);
    expect(await isEnabled(tester), isFalse);

    await scrollTo(tester, find.text('Perros'));
    await tester.tap(find.text('Perros'));
    await tester.pump();
    expect(await isEnabled(tester), isTrue);

    await scrollTo(tester, find.text('Perros'));
    await tester.tap(find.text('Perros'));
    await tester.pump();
    expect(await isEnabled(tester), isFalse);
  });

  testWidgets('primer guardado: escribe, activa la clínica y abre el panel',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Gatos'));
    await tester.pump();
    await scrollTo(tester, find.text('Atendemos emergencias'));
    await tester.tap(find.text('Atendemos emergencias'));
    await tester.pump();
    await scrollTo(tester, find.text('60 min'));
    await tester.tap(find.text('60 min'));
    await tester.pump();
    await tapSave(tester);

    final data = (await firestore.doc('clinics/c1').get()).data()!;
    expect(data['tiposAnimales'], ['gatos']);
    expect(data['atencionEmergencias'], isTrue);
    expect(data['horarioSemanal'], WeeklySchedule.standard.toMap());
    expect(data['reservas'],
        {'duracionSlotMin': 60, 'anticipacionMaxDias': 30, 'anticipacionMinMin': 120});
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
    // Sin migrar: el horarioBase se ve como horario de todos los días.
    expect(find.text('Abre 7:00 a. m.'), findsNWidgets(7));
    expect(await isEnabled(tester), isTrue);
    expect(find.text('Cerrar sesión'), findsNothing);
  });

  testWidgets('Cambio 2: si el horario nuevo deja citas por fuera, las lista y permite guardar',
      (tester) async {
    await firestore.doc('clinics/c1').update({
      'estado': 'activo',
      'tiposAnimales': ['perros'],
      'horarioBase': {'apertura': '08:00', 'cierre': '18:00', 'duracionSlotMin': 30},
    });
    // Cita confirmada el domingo 8 de noviembre a las 10:00.
    await firestore.doc('appointments/a1').set({
      'clinicId': 'c1',
      'ownerNombre': 'Ana Pérez',
      'petNombre': 'Luna',
      'fecha': '2026-11-08',
      'hora': '10:00',
      'duracionMin': 30,
      'estado': 'confirmada',
      'inicio': Timestamp.fromDate(BogotaTime.at(2026, 11, 8, 10)),
    });
    await pumpPage(tester);

    // Cierra los domingos.
    await scrollTo(tester, find.widgetWithText(SwitchListTile, 'Domingo'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Domingo'));
    await tester.pump();
    await tapSave(tester);

    expect(find.text('Hay citas fuera del nuevo horario'), findsOneWidget);
    expect(find.text('Luna · Ana Pérez'), findsOneWidget);

    await tester.tap(find.text('Revisar horario'));
    await tester.pumpAndSettle();
    var data = (await firestore.doc('clinics/c1').get()).data()!;
    expect(data.containsKey('horarioSemanal'), isFalse);

    await tapSave(tester);
    await tester.tap(find.text('Guardar de todas formas'));
    await tester.pumpAndSettle();
    data = (await firestore.doc('clinics/c1').get()).data()!;
    expect((data['horarioSemanal'] as Map)['dom'], containsPair('abierto', false));
    // La cita se mantiene.
    expect((await firestore.doc('appointments/a1').get()).data()!['estado'], 'confirmada');
  });

  testWidgets('Cambio 2: un horario inválido no se puede guardar', (tester) async {
    await firestore.doc('clinics/c1').update({
      'estado': 'activo',
      'tiposAnimales': ['perros'],
      'horarioSemanal': {
        ...WeeklySchedule.standard.toMap(),
        // Descanso que no cuadra con franjas de 60 min.
        'lun': {'abierto': true, 'apertura': '08:00', 'cierre': '18:00',
          'descansoInicio': '12:30', 'descansoFin': '14:00'},
      },
      'reservas': {'duracionSlotMin': 30, 'anticipacionMaxDias': 30, 'anticipacionMinMin': 120},
    });
    await pumpPage(tester);
    expect(await isEnabled(tester), isTrue);

    await scrollTo(tester, find.text('60 min'));
    await tester.tap(find.text('60 min'));
    await tester.pump();
    expect(await isEnabled(tester), isFalse);
    await tester.scrollUntilVisible(find.text('Usa horas en bloques de 60 minutos'), -300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Usa horas en bloques de 60 minutos'), findsOneWidget);
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
