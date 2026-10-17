import 'dart:math';

/// Código de paciente de una mascota (`pets.codigoPaciente`), p. ej.
/// `MSC-7K4P`. El dueño se lo dicta a la clínica para que la vincule
/// (Edge Function `vincular-mascota`).
///
/// Sin caracteres que se confunden al leerlos o dictarlos: no hay 0/O, 1/I
/// ni L. Con 31 símbolos y 4 posiciones hay 923.521 códigos; la unicidad la
/// garantiza el documento `codigosPaciente/{codigo}` (ver firestore.rules).
abstract final class PatientCode {
  static const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const prefix = 'MSC-';
  static const length = 4;

  static final RegExp pattern = RegExp('^$prefix[$alphabet]{$length}\$');

  static final Random _secure = Random.secure();

  /// Código aleatorio nuevo. [random] solo para pruebas.
  static String generate([Random? random]) {
    final r = random ?? _secure;
    final body = List.generate(length, (_) => alphabet[r.nextInt(alphabet.length)]).join();
    return '$prefix$body';
  }

  static bool isValid(String? code) => code != null && pattern.hasMatch(code);

  /// Lo que escribe la clínica → código canónico, o null si no es válido:
  /// `' msc 7k4p '`, `'7K4P'` o `'MSC7K4P'` → `'MSC-7K4P'`.
  static String? normalize(String input) {
    var text = input.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (text.startsWith('MSC')) text = text.substring(3);
    final code = '$prefix$text';
    return isValid(code) ? code : null;
  }
}
