import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/appointments_providers.dart';
import 'package:mascoti/core/domain/appointment.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/reservas/presentation/clinica/clinic_requests_page.dart';
import 'package:mascoti/plugins/reservas/presentation/clinica/clinic_requests_providers.dart';

import '../../a11y.dart';

const _vet = AppUser(
  uid: 'vet',
  email: 'vet@example.com',
  displayName: 'Clínica Norte',
  role: UserRole.clinica,
  clinicId: 'c1',
);

Appointment _pending(String id, String pet, DateTime inicio, {String comentario = ''}) =>
    Appointment(
      id: id,
      clinicId: 'c1',
      clinicNombre: 'Clínica Norte',
      ownerUid: 'ana',
      ownerNombre: 'Ana Pérez',
      petId: 'p-$id',
      petNombre: pet,
      serviceId: 's1',
      serviceNombre: 'Consulta general',
      precioAcordado: 45000,
      slotId: 'x',
      fecha: '2026-11-03',
      hora: '09:00',
      inicio: inicio,
      comentario: comentario,
      estado: AppointmentStatus.pendiente,
    );

void main() {
  Future<ProviderContainer> pump(WidgetTester tester, Stream<List<Appointment>> requests) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: ClinicRequestsPage())),
      GoRoute(
        path: '/reservas/:id',
        builder: (_, state) => Text('detalle ${state.pathParameters['id']}'),
      ),
    ]);
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(_vet),
      pendingRequestsProvider('c1').overrideWith((ref) => requests),
      clinicPetProvider.overrideWith(
        (ref, petId) => Stream.value(
          Pet(id: petId, ownerUid: 'ana', nombre: 'x', especie: PetSpecies.gato),
        ),
      ),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('sin solicitudes muestra el estado vacío', (tester) async {
    await pump(tester, Stream.value(const []));
    expect(find.text(ClinicRequestsPage.emptyTitle), findsOneWidget);
  });

  testWidgets('tarjetas con mascota, especie, dueño, servicio y comentario; contador',
      (tester) async {
    final container = await pump(
      tester,
      Stream.value([
        _pending('a1', 'Luna', DateTime.utc(2026, 11, 3, 14), comentario: 'Vómito desde ayer'),
        _pending('a2', 'Milo', DateTime.utc(2026, 11, 4, 15)),
      ]),
    );

    expect(find.text('Luna'), findsOneWidget);
    expect(find.text('Milo'), findsOneWidget);
    expect(find.text('Gato · Dueño: Ana Pérez'), findsNWidgets(2));
    expect(find.text('Consulta general'), findsNWidgets(2));
    expect(find.text('“Vómito desde ayer”'), findsOneWidget);
    expect(find.text('2 citas por responder'), findsOneWidget);
    expect(container.read(pendingRequestsCountProvider), 2);

    await tester.tap(find.text('Luna'));
    await tester.pumpAndSettle();
    expect(find.text('detalle a1'), findsOneWidget);
  });

  testWidgets('error al cargar ofrece "Reintentar"', (tester) async {
    await pump(tester, Stream.error(Exception('sin conexión')));
    expect(find.text('No pudimos cargar las solicitudes'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste', (tester) async {
      await pump(tester, Stream.value([
        _pending('a1', 'Luna', DateTime.utc(2026, 11, 3, 14), comentario: 'Vómito desde ayer'),
      ]));
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes', (tester) async {
      useLargeText(tester);
      await pump(tester, Stream.value([
        _pending('a1', 'Luna', DateTime.utc(2026, 11, 3, 14), comentario: 'Vómito desde ayer'),
      ]));
      expectNoOverflow(tester);
    });
  });
}
