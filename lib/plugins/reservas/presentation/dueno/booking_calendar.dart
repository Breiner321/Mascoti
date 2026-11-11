import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/domain/slot.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/calendar_month_header.dart';
import 'booking_format.dart';

/// Calendario mensual de "Agendar cita" (mockup VISTA CLIENTE): empieza en
/// lunes y solo deja tocar los días con horas disponibles, que se resaltan.
class BookingCalendar extends StatelessWidget {
  const BookingCalendar({
    super.key,
    required this.firstDay,
    required this.lastDay,
    required this.focusedDay,
    required this.selectedFecha,
    required this.availableDays,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime firstDay;
  final DateTime lastDay;
  final DateTime focusedDay;

  /// 'YYYY-MM-DD' elegido, o null.
  final String? selectedFecha;

  /// Fechas 'YYYY-MM-DD' con horas disponibles para el servicio elegido.
  final Set<String> availableDays;
  final ValueChanged<String> onDaySelected;
  final ValueChanged<DateTime> onPageChanged;

  static const _weekdayInitials = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    BoxDecoration cell(Color color) =>
        BoxDecoration(color: color, borderRadius: BorderRadius.circular(10));
    final dayText = TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: TableCalendar<int>(
        locale: 'es',
        firstDay: firstDay,
        lastDay: lastDay,
        focusedDay: focusedDay,
        startingDayOfWeek: StartingDayOfWeek.monday,
        availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
        availableGestures: AvailableGestures.horizontalSwipe,
        selectedDayPredicate: (day) => Slot.dateKey(day) == selectedFecha,
        enabledDayPredicate: (day) => availableDays.contains(Slot.dateKey(day)),
        // Cambio 3: los días con horas llevan un punto, no solo otro color.
        eventLoader: (day) => availableDays.contains(Slot.dateKey(day)) ? const [1] : const [],
        onDaySelected: (selected, _) => onDaySelected(Slot.dateKey(selected)),
        onPageChanged: onPageChanged,
        rowHeight: 48, // Cambio 3: área táctil mínima de 48 dp.
        daysOfWeekHeight: 24,
        // Cambio 3: flechas propias, con nombre para el lector de pantalla.
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          leftChevronVisible: false,
          rightChevronVisible: false,
          headerPadding: EdgeInsets.only(bottom: 4),
        ),
        calendarBuilders: CalendarBuilders(
          outsideBuilder: (context, day, focused) => const SizedBox.shrink(),
          disabledBuilder: (context, day, focused) =>
              day.month != focused.month ? const SizedBox.shrink() : null,
          headerTitleBuilder: (context, day) {
            final name = monthName(day.month);
            return CalendarMonthHeader(
              month: day,
              title: '${name[0].toUpperCase()}${name.substring(1)} ${day.year}',
              firstMonth: firstDay,
              lastMonth: lastDay,
              onChangeMonth: onPageChanged,
            );
          },
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          dowTextFormatter: (date, _) => _weekdayInitials[date.weekday - 1],
          weekdayStyle: textTheme.labelSmall!.copyWith(color: AppColors.textMuted),
          weekendStyle: textTheme.labelSmall!.copyWith(color: AppColors.textMuted),
        ),
        calendarStyle: CalendarStyle(
          // Cambio 3: los días de otros meses existen (con nombre para el lector)
          // pero se dibujan vacíos; ocultos, table_calendar deja huecos
          // tocables sin etiqueta.
          outsideDaysVisible: true,
          cellMargin: const EdgeInsets.all(3),
          // Días con horas: cuadro morado claro; sin horas: texto gris.
          defaultDecoration: cell(AppColors.primaryContainer),
          weekendDecoration: cell(AppColors.primaryContainer),
          defaultTextStyle: dayText,
          weekendTextStyle: dayText,
          todayDecoration: cell(AppColors.primaryContainer),
          todayTextStyle: dayText.copyWith(color: AppColors.primary),
          disabledDecoration: cell(AppColors.surface),
          disabledTextStyle: TextStyle(color: AppColors.textMuted),
          selectedDecoration: cell(AppColors.primary),
          selectedTextStyle: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w700),
          markerDecoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          markerSize: 5,
          markersMaxCount: 1,
        ),
      ),
    );
  }
}
