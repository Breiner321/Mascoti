import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/domain/slot.dart';
import '../../../core/theme/app_theme.dart';

/// Calendario mensual de la agenda (mockup "Mi día"): empieza en lunes,
/// días como cuadros redondeados y un punto en los días con horarios.
class AgendaCalendar extends StatelessWidget {
  const AgendaCalendar({
    super.key,
    required this.selectedDay,
    required this.focusedDay,
    required this.configuredDays,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime selectedDay;
  final DateTime focusedDay;

  /// Fechas 'YYYY-MM-DD' con franjas configuradas.
  final Set<String> configuredDays;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onPageChanged;

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    BoxDecoration cell(Color color) =>
        BoxDecoration(color: color, borderRadius: BorderRadius.circular(10));

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          TableCalendar<int>(
            locale: 'es',
            firstDay: DateTime(2024),
            lastDay: DateTime(2030, 12, 31),
            focusedDay: focusedDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
            selectedDayPredicate: (day) => isSameDay(day, selectedDay),
            eventLoader: (day) =>
                configuredDays.contains(Slot.dateKey(day)) ? const [1] : const [],
            onDaySelected: (selected, _) => onDaySelected(selected),
            onPageChanged: onPageChanged,
            rowHeight: 44,
            daysOfWeekHeight: 24,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleTextFormatter: (date, locale) =>
                  _capitalize('${_monthName(date)} ${date.year}'),
              titleTextStyle: textTheme.titleMedium!.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
              headerPadding: const EdgeInsets.only(bottom: 4),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              dowTextFormatter: (date, locale) => _weekdayInitial(date),
              weekdayStyle: textTheme.labelSmall!.copyWith(color: AppColors.textMuted),
              weekendStyle: textTheme.labelSmall!.copyWith(color: AppColors.textMuted),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              cellMargin: const EdgeInsets.all(3),
              defaultDecoration: cell(AppColors.background),
              weekendDecoration: cell(AppColors.background),
              todayDecoration: cell(AppColors.primaryContainer),
              selectedDecoration: cell(AppColors.primary),
              todayTextStyle: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
              selectedTextStyle: const TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
              markerDecoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              markerSize: 4,
              markersMaxCount: 1,
              markerMargin: const EdgeInsets.only(top: 1),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '• con horarios',
              style: textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  static const _weekdayInitials = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  static String _monthName(DateTime date) => _months[date.month - 1];
  static String _weekdayInitial(DateTime date) => _weekdayInitials[date.weekday - 1];
}

const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const _weekdays = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];

/// "Lunes 28 de septiembre" (encabezado del mockup "Mi día").
String formatDayTitle(DateTime date) {
  final weekday = _weekdays[date.weekday - 1];
  return '${weekday[0].toUpperCase()}${weekday.substring(1)} '
      '${date.day} de ${_months[date.month - 1]}';
}

/// "28 de septiembre".
String formatShortDay(DateTime date) => '${date.day} de ${_months[date.month - 1]}';
