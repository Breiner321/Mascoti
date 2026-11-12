import 'package:flutter/foundation.dart';

import 'opening_hours.dart';

/// Día de la semana del horario (Cambio 2). [key] es la clave en Firestore
/// (`clinics.horarioSemanal.lun`…) y [weekday] el de `DateTime.weekday`.
enum Weekday {
  lun('lun', 'Lunes', DateTime.monday),
  mar('mar', 'Martes', DateTime.tuesday),
  mie('mie', 'Miércoles', DateTime.wednesday),
  jue('jue', 'Jueves', DateTime.thursday),
  vie('vie', 'Viernes', DateTime.friday),
  sab('sab', 'Sábado', DateTime.saturday),
  dom('dom', 'Domingo', DateTime.sunday);

  const Weekday(this.key, this.label, this.weekday);

  final String key;
  final String label;
  final int weekday;

  static Weekday of(int dateTimeWeekday) =>
      values.firstWhere((d) => d.weekday == dateTimeWeekday);

  /// Día de la semana de 'YYYY-MM-DD' (fecha de calendario, sin zona).
  static Weekday ofDate(String fecha) {
    final parts = fecha.split('-').map(int.parse).toList();
    return of(DateTime.utc(parts[0], parts[1], parts[2]).weekday);
  }
}

/// Horario de un día: abierto o cerrado, apertura/cierre y un descanso
/// opcional (p. ej. almuerzo). Horas `HH:mm` (24 h).
@immutable
class DayHours {
  const DayHours({
    required this.abierto,
    this.apertura = '08:00',
    this.cierre = '18:00',
    this.descansoInicio,
    this.descansoFin,
  });

  const DayHours.closed() : this(abierto: false);

  /// Un día con horas mal formadas se trata como cerrado (las reglas solo
  /// validan la estructura; la app nunca guarda horas inválidas).
  factory DayHours.fromMap(Map<String, dynamic> map) {
    final day = DayHours(
      abierto: map['abierto'] == true,
      apertura: map['apertura'] is String ? map['apertura'] as String : '08:00',
      cierre: map['cierre'] is String ? map['cierre'] as String : '18:00',
      descansoInicio: map['descansoInicio'] is String ? map['descansoInicio'] as String : null,
      descansoFin: map['descansoFin'] is String ? map['descansoFin'] as String : null,
    );
    return day.abierto && day.validate(1) != null ? day.copyWith(abierto: false) : day;
  }

  final bool abierto;
  final String apertura;
  final String cierre;
  final String? descansoInicio;
  final String? descansoFin;

  bool get hasBreak => descansoInicio != null && descansoFin != null;

  /// Tramos de atención del día en minutos desde las 00:00: [inicio, fin).
  List<(int, int)> get intervals {
    if (!abierto) return const [];
    final open = OpeningHours.minutesOf(apertura);
    final close = OpeningHours.minutesOf(cierre);
    if (!hasBreak) return [(open, close)];
    final b0 = OpeningHours.minutesOf(descansoInicio!);
    final b1 = OpeningHours.minutesOf(descansoFin!);
    return [if (b0 > open) (open, b0), if (close > b1) (b1, close)];
  }

  /// Mensaje de error, o null si el horario del día es válido. Las horas
  /// deben ser múltiplos de [slotMinutes] para que las franjas cuadren.
  String? validate(int slotMinutes) {
    if (!abierto) return null;
    final time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    final times = [apertura, cierre, if (descansoInicio != null) descansoInicio!,
      if (descansoFin != null) descansoFin!];
    if (!times.every(time.hasMatch)) return 'Hora inválida';
    if ((descansoInicio == null) != (descansoFin == null)) {
      return 'Indica el inicio y el fin del descanso';
    }
    final open = OpeningHours.minutesOf(apertura);
    final close = OpeningHours.minutesOf(cierre);
    if (open >= close) return 'La apertura debe ser antes del cierre';
    if (hasBreak) {
      final b0 = OpeningHours.minutesOf(descansoInicio!);
      final b1 = OpeningHours.minutesOf(descansoFin!);
      if (b0 >= b1) return 'El descanso debe empezar antes de terminar';
      if (b0 < open || b1 > close) return 'El descanso debe estar dentro del horario';
    }
    final all = times.map(OpeningHours.minutesOf);
    if (all.any((m) => m % slotMinutes != 0)) {
      return 'Usa horas en bloques de $slotMinutes minutos';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'abierto': abierto,
        'apertura': apertura,
        'cierre': cierre,
        if (hasBreak) 'descansoInicio': descansoInicio,
        if (hasBreak) 'descansoFin': descansoFin,
      };

  DayHours copyWith({
    bool? abierto,
    String? apertura,
    String? cierre,
    String? descansoInicio,
    String? descansoFin,
    bool clearBreak = false,
  }) =>
      DayHours(
        abierto: abierto ?? this.abierto,
        apertura: apertura ?? this.apertura,
        cierre: cierre ?? this.cierre,
        descansoInicio: clearBreak ? null : descansoInicio ?? this.descansoInicio,
        descansoFin: clearBreak ? null : descansoFin ?? this.descansoFin,
      );

  @override
  bool operator ==(Object other) =>
      other is DayHours &&
      other.abierto == abierto &&
      other.apertura == apertura &&
      other.cierre == cierre &&
      other.descansoInicio == descansoInicio &&
      other.descansoFin == descansoFin;

  @override
  int get hashCode => Object.hash(abierto, apertura, cierre, descansoInicio, descansoFin);
}

/// `clinics.horarioSemanal` (Cambio 2): reemplaza a `horarioBase`. La
/// clínica está disponible siempre dentro de este horario, salvo citas y
/// excepciones. Igual a `supabase/functions/_shared/disponibilidad.ts`.
@immutable
class WeeklySchedule {
  const WeeklySchedule(this.days);

