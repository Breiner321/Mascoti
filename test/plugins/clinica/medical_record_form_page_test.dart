import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/medical_records_providers.dart';
import 'package:mascoti/core/data/medical_records_repository.dart';
import 'package:mascoti/core/domain/medical_record.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/plugins/clinica/data/attachment_picker.dart';
import 'package:mascoti/plugins/clinica/data/clinic_repository.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_providers.dart';
import 'package:mascoti/plugins/clinica/presentation/medical_record_form_page.dart';

/// Historial sobre Firestore falso; los adjuntos se "suben" en memoria y
/// pueden fallar las primeras [failUploads] veces.
class _FakeRecordsRepository extends MedicalRecordsRepository {
  _FakeRecordsRepository(FakeFirebaseFirestore firestore) : super(firestore: firestore);

  int failUploads = 0;
  final uploads = <String>[];

  @override
  Future<RecordAttachment> uploadAttachment({
    required String petId,
    required String recordId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (failUploads > 0) {
      failUploads--;
      throw MedicalRecordFailure.network;
    }
    uploads.add(fileName);
    return RecordAttachment(
      path: '$petId/$recordId/a${uploads.length}.pdf',
      tipo: AttachmentType.pdf,
      nombre: fileName,
    );
  }
}

class _FakePicker extends AttachmentPicker {
  _FakePicker(this.file);

  final PickedFile? file;

