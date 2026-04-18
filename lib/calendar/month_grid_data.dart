import 'package:flutter/material.dart';

import 'calendar_almanac.dart';
import '../models/shift_model.dart';

int calendarDayKey(DateTime day) =>
    day.year * 10000 + day.month * 100 + day.day;

int calendarMonthKey(DateTime monthStart) =>
    monthStart.year * 100 + monthStart.month;

DateTime calendarMonthStart(DateTime d) => DateTime(d.year, d.month, 1);

Color shiftTypeColor(String shiftType, ColorScheme scheme) {
  switch (shiftType) {
    case '早班':
      return scheme.primary;
    case '中班':
      return scheme.tertiary;
    case '晚班':
      return scheme.secondary;
    case '夜班':
      return Colors.indigo;
    default:
      return scheme.outline;
  }
}

enum CalendarSubTextKind { lunar, solarTerm, holiday }

/// 单月网格中一天的视图数据（42 格之一）
class MonthCellVm {
  final DateTime day;
  final bool isOutside;
  final String subText;
  final CalendarSubTextKind subTextKind;
  final String? shiftLabel;
  final Color? shiftColor;

  const MonthCellVm({
    required this.day,
    required this.isOutside,
    required this.subText,
    required this.subTextKind,
    required this.shiftLabel,
    required this.shiftColor,
  });
}

/// 预计算整月 42 格（周一起算，6 行）
final class MonthGridData {
  final DateTime monthStart;
  final List<MonthCellVm> cells;

  const MonthGridData({required this.monthStart, required this.cells});

  static MonthGridData build({
    required DateTime monthStart,
    required Map<int, List<ShiftModel>> shiftsByDay,
    required ColorScheme colorScheme,
  }) {
    final firstOfMonth = DateTime(monthStart.year, monthStart.month, 1);
    final gridStart =
        firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));

    final cells = List<MonthCellVm>.generate(42, (i) {
      final day = gridStart.add(Duration(days: i));
      final dayKey = calendarDayKey(day);
      final isOutside = day.month != firstOfMonth.month;

      final shifts = shiftsByDay[dayKey];
      String? shiftLabel;
      Color? shiftColor;
      if (shifts != null && shifts.isNotEmpty) {
        final firstType = shifts.first.shiftType;
        final extra = shifts.length - 1;
        shiftLabel = extra > 0 ? '$firstType+$extra' : firstType;
        shiftColor = shiftTypeColor(firstType, colorScheme);
      }

      final lunar = CalendarAlmanac.solarToLunar(day);
      final holiday = CalendarAlmanac.holidayName(day, lunar);
      final solarTerm = CalendarAlmanac.solarTermName(day);

      final String subText;
      final CalendarSubTextKind subTextKind;
      if (holiday != null) {
        subText = holiday;
        subTextKind = CalendarSubTextKind.holiday;
      } else if (solarTerm != null) {
        subText = solarTerm;
        subTextKind = CalendarSubTextKind.solarTerm;
      } else {
        subText = CalendarAlmanac.lunarTextForSolar(day);
        subTextKind = CalendarSubTextKind.lunar;
      }

      return MonthCellVm(
        day: day,
        isOutside: isOutside,
        subText: subText,
        subTextKind: subTextKind,
        shiftLabel: shiftLabel,
        shiftColor: shiftColor,
      );
    });

    return MonthGridData(monthStart: firstOfMonth, cells: cells);
  }
}
