import 'package:intl/intl.dart';

/// Validaciones del formulario de servicios (RF-05). Devuelven el mensaje de
/// error o null si el valor es válido.
abstract final class ServiceValidators {
  static String? nombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El nombre es obligatorio';
    if (v.length < 3 || v.length > 60) {
      return 'El nombre debe tener entre 3 y 60 caracteres';
    }
    return null;
  }

  static String? categoria(Object? value) =>
      value == null ? 'Selecciona una categoría' : null;

  /// Precio en COP sin decimales. Acepta los puntos de miles del formato
  /// ("45.000").
  static String? precio(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'El precio es obligatorio';
    if (v.contains(',') || RegExp(r'\.\d{1,2}$').hasMatch(v)) {
      return 'Ingresa el precio sin decimales';
    }
    final parsed = parsePrice(v);
    if (parsed == null) return 'Ingresa el precio sin decimales';
    if (parsed <= 0) return 'El precio debe ser mayor a 0';
    return null;
  }

  static String? duracion(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'La duración es obligatoria';
    final parsed = int.tryParse(v);
    if (parsed == null || parsed < 5 || parsed > 480) {
      return 'La duración debe ser un número entero entre 5 y 480 minutos';
    }
    return null;
  }

  static String? descripcion(String? value) => (value?.trim().length ?? 0) > 1000
      ? 'La descripción no puede superar 1000 caracteres'
      : null;

  /// "45.000" o "45000" → 45000. null si no es un entero.
  static int? parsePrice(String value) {
    final v = value.trim();
    if (v.startsWith('-')) {
      final n = parsePrice(v.substring(1));
      return n == null ? null : -n;
    }
    if (!RegExp(r'^(\d+|\d{1,3}(\.\d{3})+)$').hasMatch(v)) return null;
    return int.parse(v.replaceAll('.', ''));
  }
}

/// Separador de miles con punto, sin decimales. Se arma a mano porque el
/// patrón de moneda de es_CO en intl ubica el símbolo después del número.
final _thousands = NumberFormat('#,##0', 'es_CO');

/// 45000 → "$ 45.000".
String formatCop(num value) => '\$ ${formatThousands(value.round())}';

/// 45000 → "45.000" (para el campo de precio).
String formatThousands(num value) => _thousands.format(value);
