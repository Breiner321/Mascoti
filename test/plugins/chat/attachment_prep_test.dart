import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/chat_repository.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/core/domain/medical_record.dart';
import 'package:mascoti/plugins/chat/presentation/comun/adjuntos/attach_button.dart';
import 'package:mascoti/plugins/chat/presentation/comun/adjuntos/attachment_prep.dart';
import 'package:mascoti/plugins/chat/presentation/comun/adjuntos/history_reference.dart';

const mb = 1024 * 1024;

Uint8List bytesOf(int n) => Uint8List(n);

void main() {
  group('prepareChatAttachment (RF-16 paso 4)', () {
    Future<Uint8List> noCompression(Uint8List b, {required bool png}) async => b;

    test('acepta JPG, JPEG, PNG y PDF (sin importar mayúsculas)', () async {
      for (final (name, tipo) in [
        ('foto.jpg', ChatAttachmentType.imagen),
        ('foto.JPEG', ChatAttachmentType.imagen),
        ('placa.png', ChatAttachmentType.imagen),
        ('examen.PDF', ChatAttachmentType.pdf),
      ]) {
        final out = await prepareChatAttachment(name, bytesOf(10), compress: noCompression);
        expect(out.tipo, tipo, reason: name);
        expect(out.name, name);
      }
    });

    test('rechaza otros tipos con un mensaje claro', () async {
      for (final name in ['video.mp4', 'nota.docx', 'foto.heic', 'sin_extension']) {
        await expectLater(
          prepareChatAttachment(name, bytesOf(10), compress: noCompression),
          throwsA(isA<ChatFailure>().having(
            (e) => e.message,
            'message',
            'Solo se permiten imágenes JPG o PNG y archivos PDF.',
          )),
          reason: name,
        );
      }
    });

    test('rechaza un PDF de más de 10 MB y sugiere uno más liviano', () async {
      await expectLater(
        prepareChatAttachment('examen.pdf', bytesOf(10 * mb + 1), compress: noCompression),
        throwsA(isA<ChatFailure>().having(
          (e) => e.message,
          'message',
          contains('supera los 10 MB'),
        )),
      );
      final ok = await prepareChatAttachment('examen.pdf', bytesOf(10 * mb));
      expect(ok.bytes.length, 10 * mb);
    });

    test('comprime las imágenes antes de validar el tamaño', () async {
      bool? asPng;
      final out = await prepareChatAttachment(
        'foto.png',
        bytesOf(12 * mb),
        compress: (b, {required png}) async {
          asPng = png;
          return bytesOf(800 * 1024);
        },
      );
      expect(asPng, isTrue);
      expect(out.bytes.length, 800 * 1024);
    });

    test('si la compresión falla o no ayuda, usa la original', () async {
      final failed = await prepareChatAttachment(
        'foto.jpg',
        bytesOf(2 * mb),
        compress: (b, {required png}) async => throw Exception('códec'),
      );
      expect(failed.bytes.length, 2 * mb);

      final bigger = await prepareChatAttachment(
        'foto.jpg',
        bytesOf(100),
        compress: (b, {required png}) async => bytesOf(200),
      );
      expect(bigger.bytes.length, 100);
    });

    test('no comprime los PDF', () async {
      var called = false;
      await prepareChatAttachment(
        'examen.pdf',
        bytesOf(100),
        compress: (b, {required png}) async {
          called = true;
          return b;
        },
      );
      expect(called, isFalse);
    });

    test('un archivo vacío no se envía', () async {
      await expectLater(
        prepareChatAttachment('foto.jpg', Uint8List(0), compress: noCompression),
        throwsA(isA<ChatFailure>()),
      );
    });
  });

  group('adjuntos del historial', () {
    test('referenciaHistorialId es "{petId}/{recordId}"', () {
      const ref = HistoryReference(petId: 'p1', recordId: 'r9');
      expect(ref.value, 'p1/r9');
      final parsed = HistoryReference.parse('p1/r9')!;
      expect((parsed.petId, parsed.recordId), ('p1', 'r9'));
      expect(HistoryReference.parse(null), isNull);
      expect(HistoryReference.parse('r9'), isNull);
      expect(HistoryReference.parse('p1/'), isNull);
    });

    test('el nombre conserva la extensión o la agrega según el tipo', () {
      expect(
        historyFileName(const RecordAttachment(path: 'x', tipo: AttachmentType.pdf, nombre: 'a.pdf')),
        'a.pdf',
      );
      expect(
        historyFileName(
            const RecordAttachment(path: 'x', tipo: AttachmentType.imagen, nombre: 'Radiografía')),
        'Radiografía.jpg',
      );
      expect(
        historyFileName(const RecordAttachment(path: 'x', tipo: AttachmentType.pdf, nombre: ' ')),
        'archivo.pdf',
      );
    });
  });
}
