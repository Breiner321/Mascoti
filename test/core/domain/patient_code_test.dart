import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/patient_code.dart';

void main() {
  test('genera códigos MSC-XXXX sin caracteres ambiguos', () {
    final random = Random(42);
    for (var i = 0; i < 500; i++) {
      final code = PatientCode.generate(random);
      expect(PatientCode.isValid(code), isTrue, reason: code);
      expect(code.substring(4), isNot(matches(r'[01OIL]')));
    }
    expect(PatientCode.alphabet, isNot(contains('0')));
    expect(PatientCode.alphabet, isNot(contains('O')));
    expect(PatientCode.alphabet, isNot(contains('1')));
    expect(PatientCode.alphabet, isNot(contains('I')));
    expect(PatientCode.alphabet, isNot(contains('L')));
    expect(PatientCode.alphabet.length, 31);
  });

  test('valida el formato', () {
    expect(PatientCode.isValid('MSC-7K4P'), isTrue);
    for (final bad in ['MSC-0K4P', 'MSC-OK4P', 'MSC-1K4P', 'MSC-IK4P', 'MSC-LK4P',
                       'MSC-7K4', 'MSC-7K4PP', 'msc-7k4p', 'ABC-7K4P', null]) {
      expect(PatientCode.isValid(bad), isFalse, reason: '$bad');
    }
  });

  test('normaliza lo que escribe la clínica', () {
    expect(PatientCode.normalize('MSC-7K4P'), 'MSC-7K4P');
    expect(PatientCode.normalize(' msc 7k4p '), 'MSC-7K4P');
    expect(PatientCode.normalize('7k4p'), 'MSC-7K4P');
    expect(PatientCode.normalize('MSC7K4P'), 'MSC-7K4P');
    expect(PatientCode.normalize('MSC-7K40'), isNull);
    expect(PatientCode.normalize(''), isNull);
  });
}
