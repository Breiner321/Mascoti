import 'package:intl/intl.dart';

/// Separador de miles con punto, sin decimales. Se arma a mano porque el
/// patrón de moneda de es_CO en intl ubica el símbolo después del número.
final _thousands = NumberFormat('#,##0', 'es_CO');

/// 45000 → "$ 45.000".
String formatCop(num value) => '\$ ${_thousands.format(value.round())}';
