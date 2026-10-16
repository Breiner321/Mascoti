import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/domain/clinic_service.dart';
import 'package:mascoti/plugins/clinica/data/services_repository.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_providers.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_services_page.dart';
import 'package:mascoti/plugins/clinica/presentation/service_card.dart';

/// Falla el primer guardado (como sin red) y deja pasar los siguientes.
class _FlakyRepository extends ServicesRepository {
  _FlakyRepository(FakeFirebaseFirestore firestore) : super(firestore: firestore);

  int attempts = 0;

  @override
  Future<void> save(String clinicId, ClinicService service, {required bool isNew}) {
    attempts++;
    if (attempts == 1) return Future.error(Exception('unavailable'));
    return super.save(clinicId, service, isNew: isNew);
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

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> pumpPage(WidgetTester tester, {ServicesRepository? repo}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(clinicUser),
          servicesRepositoryProvider
              .overrideWithValue(repo ?? ServicesRepository(firestore: firestore)),
        ],
        child: const MaterialApp(home: Scaffold(body: ClinicServicesPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addService(String id, String nombre, {int precio = 45000}) =>
      firestore.doc('clinics/c1/services/$id').set({
        'nombre': nombre,
        'categoria': 'bano',
        'descripcion': '',
        'precio': precio,
        'duracionMin': 30,
        'activo': true,
      });

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('estado vacío con el botón "+ Nuevo Servicio"', (tester) async {
    await pumpPage(tester);

    expect(find.text('Aún no tienes servicios. Agrega el primero'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Nuevo Servicio'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('lista los servicios activos con precio en COP', (tester) async {
    await addService('a', 'Baño medicado', precio: 45000);
    await firestore.doc('clinics/c1/services/b').set({
      'nombre': 'Inactivo',
      'categoria': 'otro',
      'precio': 1000,
      'duracionMin': 10,
      'activo': false,
    });
    await pumpPage(tester);

    expect(find.byType(ServiceCard), findsOneWidget);
    expect(find.text('Baño medicado'), findsOneWidget);
    expect(find.text(r'$ 45.000'), findsOneWidget);
    expect(find.text('Inactivo'), findsNothing);
  });

  testWidgets('el formulario muestra los errores y no guarda', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Nuevo Servicio'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Nombre del servicio'), 'ab');
    await tester.enterText(field('Precio'), '0');
    await tester.enterText(field('Duración'), '481');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('El nombre debe tener entre 3 y 60 caracteres'), findsOneWidget);
    expect(find.text('Selecciona una categoría'), findsOneWidget);
    expect(find.text('El precio debe ser mayor a 0'), findsOneWidget);
    expect(find.text('La duración debe ser un número entero entre 5 y 480 minutos'),
        findsOneWidget);
    expect((await firestore.collection('clinics/c1/services').get()).size, 0);
  });

  testWidgets('crear: guarda, cierra el formulario y muestra la tarjeta',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Nuevo Servicio'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Nombre del servicio'), 'Vacuna antirrábica');
    await tester.tap(find.text('Categoría'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vacunación').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Precio'), '45000');
    await tester.enterText(field('Duración'), '20');
    expect(find.text('45.000'), findsOneWidget, reason: 'puntos de miles al escribir');

    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    final docs = await firestore.collection('clinics/c1/services').get();
    expect(docs.size, 1);
    final data = docs.docs.single.data();
    expect(data['nombre'], 'Vacuna antirrábica');
    expect(data['categoria'], 'vacunacion');
    expect(data['precio'], 45000);
    expect(data['duracionMin'], 20);
    expect(data['activo'], isTrue);

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ServiceCard), findsOneWidget);
    expect(find.text(r'$ 45.000'), findsOneWidget);
    expect(find.text('Servicio creado'), findsOneWidget);
  });

  testWidgets('editar: el formulario viene precargado y dice "Actualizar"',
      (tester) async {
    await addService('a', 'Baño medicado', precio: 45000);
    await pumpPage(tester);

    await tester.tap(find.text('Baño medicado'));
    await tester.pumpAndSettle();

    expect(find.text('Editar servicio'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Baño medicado'), findsOneWidget);
    expect(find.text('45.000'), findsOneWidget);

    await tester.enterText(field('Precio'), '50000');
    await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
    await tester.pumpAndSettle();

    expect((await firestore.doc('clinics/c1/services/a').get()).data()!['precio'], 50000);
    expect(find.text(r'$ 50.000'), findsOneWidget);
    expect(find.text('Servicio actualizado'), findsOneWidget);
  });

  testWidgets('eliminar con la papelera: confirma y hace borrado lógico',
      (tester) async {
    await addService('a', 'Baño medicado');
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar "Baño medicado"? Se ocultará del catálogo.'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect((await firestore.doc('clinics/c1/services/a').get()).data()!['activo'], isFalse);
    expect(find.byType(ServiceCard), findsNothing);
    expect(find.text('Servicio eliminado'), findsOneWidget);
  });

  testWidgets('deslizar y cancelar no elimina', (tester) async {
    await addService('a', 'Baño medicado');
    await pumpPage(tester);

    await tester.drag(find.byType(ServiceCard), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect((await firestore.doc('clinics/c1/services/a').get()).data()!['activo'], isTrue);
    expect(find.byType(ServiceCard), findsOneWidget);
  });

  testWidgets('deslizar y confirmar elimina', (tester) async {
    await addService('a', 'Baño medicado');
    await pumpPage(tester);

    await tester.drag(find.byType(ServiceCard), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect((await firestore.doc('clinics/c1/services/a').get()).data()!['activo'], isFalse);
    expect(find.byType(ServiceCard), findsNothing);
    expect(find.text('Aún no tienes servicios. Agrega el primero'), findsOneWidget);
  });

  testWidgets('fallo de red: conserva los datos y permite reintentar', (tester) async {
    final repo = _FlakyRepository(firestore);
    await pumpPage(tester, repo: repo);
    await tester.tap(find.text('Nuevo Servicio'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Nombre del servicio'), 'Corte de uñas');
    await tester.tap(find.text('Categoría'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peluquería').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Precio'), '15000');
    await tester.enterText(field('Duración'), '15');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo guardar. Revisa tu conexión e inténtalo de nuevo.'),
        findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Corte de uñas'), findsOneWidget);
    expect(find.text('15.000'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(repo.attempts, 2);
    expect((await firestore.collection('clinics/c1/services').get()).size, 1);
    expect(find.text('Servicio creado'), findsOneWidget);
  });
}
