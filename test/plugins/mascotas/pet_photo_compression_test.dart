import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/plugins/mascotas/data/pet_photo_service.dart';
import 'package:mascoti/plugins/mascotas/domain/pet_photo.dart';

void main() {
  Uint8List bytes(int length) => Uint8List(length);
  const big = PetPhoto.maxBytes + 1;

  test('una foto de 1 MB o menos se deja igual (y conserva PNG)', () async {
    var calls = 0;
    final photo = await compressPetPhoto(
      bytes(PetPhoto.maxBytes),
      png: true,
      compress: (b, side, q) async {
        calls++;
        return b;
      },
    );
    expect(calls, 0);
    expect(photo.png, isTrue);
    expect(photo.bytes.length, PetPhoto.maxBytes);
  });

  test('una foto pesada se comprime a JPEG hasta quedar en 1 MB', () async {
    final attempts = <(int, int)>[];
    final photo = await compressPetPhoto(
      bytes(5 * PetPhoto.maxBytes),
      png: true,
      compress: (b, side, quality) async {
        attempts.add((side, quality));
        return bytes(attempts.length == 1 ? big : 500 * 1024);
      },
    );
    expect(attempts, [(1600, 85), (1600, 70)]);
    expect(photo.png, isFalse);
    expect(photo.bytes.length, 500 * 1024);
  });

  test('si nunca queda en 1 MB avisa que es muy pesada', () {
    expect(
      compressPetPhoto(bytes(big), png: false, compress: (b, s, q) async => bytes(big)),
      throwsA(isA<PetPhotoException>()
          .having((e) => e.message, 'message', 'La foto es muy pesada. Elige otra.')),
    );
  });

  test('si el compresor falla avisa que no se pudo procesar', () {
    expect(
      compressPetPhoto(bytes(big), png: false, compress: (b, s, q) => throw Exception()),
      throwsA(isA<PetPhotoException>().having(
          (e) => e.message, 'message', 'No se pudo procesar la foto. Elige otra.')),
    );
  });
}
