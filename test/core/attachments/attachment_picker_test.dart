import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/attachments/attachment_picker.dart';

/// Registra con qué filtro se abre el selector del sistema.
class _FakeFilePicker extends FilePickerPlatform {
  FileType? type;
  List<String>? allowedExtensions;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.type = type;
    this.allowedExtensions = allowedExtensions;
    return null;
  }
}

void main() {
  late _FakeFilePicker platform;

  setUp(() => FilePickerPlatform.instance = platform = _FakeFilePicker());

  test('historial: abre sin filtro para que la app avise si el tipo no se permite', () async {
    expect(await const AttachmentPicker().pick(), isNull);
    expect(platform.type, FileType.any);
    expect(platform.allowedExtensions, isNull);
  });

  test('chat "Documento PDF": sigue mostrando solo PDF', () async {
    await const AttachmentPicker().pickPdf();
    expect(platform.type, FileType.custom);
    expect(platform.allowedExtensions, ['pdf']);
  });
}
