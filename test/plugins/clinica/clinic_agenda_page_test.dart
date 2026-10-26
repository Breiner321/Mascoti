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
import 'package:mascoti/plugins/clinica/clinica_routes.dart';
import 'package:mascoti/plugins/clinica/data/clinic_repository.dart';
import 'package:mascoti/plugins/clinica/data/services_repository.dart';
import 'package:mascoti/plugins/clinica/data/slots_repository.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_agenda_page.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_providers.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  const clinicUser = AppUser(
    uid: 'vet',
    email: 'vet@correo.co',
    displayName: 'Vet',
    role: UserRole.clinica,
    clinicId: 'c1',
  );

  /// "Hoy" en las pruebas: martes 20 de octubre de 2026, 08:45.
  final now = DateTime(2026, 10, 20, 8, 45);
  const fecha = '2026-10-20';

  setUpAll(() => initializeDateFormatting('es'));

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('clinics/c1').set({
      'ownerUid': 'vet',
      'nombre': 'Vet Central',
      'estado': 'activo',
      'tiposAnimales': ['perros'],
      'horarioBase': {'apertura': '08:00', 'cierre': '12:00', 'duracionSlotMin': 30},
    });
  });

  Future<void> addService(String id, String nombre, int duracion, int precio) =>
      firestore.doc('clinics/c1/services/$id').set({
        'nombre': nombre,
        'categoria': 'consulta_general',
        'descripcion': '',
        'precio': precio,
        'duracionMin': duracion,
        'activo': true,
      });

  Future<void> addSlot(String hora, String estado, {String? serviceId, int? precio}) =>
      firestore.doc('clinics/c1/slots/${fecha}_$hora').set({
        'fecha': fecha,
        'hora': hora,
        'inicio': Timestamp.fromDate(DateTime.parse('${fecha}T$hora:00')),
        'estado': estado,
        'serviceId': serviceId,
        'precio': precio,
      });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
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
          servicesRepositoryProvider
              .overrideWithValue(ServicesRepository(firestore: firestore)),
          slotsRepositoryProvider.overrideWithValue(SlotsRepository(firestore: firestore)),
          agendaClockProvider.overrideWithValue(() => now),
          appointmentsRepositoryProvider
              .overrideWithValue(AppointmentsRepository(firestore: firestore)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Botón (de cualquier tipo de ButtonStyleButton) con el texto [label].
  Finder button(String label) => find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<ButtonStyleButton>(),
      );

  Finder franja(String hora) => find.byKey(ValueKey('franja-$hora'));

  Future<Map<String, dynamic>?> slotDoc(String hora) async =>
      (await firestore.doc('clinics/c1/slots/${fecha}_$hora').get()).data();

  testWidgets('sin servicios activos: estado vacío con botón a Servicios', (tester) async {
    await pumpPage(tester);

    expect(find.text('Para abrir tu agenda primero agrega al menos un servicio.'),
        findsOneWidget);
    await tester.tap(find.text('Ir a Servicios'));
    await tester.pumpAndSettle();
    expect(find.text('Pantalla servicios'), findsOneWidget);
  });

  testWidgets('muestra el día de hoy, el calendario y las franjas por estado',
      (tester) async {
    await addService('s1', 'Consulta general', 30, 45000);
    await addSlot('09:00', 'disponible', serviceId: 's1', precio: 45000);
    await addSlot('10:00', 'no_disponible');
    await addSlot('11:00', 'ocupado', serviceId: 's1', precio: 45000);
    await pumpPage(tester);

    expect(find.text('Mi día'), findsOneWidget);
    expect(find.text('Martes 20 de octubre'), findsOneWidget);
    expect(find.text('Octubre 2026'), findsOneWidget);
    expect(find.text('Franjas del 20 de octubre'), findsOneWidget);

    expect(find.descendant(of: franja('09:00'), matching: find.text(r'Consulta general · $ 45.000')),
        findsOneWidget);
    expect(find.descendant(of: franja('10:00'), matching: find.text('No disponible')),
        findsOneWidget);
    expect(find.descendant(of: franja('11:00'), matching: find.text('Ocupado')),
        findsOneWidget);
    expect(find.descendant(of: franja('11:30'), matching: find.text('Sin configurar')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('franja-08:00')), findsOneWidget);
  });

  testWidgets('una franja ocupada es de solo lectura (mensaje del RF)', (tester) async {
    await addService('s1', 'Consulta general', 30, 45000);
    await addSlot('11:00', 'ocupado', serviceId: 's1', precio: 45000);
    await pumpPage(tester);

    await tester.tap(franja('11:00'));
    await tester.pump();

    expect(
      find.text('No puedes modificar un horario con una cita confirmada. Cancela la cita primero'),
      findsOneWidget,
    );
    expect(find.text('1 franja seleccionada'), findsNothing);
  });

  testWidgets('RF-14: la franja reservada muestra la cita y abre su detalle; '
      'aparece en "Próximas citas"', (tester) async {
    await addService('s1', 'Consulta general', 30, 45000);
    await addSlot('11:00', 'ocupado', serviceId: 's1', precio: 45000);
    await firestore.doc('appointments/a1').set({
      'clinicId': 'c1',
      'petId': 'p1',
      'petNombre': 'Luna',
      'serviceId': 's1',
      'serviceNombre': 'Consulta general',
      'slotId': '${fecha}_11:00',
      'fecha': fecha,
      'hora': '11:00',
      // 11:00 a. m. en Bogotá.
      'inicio': Timestamp.fromDate(DateTime.utc(2026, 10, 20, 16)),
      'estado': 'confirmada',
    });
    await pumpPage(tester);

    expect(find.text('Próximas citas'), findsOneWidget);
    expect(find.text('11:00 a. m. · Luna'), findsOneWidget);
    expect(
      find.descendant(of: franja('11:00'), matching: find.text('Luna · Consulta general')),
      findsOneWidget,
    );

    await tester.tap(franja('11:00'));
    await tester.pumpAndSettle();
    expect(find.text('Cita a1'), findsOneWidget);
  });

  testWidgets('sin citas hoy ni mañana: "Próximas citas" lo dice', (tester) async {
    await addService('s1', 'Consulta general', 30, 45000);
    await pumpPage(tester);
    expect(find.text('No tienes citas para hoy ni para mañana.'), findsOneWidget);
  });

  testWidgets('una franja que ya pasó no se puede editar', (tester) async {
    await addService('s1', 'Consulta general', 30, 45000);
    await pumpPage(tester);

    await tester.tap(franja('08:00'));
    await tester.pump();
    expect(find.text('Este horario ya pasó; no se puede modificar.'), findsOneWidget);
  });

  testWidgets('seleccionar varias, marcarlas disponibles y guardar en lote', (tester) async {
    await addService('s1', 'Consulta general', 30, 45000);
    await pumpPage(tester);

    await tester.tap(franja('09:00'));
    await tester.tap(franja('09:30'));
    await tester.pump();
    expect(find.text('2 franjas seleccionadas'), findsOneWidget);

    await tester.tap(button('Disponible'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Consulta general · $ 45.000 · 30 min').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(await slotDoc('09:00'), isNull, reason: 'aún es borrador');
    expect(find.text('Guardar Disponibilidad (2)'), findsOneWidget);

    await tester.tap(find.text('Guardar Disponibilidad (2)'));
    await tester.pumpAndSettle();

    for (final hora in ['09:00', '09:30']) {
      final data = (await slotDoc(hora))!;
      expect(data['estado'], 'disponible');
      expect(data['serviceId'], 's1');
      expect(data['precio'], 45000);
    }
    expect(find.text('Disponibilidad guardada'), findsOneWidget);
    expect(find.text('Guardar Disponibilidad'), findsOneWidget);
  });

  testWidgets('marcar "No disponible" sin servicio', (tester) async {
    await addService('s1', 'Consulta general', 30, 45000);
    await pumpPage(tester);

    await tester.tap(franja('10:00'));
    await tester.pump();
    await tester.tap(button('No disponible'));
    await tester.pump();
    await tester.tap(find.text('Guardar Disponibilidad (1)'));
    await tester.pumpAndSettle();

    final data = (await slotDoc('10:00'))!;
    expect(data['estado'], 'no_disponible');
    expect(data['serviceId'], isNull);
  });

  testWidgets('un solapamiento bloquea el guardado', (tester) async {
    await addService('s2', 'Cirugía', 60, 200000);
    await addSlot('11:30', 'no_disponible');
    await pumpPage(tester);

    await tester.tap(franja('11:00'));
    await tester.pump();
    await tester.tap(button('Disponible'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Cirugía · $ 200.000 · 60 min').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Hay franjas que se solapan o terminan después del cierre'),
      findsOneWidget,
    );
    final save = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Guardar Disponibilidad (1)'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(save.onPressed, isNull);
    expect(await slotDoc('11:00'), isNull);
  });

  testWidgets('quitar una franja guardada la borra', (tester) async {
    await addService('s1', 'Consulta general', 30, 45000);
    await addSlot('10:00', 'no_disponible');
    await pumpPage(tester);

    await tester.tap(franja('10:00'));
    await tester.pump();
    await tester.tap(find.text('Quitar'));
    await tester.pump();
    await tester.tap(find.text('Guardar Disponibilidad (1)'));
    await tester.pumpAndSettle();

    expect(await slotDoc('10:00'), isNull);
  });
}
