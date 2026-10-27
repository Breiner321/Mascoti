import 'time_format.dart';

/// Horario `opening_hours` de OpenStreetMap en español (Cambio 4):
/// "Mo-Fr 08:00-18:00; Sa 08:00-12:00" → "Lu-Vi 8:00 a. m.–6:00 p. m.; Sá
/// 8:00 a. m.–12:00 p. m.". Es una traducción del texto, no un intérprete
/// completo del formato: lo que no reconoce queda igual.
abstract final class OsmHours {
  static const _days = {
    'Mo': 'Lu', 'Tu': 'Ma', 'We': 'Mi', 'Th': 'Ju', 'Fr': 'Vi', 'Sa': 'Sá', 'Su': 'Do',
    'PH': 'festivos',
  };

  static final _dayPattern = RegExp(r'\b(Mo|Tu|We|Th|Fr|Sa|Su|PH)\b');
  static final _rangePattern = RegExp(r'\b(\d{1,2}:\d{2})-(\d{1,2}:\d{2})\b');
  static final _offPattern = RegExp(r'\boff\b');

  static String toSpanish(String raw) {
    final text = raw.trim();
    if (text == '24/7') return 'Abierto 24 horas';
    return text
        .replaceAllMapped(_dayPattern, (m) => _days[m[1]]!)
        .replaceAllMapped(
          _rangePattern,
          (m) => '${TimeFormat.hour(m[1]!)}–${TimeFormat.hour(m[2]!)}',
        )
        .replaceAll(_offPattern, 'cerrado');
  }
}