  @override
  Future<PickedFile?> pick() async => file;
}

void main() {
  late FakeFirebaseFirestore firestore;
  late _FakeRecordsRepository repository;

  final now = DateTime(2026, 10, 16, 10);
  const pet = Pet(id: 'p1', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.gato);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repository = _FakeRecordsRepository(firestore);
    await firestore.doc('clinics/c1').set({'ownerUid': 'vet', 'nombre': 'Vet Feliz'});
  });

  /// Abre el formulario desde una pantalla de inicio (al guardar, vuelve).
  Future<void> pumpForm(
    WidgetTester tester, {
    MedicalRecord? existing,
    PickedFile? picked,
  }) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          medicalRecordsRepositoryProvider.overrideWithValue(repository),
          clinicRepositoryProvider.overrideWithValue(ClinicRepository(firestore: firestore)),
          recordsClockProvider.overrideWithValue(() => now),
          attachmentPickerProvider.overrideWithValue(_FakePicker(picked)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => MedicalRecordForm(pet: pet, clinicId: 'c1', existing: existing),
                )),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> savedRecords() async =>
      (await firestore.collection('pets/p1/medicalRecords').get()).docs;

  testWidgets('valida diagnóstico y vacunas, y guarda la consulta', (tester) async {
    await pumpForm(tester);
    expect(find.text('16/10/2026'), findsOneWidget); // hoy por defecto

    await tester.tap(find.text('Agregar vacuna'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar consulta'));
    await tester.pumpAndSettle();

    expect(find.text('El diagnóstico es obligatorio'), findsOneWidget);
    expect(find.text('El nombre de la vacuna es obligatorio'), findsOneWidget);
    expect(find.text('El lote es obligatorio'), findsOneWidget);
    expect(await savedRecords(), isEmpty);

    await tester.enterText(field('Diagnóstico *'), 'Otitis externa');
    await tester.enterText(field('Tratamiento'), 'Gotas cada 12 h');
    await tester.enterText(field('Nombre de la vacuna'), 'Triple felina');
    await tester.enterText(field('Lote'), 'L-2026');
    await tester.tap(find.text('Guardar consulta'));
    await tester.pumpAndSettle();

    final docs = await savedRecords();
    expect(docs, hasLength(1));
    final data = docs.single.data();
    expect(data['clinicId'], 'c1');
    expect(data['clinicNombre'], 'Vet Feliz');
    expect(data['diagnostico'], 'Otitis externa');
    expect(data['tratamiento'], 'Gotas cada 12 h');
    expect((data['fecha'] as Timestamp).toDate(), now);
    final vacunas = data['vacunas'] as List;
    expect(vacunas.single['nombre'], 'Triple felina');
    expect(vacunas.single['lote'], 'L-2026');
    expect(data['createdAt'], isNotNull);
    expect(find.text('Consulta guardada'), findsOneWidget);
    expect(find.byType(MedicalRecordForm), findsNothing);
  });

  testWidgets('quitar una vacuna la saca del formulario', (tester) async {
    await pumpForm(tester);
    await tester.tap(find.text('Agregar vacuna'));
    await tester.pumpAndSettle();
    expect(find.text('Vacuna 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar vacuna'));
    await tester.pumpAndSettle();
    expect(find.text('Vacuna 1'), findsNothing);
    expect(find.text('Sin vacunas en esta consulta'), findsOneWidget);
  });

  testWidgets('adjunto: si falla la subida se reintenta y luego se guarda', (tester) async {
    repository.failUploads = 1;
    await pumpForm(tester, picked: PickedFile(name: 'rx.pdf', bytes: Uint8List(100)));

    await tester.tap(find.text('Adjuntar'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo conectar. Verifica tu conexión'), findsOneWidget);

    await tester.enterText(field('Diagnóstico *'), 'Fractura');
    await tester.tap(find.text('Guardar consulta'));
    await tester.pumpAndSettle();
    expect(find.text('Reintenta o quita los adjuntos que no se subieron'), findsOneWidget);
    expect(await savedRecords(), isEmpty);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('PDF'), findsOneWidget);

    await tester.tap(find.text('Guardar consulta'));
    await tester.pumpAndSettle();
    final adjuntos = (await savedRecords()).single.data()['adjuntos'] as List;
    expect(adjuntos.single['nombre'], 'rx.pdf');
    expect(adjuntos.single['tipo'], 'pdf');
  });

  testWidgets('rechaza archivos de más de 10 MB sin subirlos', (tester) async {
    await pumpForm(
      tester,
      picked: PickedFile(
        name: 'tac.pdf',
        bytes: Uint8List(MedicalRecordLimits.maxAdjuntoBytes + 1),
      ),
    );

    await tester.tap(find.text('Adjuntar'));
    await tester.pumpAndSettle();

    expect(find.text('El archivo supera el máximo de 10 MB.'), findsOneWidget);
    expect(repository.uploads, isEmpty);
    expect(find.text('Sin adjuntos'), findsOneWidget);
  });

  MedicalRecord existingRecord(DateTime createdAt, {String clinicId = 'c1'}) => MedicalRecord(
        id: 'r1',
        petId: 'p1',
        clinicId: clinicId,
        clinicNombre: 'Vet Feliz',
        fecha: createdAt,
        diagnostico: 'Otitis',
        createdAt: createdAt,
      );

  Future<void> seed(MedicalRecord record) => firestore.doc('pets/p1/medicalRecords/r1').set({
        ...record.toMap(),
        'createdAt': Timestamp.fromDate(record.createdAt!),
      });

  testWidgets('dentro de las 24 h la clínica autora corrige la consulta', (tester) async {
    final record = existingRecord(now.subtract(const Duration(hours: 2)));
    await seed(record);
    await pumpForm(tester, existing: record);

    expect(find.textContaining('Solo lectura'), findsNothing);
    await tester.enterText(field('Diagnóstico *'), 'Otitis bilateral');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    final data = (await savedRecords()).single.data();
    expect(data['diagnostico'], 'Otitis bilateral');
    expect(data['updatedAt'], isNotNull);
    expect(find.text('Consulta actualizada'), findsOneWidget);
  });

  testWidgets('después de 24 h la consulta es de solo lectura', (tester) async {
    final record = existingRecord(now.subtract(const Duration(hours: 25)));
    await pumpForm(tester, existing: record);

    expect(find.textContaining('Solo lectura: las consultas se pueden corregir'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsNothing);
    expect(find.text('Agregar vacuna'), findsNothing);
    expect(find.text('Adjuntar'), findsNothing);
    final diagnostico = tester.widget<TextFormField>(field('Diagnóstico *'));
    expect(diagnostico.enabled, isFalse);
  });

  testWidgets('la consulta de otra clínica es de solo lectura', (tester) async {
    final record = existingRecord(now.subtract(const Duration(hours: 1)), clinicId: 'c2');
    await pumpForm(tester, existing: record);

    expect(find.text('Registrada por otra clínica: solo lectura.'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsNothing);
  });
}
