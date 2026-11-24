import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/images/photo_compression.dart';

void main() {
  test('reconoce JPG y PNG por tipo o extensión', () {
    expect(isPngImage('foto.jpg', null), isFalse);
    expect(isPngImage('foto.JPEG', null), isFalse);
    expect(isPngImage('foto', 'image/png'), isTrue);
    expect(isPngImage('foto.gif', 'image/gif'), isNull);
    expect(isPngImage('foto.webp', null), isNull);
  });

  test('una foto de 1 MB o menos se deja igual', () async {
    final bytes = Uint8List(1000);
    final photo = await compressPhoto(bytes, png: true, compress: (_, __, ___) => fail('no'));
    expect(photo.bytes, same(bytes));
    expect(photo.png, isTrue);
  });

  test('comprime hasta quedar en 1 MB o menos (JPEG)', () async {
    final calls = <int>[];
    final photo = await compressPhoto(
      Uint8List(3 * 1024 * 1024),
      png: true,
      compress: (bytes, side, quality) async {
        calls.add(quality);
        return Uint8List(quality > 70 ? 2 * 1024 * 1024 : 900 * 1024);
      },
    );
    expect(photo.bytes.length, lessThanOrEqualTo(PickedPhoto.maxBytes));
    expect(photo.png, isFalse);
    expect(calls, [85, 70]);
  });

  test('rechaza archivos de más de 5 MB antes de comprimir', () {
    expect(
      compressPhoto(Uint8List(PickedPhoto.maxSourceBytes + 1), png: false),
      throwsA(isA<PhotoException>()),
    );
  });

  test('si no logra bajar de 1 MB pide otra foto', () {
    expect(
      compressPhoto(
        Uint8List(2 * 1024 * 1024),
        png: false,
        compress: (_, __, ___) async => Uint8List(2 * 1024 * 1024),
      ),
      throwsA(isA<PhotoException>()),
    );
  });
}
