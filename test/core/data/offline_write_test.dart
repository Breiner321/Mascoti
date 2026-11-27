import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/data/offline_write.dart';

void main() {
  test('confirmada por el servidor → true', () async {
    expect(await awaitWrite(Future.value()), isTrue);
  });

  test('sin conexión (nunca termina) → false a los 10 s, sin quedarse esperando', () {
    fakeAsync((async) {
      bool? result;
      awaitWrite(Completer<void>().future).then((v) => result = v);
      async.elapse(const Duration(seconds: 9));
      expect(result, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(result, isFalse);
    });
  });

  test('un rechazo del servidor se propaga', () {
    expect(awaitWrite(Future.error(StateError('permission-denied'))), throwsStateError);
  });
}
