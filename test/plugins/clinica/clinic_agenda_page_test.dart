import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/appointments_providers.dart';
import 'package:mascoti/core/data/appointments_repository.dart';
import 'package:mascoti/core/format/bogota_time.dart';
import 'package:mascoti/plugins/clinica/clinica_routes.dart';
import 'package:mascoti/plugins/clinica/data/clinic_repository.dart';
import 'package:mascoti/plugins/clinica/data/exceptions_repository.dart';
import 'package:mascoti/plugins/clinica/data/services_repository.dart';
import 'package:mascoti/plugins/clinica/data/slots_repository.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_agenda_page.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_providers.dart';

import '../../a11y.dart';

/// Agenda de la clínica por EXCEPCIONES (Cambio 2).
void main() {
  late FakeFirebaseFirestore firestore;

  const clinicUser = AppUser(
    uid: 'vet',
    email: 'vet@correo.co',
    displayName: 'Vet',
    role: UserRole.clinica,
    clinicId: 'c1',
  );

  /// "Hoy" en las pruebas: martes 20 de octubre de 2026, 8:45 a. m. en Bogotá.
  final now = BogotaTime.at(2026, 10, 20, 8, 45);
  const fecha = '2026-10-20';

  setUpAll(() => initializeDateFormatting('es'));

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    // Clínica sin migrar: horarioBase de 8 a 12 todos los días, franjas de 30.
    await firestore.doc('clinics/c1').set({
      'ownerUid': 'vet',
      'nombre': 'Vet Central',
      'estado': 'activo',
      'tiposAnimales': ['perros'],
      'horarioBase': {'apertura': '08:00', 'cierre': '12:00', 'duracionSlotMin': 30},
    });
  });

  Future<void> addService() => firestore.doc('clinics/c1/services/s1').set({
        'nombre': 'Consulta',
        'categoria': 'consulta_general',
        'descripcion': '',
        'precio': 45000,
        'duracionMin': 30,
        'activo': true,
      });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: ClinicaRoutes.agenda,
      routes: [
        GoRoute(
          path: ClinicaRoutes.agenda,
          builder: (context, state) => const Scaffold(body: ClinicAgendaPage()),
        ),
        GoRoute(
          path: ClinicaRoutes.services,
          builder: (context, state) => const Scaffold(body: Text('Pantalla servicios')),
        ),
        GoRoute(
          path: '/reservas/:id',
          builder: (context, state) => Scaffold(body: Text('Cita ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(clinicUser),
          clinicRepositoryProvider.overrideWithValue(ClinicRepository(firestore: firestore)),
          servicesRepositoryProvider.overrideWithValue(ServicesRepository(firestore: firestore)),
          slotsRepositoryProvider.overrideWithValue(SlotsRepository(firestore: firestore)),
          exceptionsRepositoryProvider
              .overrideWithValue(ExceptionsRepository(firestore: firestore)),
          agendaClockProvider.overrideWithValue(() => now),
          appointmentsRepositoryProvider
              .overrideWithValue(AppointmentsRepository(firestore: firestore)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder franja(String hora) => find.byKey(ValueKey('franja-$hora'));

  Finder inFranja(String hora, String text) =>
      find.descendant(of: franja(hora), matching: find.text(text));

  Future<List<Map<String, dynamic>>> exceptions() async =>
      [for (final d in (await firestore.collection('clinics/c1/excepciones').get()).docs) d.data()];

  testWidgets('sin servicios activos: estado vacío con botón a Servicios', (tester) async {
    await pumpPage(tester);
    expect(find.text('Para abrir tu agenda primero agrega al menos un servicio.'), findsOneWidget);
    await tester.tap(find.text('Ir a Servicios'));
    await tester.pumpAndSettle();
    expect(find.text('Pantalla servicios'), findsOneWidget);
  });

  testWidgets('sin horario configurado pide configurarlo', (tester) async {
    await firestore.doc('clinics/c1').update({'horarioBase': FieldValue.delete()});
    await addService();
    await pumpPage(tester);
    expect(find.text('Configura tu horario semanal para empezar a recibir citas.'), findsOneWidget);
  });

  testWidgets('disponible por defecto: todas las franjas del horario están libres', (tester) async {
    await addService();
    await pumpPage(tester);

    expect(find.text('Mi día'), findsOneWidget);
    for (final h in ['08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30']) {
      expect(franja(h), findsOneWidget, reason: h);
    }
    expect(franja('12:00'), findsNothing);
    expect(inFranja('09:00', 'Libre'), findsOneWidget);
    expect(find.text('Bloquear día'), findsOneWidget);
    expect(find.text('Abrir horario extra'), findsOneWidget);
  });

  testWidgets('sugiere los próximos festivos de Colombia', (tester) async {
    await addService();
    await pumpPage(tester);

    expect(find.text('Próximos festivos'), findsOneWidget);
    expect(find.text('2 de noviembre · Todos los Santos'), findsOneWidget);

    await tester.tap(find.text('2 de noviembre · Todos los Santos'));
    await tester.pumpAndSettle();
    // El motivo viene prellenado con el nombre del festivo.
    expect(find.widgetWithText(TextField, 'Todos los Santos'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Bloquear'));
    await tester.pumpAndSettle();

    final saved = await exceptions();
    expect(saved.single, containsPair('fechaInicio', '2026-11-02'));
    expect(saved.single['fechaFin'], '2026-11-02');
    expect(saved.single['motivo'], 'Todos los Santos');
    expect(saved.single.containsKey('desde'), isFalse);
    // Ya bloqueado, deja de sugerirse.
    expect(find.text('2 de noviembre · Todos los Santos'), findsNothing);
  });

  testWidgets('seleccionar franjas y bloquearlas: un rango por cada grupo seguido', (tester) async {
    await addService();
    await pumpPage(tester);

    for (final h in ['09:30', '10:00', '11:00']) {
      await tester.tap(franja(h));
      await tester.pump();
    }
    expect(inFranja('10:00', 'Seleccionada'), findsOneWidget);
    await tester.tap(find.text('Bloquear 3 franjas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Capacitación');
    await tester.tap(find.widgetWithText(FilledButton, 'Bloquear'));
    await tester.pumpAndSettle();

    final saved = await exceptions();
    expect(
      saved.map((e) => '${e['desde']}-${e['hasta']}').toSet(),
      {'09:30-10:30', '11:00-11:30'},
    );
    expect(saved.every((e) => e['tipo'] == 'bloqueo' && e['fechaInicio'] == fecha), isTrue);
    expect(inFranja('10:00', 'Bloqueada · Capacitación'), findsOneWidget);
    expect(inFranja('09:00', 'Libre'), findsOneWidget);
  });

  testWidgets('tocar una franja bloqueada permite quitar el bloqueo', (tester) async {
    await addService();
    await firestore.doc('clinics/c1/excepciones/x1').set({
      'tipo': 'bloqueo',
      'fechaInicio': fecha,
      'fechaFin': fecha,
      'desde': '10:00',
      'hasta': '11:00',
    });
    await pumpPage(tester);

    expect(inFranja('10:30', 'Bloqueada'), findsOneWidget);
    await tester.tap(franja('10:30'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Se vuelve a abrir'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Quitar bloqueo'));
    await tester.pumpAndSettle();

    expect(await exceptions(), isEmpty);
    expect(inFranja('10:30', 'Libre'), findsOneWidget);
  });

  testWidgets('bloquear el día completo y desbloquearlo', (tester) async {
    await addService();
    await pumpPage(tester);

    await tester.tap(find.text('Bloquear día'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Bloquear'));
    await tester.pumpAndSettle();

    expect(find.text('Día bloqueado'), findsOneWidget);
    expect(inFranja('09:00', 'Bloqueada'), findsOneWidget);
    await tester.tap(find.text('Desbloquear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Quitar bloqueo'));
    await tester.pumpAndSettle();
    expect(find.text('Día bloqueado'), findsNothing);
  });

  testWidgets('una franja que ya pasó no se puede seleccionar', (tester) async {
    await addService();
    await pumpPage(tester);
    await tester.tap(franja('08:00'));
    await tester.pump();
    expect(find.text('Este horario ya pasó; no se puede modificar.'), findsOneWidget);
    expect(find.textContaining('Bloquear 1'), findsNothing);
  });

  testWidgets('una franja con cita muestra la mascota y abre el detalle', (tester) async {
    await addService();
    // Cita de 60 min: aparta 2 franjas.
    for (final h in ['09:00', '09:30']) {
      await firestore.doc('clinics/c1/slots/${fecha}_$h').set({
        'fecha': fecha,
        'hora': h,
        'inicio': Timestamp.fromDate(BogotaTime.tryParse(fecha, h)!),
        'estado': 'reservado_temporal',
        'appointmentId': 'a1',
      });
    }
    await firestore.doc('appointments/a1').set({
      'clinicId': 'c1',
      'ownerUid': 'ana',
      'petNombre': 'Luna',
      'serviceNombre': 'Cirugía',
      'fecha': fecha,
      'hora': '09:00',
      'slotId': '${fecha}_09:00',
      'slotIds': ['${fecha}_09:00', '${fecha}_09:30'],
      'estado': 'pendiente',
      'inicio': Timestamp.fromDate(BogotaTime.at(2026, 10, 20, 9)),
    });
    await pumpPage(tester);

    expect(inFranja('09:00', 'Luna · Pendiente'), findsOneWidget);
    expect(inFranja('09:30', 'Luna · Pendiente'), findsOneWidget);
    await tester.tap(franja('09:30'));
    await tester.pumpAndSettle();
    expect(find.text('Cita a1'), findsOneWidget);
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await addService();
      await pumpPage(tester);
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      useLargeText(tester);
      await addService();
      await pumpPage(tester);
      expectNoOverflow(tester);
    });
  });
}