  factory WeeklySchedule.fromMap(Map<String, dynamic> map) => WeeklySchedule({
        for (final d in Weekday.values)
          d: map[d.key] is Map
              ? DayHours.fromMap(Map<String, dynamic>.from(map[d.key] as Map))
              : const DayHours.closed(),
      });

  /// Migración de `horarioBase`: todos los días abiertos con el mismo
  /// horario (decisión del equipo), así nada cambia para la clínica.
  factory WeeklySchedule.fromOpeningHours(OpeningHours hours) => WeeklySchedule({
        for (final d in Weekday.values)
          d: DayHours(abierto: true, apertura: hours.apertura, cierre: hours.cierre),
      });

  /// Valor inicial para una clínica nueva: lunes a sábado de 8 a 18 con
  /// almuerzo de 12 a 14; domingo cerrado.
  static final standard = WeeklySchedule({
    for (final d in Weekday.values)
      d: d == Weekday.dom
          ? const DayHours.closed()
          : const DayHours(
              abierto: true,
              apertura: '08:00',
              cierre: '18:00',
              descansoInicio: '12:00',
              descansoFin: '14:00',
            ),
  });

  final Map<Weekday, DayHours> days;

  DayHours operator [](Weekday day) => days[day] ?? const DayHours.closed();

  DayHours forDate(String fecha) => this[Weekday.ofDate(fecha)];

  bool get isOpenSomeDay => days.values.any((d) => d.abierto);

  /// Primer error por día ("Lunes: …"), o null si todo es válido.
  String? validate(int slotMinutes) {
    if (!isOpenSomeDay) return 'Abre al menos un día de la semana';
    for (final d in Weekday.values) {
      final error = this[d].validate(slotMinutes);
      if (error != null) return '${d.label}: $error';
    }
    return null;
  }

  WeeklySchedule withDay(Weekday day, DayHours hours) =>
      WeeklySchedule({...days, day: hours});

  Map<String, dynamic> toMap() => {for (final d in Weekday.values) d.key: this[d].toMap()};

  @override
  bool operator ==(Object other) =>
      other is WeeklySchedule &&
      Weekday.values.every((d) => other[d] == this[d]);

  @override
  int get hashCode => Object.hashAll(Weekday.values.map((d) => this[d]));
}

/// `clinics.reservas` (Cambio 2): reglas para agendar.
@immutable
class BookingSettings {
  const BookingSettings({
    this.duracionSlotMin = 30,
    this.anticipacionMaxDias = 30,
    this.anticipacionMinMin = 120,
  });

  factory BookingSettings.fromMap(Map<String, dynamic> map) => BookingSettings(
        duracionSlotMin: (map['duracionSlotMin'] as num?)?.toInt() ?? 30,
        anticipacionMaxDias: (map['anticipacionMaxDias'] as num?)?.toInt() ?? 30,
        anticipacionMinMin: (map['anticipacionMinMin'] as num?)?.toInt() ?? 120,
      );

  /// Duraciones que ofrece la app (RF-04).
  static const slotOptions = [15, 30, 60];

  /// Duración base de cada franja: 15, 30 o 60 minutos.
  final int duracionSlotMin;

  /// Hasta cuántos días adelante se puede reservar (1-365).
  final int anticipacionMaxDias;

  /// Mínimo de minutos antes del inicio para reservar (0-10080 = 7 días).
  final int anticipacionMinMin;

  Map<String, dynamic> toMap() => {
        'duracionSlotMin': duracionSlotMin,
        'anticipacionMaxDias': anticipacionMaxDias,
        'anticipacionMinMin': anticipacionMinMin,
      };

  BookingSettings copyWith({
    int? duracionSlotMin,
    int? anticipacionMaxDias,
    int? anticipacionMinMin,
  }) =>
      BookingSettings(
        duracionSlotMin: duracionSlotMin ?? this.duracionSlotMin,
        anticipacionMaxDias: anticipacionMaxDias ?? this.anticipacionMaxDias,
        anticipacionMinMin: anticipacionMinMin ?? this.anticipacionMinMin,
      );

  @override
  bool operator ==(Object other) =>
      other is BookingSettings &&
      other.duracionSlotMin == duracionSlotMin &&
      other.anticipacionMaxDias == anticipacionMaxDias &&
      other.anticipacionMinMin == anticipacionMinMin;

  @override
  int get hashCode => Object.hash(duracionSlotMin, anticipacionMaxDias, anticipacionMinMin);
}
