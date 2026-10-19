import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/medical_records_providers.dart';
import 'package:mascoti/core/domain/medical_record.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/presentation/medical_history_tab.dart';
import 'package:mascoti/plugins/mascotas/presentation/pets_providers.dart';

void main() {
  final opened = <Uri>[];

  setUp(opened.clear);

  Future<StreamController<List<MedicalRecord>>> pumpTab(
    WidgetTester tester, {
    List<MedicalRecord>? records,
    Object? error,
    FutureOr<String> Function(String path)? url,
  }) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = StreamController<List<MedicalRecord>>.broadcast();
    // Sin await: close() de un stream sin oyentes no termina nunca.
    addTearDown(() {
      controller.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          medicalRecordsProvider('p1').overrideWith((ref) => controller.stream),
          recordAttachmentUrlProvider.overrideWith(
            (ref, key) async => url == null ? throw Exception('sin enlace') : url(key.$2),
          ),
          externalUrlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: MedicalHistoryTab(petId: 'p1')),
        ),
      ),
    );
    if (records != null) controller.add(records);
    if (error != null) controller.addError(error);
    await tester.pump();
    return controller;
  }

  MedicalRecord record(
    String id,
    DateTime fecha, {
    String diagnostico = 'Control anual',
    String tratamiento = '',
    List<Vaccine> vacunas = const [],
    List<RecordAttachment> adjuntos = const [],
  }) =>
      MedicalRecord(
        id: id,
        petId: 'p1',
        clinicId: 'c1',
        clinicNombre: 'Vet Central',
        fecha: fecha,
        diagnostico: diagnostico,
        tratamiento: tratamiento,
        vacunas: vacunas,
        adjuntos: adjuntos,
      );

  const pdf = RecordAttachment(path: 'p1/r1/examen.pdf', tipo: AttachmentType.pdf, nombre: 'examen.pdf');
  const imagen =
      RecordAttachment(path: 'p1/r1/rx.jpg', tipo: AttachmentType.imagen, nombre: 'rx.jpg');

  testWidgets('sin registros muestra el estado vacío del RF', (tester) async {
    await pumpTab(tester, records: const []);
    expect(find.text('Esta mascota aún no tiene historial médico registrado'), findsOneWidget);
  });

  testWidgets('mientras carga muestra un indicador', (tester) async {
    await pumpTab(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error al cargar muestra "Reintentar"', (tester) async {
    await pumpTab(tester, error: Exception('permission-denied'));
    expect(find.text('No pudimos cargar el historial médico. Verifica tu conexión.'),
        findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('línea de tiempo: más reciente arriba y la tarjeta se expande', (tester) async {
    await pumpTab(tester, records: [
      record(
        'r2',
        DateTime(2026, 10, 1),
        diagnostico: 'Otitis externa',
        tratamiento: 'Gotas óticas cada 12 h',
        vacunas: [
          Vaccine(
            nombre: 'Rabia',
            lote: 'RB-1',
            fechaAplicacion: DateTime(2026, 10, 1),
            fechaProximaDosis: DateTime(2027, 10, 1),
          ),
          Vaccine(nombre: 'Parvovirus', lote: 'PV-9', fechaAplicacion: DateTime(2026, 10, 1)),
        ],
      ),
      record('r1', DateTime(2025, 3, 1), diagnostico: 'Gastroenteritis'),
    ]);

    final otitis = tester.getTopLeft(find.text('Otitis externa'));
    final gastro = tester.getTopLeft(find.text('Gastroenteritis'));
    expect(otitis.dy, lessThan(gastro.dy));
    expect(find.text('Vet Central'), findsNWidgets(2));
    expect(find.text('Gotas óticas cada 12 h'), findsNothing);

    await tester.tap(find.text('Otitis externa'));
    await tester.pumpAndSettle();

    expect(find.text('Gotas óticas cada 12 h'), findsOneWidget);
    expect(find.text('Rabia'), findsOneWidget);
    expect(find.textContaining('Lote RB-1 · Próxima dosis:'), findsOneWidget);
    expect(find.text('Lote PV-9'), findsOneWidget);
  });

  testWidgets('tiempo real: un registro nuevo aparece arriba sin refrescar', (tester) async {
    final controller = await pumpTab(tester, records: [
      record('r1', DateTime(2025, 3, 1), diagnostico: 'Gastroenteritis'),
    ]);

    controller.add([
      record('r2', DateTime(2026, 10, 1), diagnostico: 'Otitis externa'),
      record('r1', DateTime(2025, 3, 1), diagnostico: 'Gastroenteritis'),
    ]);
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Otitis externa')).dy,
      lessThan(tester.getTopLeft(find.text('Gastroenteritis')).dy),
    );
  });

  testWidgets(
      'un adjunto que falla muestra "Archivo no disponible" sin bloquear el resto',
      (tester) async {
    await pumpTab(
      tester,
      records: [
        record('r1', DateTime(2026, 10, 1),
            diagnostico: 'Cojera', tratamiento: 'Reposo', adjuntos: const [imagen, pdf]),
        record('r0', DateTime(2025, 1, 1), diagnostico: 'Gastroenteritis'),
      ],
      // La imagen falla; el PDF sí tiene enlace.
      url: (path) => path.endsWith('.jpg')
          ? throw Exception('404')
          : 'https://ejemplo.test/examen.pdf',
    );

    await tester.tap(find.text('Cojera'));
    await tester.pumpAndSettle();

    expect(find.text('Archivo no disponible'), findsOneWidget);
    expect(find.text('rx.jpg'), findsOneWidget);
    expect(find.byTooltip('Reintentar'), findsOneWidget);
    // El resto del historial sigue visible y el PDF se puede abrir.
    expect(find.text('Reposo'), findsOneWidget);
    expect(find.text('Gastroenteritis'), findsOneWidget);
    expect(find.text('PDF · toca para abrir o descargar'), findsOneWidget);

    await tester.tap(find.text('examen.pdf'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://ejemplo.test/examen.pdf')]);
  });
}
