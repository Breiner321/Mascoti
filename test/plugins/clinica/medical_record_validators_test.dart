import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/medical_record.dart';
import 'package:mascoti/plugins/clinica/presentation/medical_record_validators.dart';

void main() {
  final now = DateTime(2026, 10, 16, 10, 30);

  group('consulta', () {
    test('el diagnóstico es obligatorio y de máximo 2000 caracteres', () {
      expect(MedicalRecordValidators.diagnostico(''), 'El diagnóstico es obligatorio');
      expect(MedicalRecordValidators.diagnostico('   '), 'El diagnóstico es obligatorio');
      expect(MedicalRecordValidators.diagnostico('Otitis'), isNull);
      expect(MedicalRecordValidators.diagnostico('a' * 2000), isNull);
      expect(MedicalRecordValidators.diagnostico('a' * 2001), contains('2000'));
    });

    test('el tratamiento es opcional, máximo 2000 caracteres', () {
      expect(MedicalRecordValidators.tratamiento(null), isNull);
      expect(MedicalRecordValidators.tratamiento(''), isNull);
      expect(MedicalRecordValidators.tratamiento('a' * 2001), contains('2000'));
    });

    test('la fecha de la consulta no puede ser futura', () {
      expect(MedicalRecordValidators.fecha(null, now), isNotNull);
      expect(MedicalRecordValidators.fecha(DateTime(2026, 10, 16, 23), now), isNull);
      expect(MedicalRecordValidators.fecha(DateTime(2026, 9, 1), now), isNull);
      expect(MedicalRecordValidators.fecha(DateTime(2026, 10, 17), now),
          'La fecha no puede ser futura');
    });
  });

  group('vacunas', () {
    test('nombre y lote obligatorios, con sus límites', () {
      expect(MedicalRecordValidators.vacunaNombre(''), 'El nombre de la vacuna es obligatorio');
      expect(MedicalRecordValidators.vacunaNombre('Rabia'), isNull);
      expect(MedicalRecordValidators.vacunaNombre('a' * 81), 'Máximo 80 caracteres');
      expect(MedicalRecordValidators.lote(' '), 'El lote es obligatorio');
      expect(MedicalRecordValidators.lote('A123'), isNull);
      expect(MedicalRecordValidators.lote('a' * 41), 'Máximo 40 caracteres');
    });

    test('la fecha de aplicación es obligatoria y no futura', () {
      expect(
          MedicalRecordValidators.fechaAplicacion(null, now), 'Selecciona la fecha de aplicación');
      expect(MedicalRecordValidators.fechaAplicacion(DateTime(2026, 10, 16), now), isNull);
      expect(MedicalRecordValidators.fechaAplicacion(DateTime(2026, 10, 20), now),
          'La fecha de aplicación no puede ser futura');
    });

    test('la próxima dosis es opcional y posterior a la aplicación', () {
      final aplicada = DateTime(2026, 10, 16);
      expect(MedicalRecordValidators.fechaProximaDosis(null, aplicada), isNull);
      expect(MedicalRecordValidators.fechaProximaDosis(DateTime(2027, 10, 16), aplicada), isNull);
      expect(MedicalRecordValidators.fechaProximaDosis(DateTime(2026, 10, 16, 18), aplicada),
          'La próxima dosis debe ser posterior a la aplicación');
      expect(MedicalRecordValidators.fechaProximaDosis(DateTime(2026, 1, 1), aplicada),
          'La próxima dosis debe ser posterior a la aplicación');
    });
  });

  group('adjuntos', () {
    test('solo JPG, PNG o PDF de máximo 10 MB', () {
      expect(MedicalRecordValidators.adjunto(fileName: 'rx.JPG', bytes: 100), isNull);
      expect(MedicalRecordValidators.adjunto(fileName: 'examen.pdf', bytes: 100), isNull);
      expect(
        MedicalRecordValidators.adjunto(
            fileName: 'examen.pdf', bytes: MedicalRecordLimits.maxAdjuntoBytes),
        isNull,
      );
      expect(
        MedicalRecordValidators.adjunto(
            fileName: 'examen.pdf', bytes: MedicalRecordLimits.maxAdjuntoBytes + 1),
        'El archivo supera el máximo de 10 MB.',
      );
      expect(MedicalRecordValidators.adjunto(fileName: 'notas.docx', bytes: 100),
          'Solo se permiten imágenes JPG o PNG y archivos PDF.');
      expect(MedicalRecordValidators.adjunto(fileName: 'sin_extension', bytes: 100), isNotNull);
    });

    test('tipo según la extensión y nombre recortado a 120 caracteres', () {
      expect(MedicalRecordValidators.attachmentType('a.pdf'), AttachmentType.pdf);
      expect(MedicalRecordValidators.attachmentType('a.png'), AttachmentType.imagen);
      final long = '${'x' * 200}.pdf';
      final name = MedicalRecordValidators.displayName(long);
      expect(name.length, 120);
      expect(name, endsWith('.pdf'));
      expect(MedicalRecordValidators.displayName('rx.png'), 'rx.png');
    });
  });
}
