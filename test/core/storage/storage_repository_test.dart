import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/storage/storage_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockStorage extends Mock implements SupabaseStorageClient {}

class _MockFiles extends Mock implements StorageFileApi {}

void main() {
  late _MockStorage storage;
  late _MockFiles files;
  late StorageRepository repository;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const FileOptions());
  });

  setUp(() {
    storage = _MockStorage();
    files = _MockFiles();
    when(() => storage.from('mascoti')).thenReturn(files);
    repository = StorageRepository(storage);
  });

  test('las rutas quedan dentro de la carpeta del usuario', () {
    expect(StorageRepository.userPath('u1', 'mascotas/p1/foto.jpg'),
        'usuarios/u1/mascotas/p1/foto.jpg');
    expect(StorageRepository.userPath('u1', '/foto.jpg'), 'usuarios/u1/foto.jpg');
    expect(() => StorageRepository.userPath('u1', '../u2/foto.jpg'), throwsArgumentError);
    expect(() => StorageRepository.userPath('', 'foto.jpg'), throwsArgumentError);
  });

  test('upload sube al bucket mascoti y devuelve la ruta completa', () async {
    when(() => files.uploadBinary(any(), any(), fileOptions: any(named: 'fileOptions')))
        .thenAnswer((_) async => 'mascoti/usuarios/u1/foto.jpg');

    final path = await repository.upload(
      uid: 'u1',
      path: 'foto.jpg',
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/jpeg',
    );

    expect(path, 'usuarios/u1/foto.jpg');
    final options = verify(() => files.uploadBinary(
          'usuarios/u1/foto.jpg',
          any(),
          fileOptions: captureAny(named: 'fileOptions'),
        )).captured.single as FileOptions;
    expect(options.contentType, 'image/jpeg');
    expect(options.upsert, isTrue);
  });

  test('signedUrl pide un enlace temporal', () async {
    when(() => files.createSignedUrl('usuarios/u1/foto.jpg', 3600))
        .thenAnswer((_) async => 'https://firmado');
    expect(await repository.signedUrl('usuarios/u1/foto.jpg'), 'https://firmado');
  });

  test('sin Supabase configurado avisa con un error claro', () {
    expect(() => StorageRepository(null).signedUrl('x'), throwsStateError);
  });
}
