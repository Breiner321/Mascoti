import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/medical_records_repository.dart';
import 'package:mascoti/core/domain/medical_record.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockFunctions extends Mock implements FunctionsClient {}

class _MockStorage extends Mock implements SupabaseStorageClient {}

class _MockFiles extends Mock implements StorageFileApi {}

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockFunctions functions;
  late _MockStorage storage;
  late _MockFiles files;
  late MedicalRecordsRepository repository;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const FileOptions());
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
    functions = _MockFunctions();
    storage = _MockStorage();
    files = _MockFiles();
    when(() => storage.from('registros')).thenReturn(files);
    repository = MedicalRecordsRepository(
      firestore: firestore,
      functions: functions,
      storage: storage,
    );
  });

  final aplicada = DateTime(2026, 10, 10, 10);
  final refuerzo = DateTime(2027, 10, 10, 10);

  MedicalRecord record({
    String id = 'r1',
    DateTime? fecha,
    List<Vaccine>? vacunas,
  }) =>
      MedicalRecord(
        id: id,
        petId: 'p6',
        clinicId: 'c2',
        clinicNombre: 'Vet 2',
        fecha: fecha ?? DateTime(2026, 10, 10, 10),
        diagnostico: 'Control anual',
        tratamiento: 'Ninguno',
        vacunas: vacunas ??
            [
              Vaccine(nombre: 'Rabia', lote: 'L-1', fechaAplicacion: aplicada,
                  fechaProximaDosis: refuerzo),
              Vaccine(nombre: 'Moquillo', lote: 'L-2', fechaAplicacion: aplicada),
            ],
      );

  Future<Map<String, dynamic>?> data(String path) async => (await firestore.doc(path).get()).data();

  group('registros', () {
    test('crear guarda el registro y una próxima dosis por vacuna con refuerzo', () async {
      await repository.createRecord(record(), ownerUid: 'ana');

      final saved = (await data('pets/p6/medicalRecords/r1'))!;
      expect(saved['diagnostico'], 'Control anual');
      expect(saved['createdAt'], isA<Timestamp>());
      expect((saved['vacunas'] as List).length, 2);

      final dosis = (await data('vacunasProgramadas/r1_0'))!;
      expect(dosis['vacuna'], 'Rabia');
      expect(dosis['ownerUid'], 'ana');
      expect(dosis['clinicId'], 'c2');
      expect(dosis['notificado'], isFalse);
      expect((dosis['fechaProximaDosis'] as Timestamp).toDate(), refuerzo);
      // Moquillo no tiene refuerzo.
      expect(await data('vacunasProgramadas/r1_1'), isNull);
    });

    test('corregir quita la próxima dosis que ya no aplica', () async {
      final original = record();
      await repository.createRecord(original, ownerUid: 'ana');

      final corregido = original.copyWith(
        diagnostico: 'Control anual (corregido)',
        vacunas: [Vaccine(nombre: 'Rabia', lote: 'L-1', fechaAplicacion: aplicada)],
      );
      await repository.updateRecord(corregido, previous: original, ownerUid: 'ana');

      final saved = (await data('pets/p6/medicalRecords/r1'))!;
      expect(saved['diagnostico'], 'Control anual (corregido)');
      expect(saved['updatedAt'], isA<Timestamp>());
      expect(await data('vacunasProgramadas/r1_0'), isNull);
    });

    test('el timeline viene del más reciente al más antiguo', () async {
      await repository.createRecord(record(id: 'viejo', fecha: DateTime(2025, 1, 1)), ownerUid: 'ana');
      await repository.createRecord(record(id: 'nuevo', fecha: DateTime(2026, 9, 1)), ownerUid: 'ana');

      final timeline = await repository.watchRecords('p6').first;
      expect(timeline.map((r) => r.id), ['nuevo', 'viejo']);
      expect(timeline.first.vacunas.first.nombre, 'Rabia');
      expect(timeline.first.isEditable(DateTime.now()), isTrue);
    });

    test('tiempo real: un registro nuevo aparece arriba con el timeline abierto', () async {
      await repository.createRecord(record(id: 'viejo', fecha: DateTime(2025, 1, 1)), ownerUid: 'ana');
      final emissions = <List<String>>[];
      final sub = repository
          .watchRecords('p6')
          .listen((records) => emissions.add([for (final r in records) r.id]));
      await pumpEventQueue();

      await repository.createRecord(record(id: 'nuevo', fecha: DateTime(2026, 9, 1)), ownerUid: 'ana');
      await pumpEventQueue();
      await sub.cancel();

      expect(emissions.first, ['viejo']);
      expect(emissions.last, ['nuevo', 'viejo']);
    });

    test('el timeline es solo de la mascota pedida', () async {
      await repository.createRecord(record(id: 'mio'), ownerUid: 'ana');
      await firestore.collection('pets/otra/medicalRecords').doc('ajeno').set({
        ...record(id: 'ajeno').toMap(),
      });

      expect((await repository.watchRecords('p6').first).map((r) => r.id), ['mio']);
      expect(await repository.watchRecords('sin-historial').first, isEmpty);
    });

    test('próximas dosis del dueño ordenadas por fecha', () async {
      await repository.createRecord(record(id: 'r1'), ownerUid: 'ana');
      await repository.createRecord(
        record(id: 'r2', vacunas: [
          Vaccine(nombre: 'Leptospira', lote: 'L-9', fechaAplicacion: aplicada,
              fechaProximaDosis: DateTime(2027, 1, 1)),
        ]),
        ownerUid: 'ana',
      );

      final dosis = await repository.watchScheduledVaccines('ana').first;
      expect(dosis.map((d) => d.vacuna), ['Leptospira', 'Rabia']);
    });
  });

  group('adjuntos', () {
    test('pide el enlace de subida y sube el archivo al bucket registros', () async {
      when(() => functions.invoke('adjuntos-historial', body: any(named: 'body'))).thenAnswer(
        (_) async => const FunctionResponse(
          status: 200,
          data: {'path': 'p6/r1/ARCH1.pdf', 'token': 'tok', 'tipo': 'pdf'},
        ),
      );
      when(() => files.uploadBinaryToSignedUrl(any(), any(), any(), any()))
          .thenAnswer((_) async => 'p6/r1/ARCH1.pdf');

      final adjunto = await repository.uploadAttachment(
        petId: 'p6',
        recordId: 'r1',
        fileName: 'Examen.pdf',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(adjunto, const RecordAttachment(
          path: 'p6/r1/ARCH1.pdf', tipo: AttachmentType.pdf, nombre: 'Examen.pdf'));
      verify(() => functions.invoke('adjuntos-historial', body: {
            'accion': 'subir',
            'petId': 'p6',
            'recordId': 'r1',
            'nombreArchivo': 'Examen.pdf',
          })).called(1);
      final options = verify(() => files.uploadBinaryToSignedUrl(
            'p6/r1/ARCH1.pdf', 'tok', any(), captureAny())).captured.single as FileOptions;
      expect(options.contentType, 'application/pdf');
    });

    test('rechaza archivos de más de 10 MB sin llamar al servidor', () async {
      await expectLater(
        repository.uploadAttachment(
          petId: 'p6',
          recordId: 'r1',
          fileName: 'grande.jpg',
          bytes: Uint8List(MedicalRecordLimits.maxAdjuntoBytes + 1),
        ),
        throwsA(isA<MedicalRecordFailure>()),
      );
      verifyNever(() => functions.invoke(any(), body: any(named: 'body')));
    });

    test('el enlace de lectura y los errores del servidor', () async {
      when(() => functions.invoke('adjuntos-historial', body: any(named: 'body'))).thenAnswer(
        (_) async => const FunctionResponse(status: 200, data: {'url': 'https://firmado'}),
      );
      expect(await repository.attachmentUrl(petId: 'p6', path: 'p6/r1/a.jpg'), 'https://firmado');

      when(() => functions.invoke('adjuntos-historial', body: any(named: 'body'))).thenThrow(
        const FunctionException(status: 403, details: {
          'error': {'code': 'permission-denied', 'message': 'No tienes permiso para ver este archivo.'},
        }),
      );
      await expectLater(
        repository.attachmentUrl(petId: 'p6', path: 'p6/r1/a.jpg'),
        throwsA(isA<MedicalRecordFailure>()
            .having((f) => f.message, 'message', 'No tienes permiso para ver este archivo.')),
      );
    });

    test('sin Supabase configurado avisa', () async {
      repository = MedicalRecordsRepository(firestore: firestore);
      await expectLater(
        repository.attachmentUrl(petId: 'p6', path: 'p6/r1/a.jpg'),
        throwsA(same(MedicalRecordFailure.notConfigured)),
      );
    });
  });

  test('MedicalRecord: toMap/fromMap y ventana de edición de 24 h', () {
    final r = record();
    final copia = MedicalRecord.fromMap('p6', 'r1', {...r.toMap(), 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 10, 12))});
    expect(copia.vacunas, r.vacunas);
    expect(copia.diagnostico, r.diagnostico);
    expect(copia.isEditable(DateTime(2026, 10, 11, 11)), isTrue);
    expect(copia.isEditable(DateTime(2026, 10, 11, 13)), isFalse);
    expect(record().isEditable(DateTime.now()), isFalse); // sin createdAt aún
  });
}
