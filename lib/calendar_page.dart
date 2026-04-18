import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'calendar/month_grid_data.dart';
import 'models/shift_model.dart';
import 'services/hive_service.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

enum ViewType { day, week, month }

class _CalendarPageState extends State<CalendarPage> {
  static const int _firstCalendarYear = 2020;
  static const int _lastCalendarYear = 2030;
  static int get _monthPageCount =>
      (_lastCalendarYear - _firstCalendarYear + 1) * 12;

  static int _monthPageIndexForMonthStart(DateTime monthStart) =>
      (monthStart.year - _firstCalendarYear) * 12 + (monthStart.month - 1);

  ViewType _viewType = ViewType.month;
  DateTime _selectedDay = DateTime.now();

  /// 当前可见月份页索引；用 [ValueNotifier] 更新，避免滑页结束时 setState 整树重建导致格子宽度取整抖动
  late final ValueNotifier<int> _visibleMonthNv;

  final Map<int, List<ShiftModel>> _shiftsByDayIndex = {};
  final Map<int, MonthGridData> _monthGridCache = {};

  /// 必须在 initState 前完成构造；initialPage 与 [_visibleMonthNv] 一致
  final PageController _monthPageController = PageController(
    initialPage: _monthPageIndexForMonthStart(
      DateTime(DateTime.now().year, DateTime.now().month, 1),
    ),
  );

  Timer? _hiveDebounce;

  final DateFormat _monthFormat = DateFormat('M月', 'zh_CN');
  final DateFormat _weekFormat = DateFormat('M月 第W周', 'zh_CN');
  final DateFormat _dayFormat = DateFormat('MM/dd EEEE', 'zh_CN');

  @override
  void initState() {
    super.initState();
    _visibleMonthNv = ValueNotifier(
      _monthPageIndexForMonthStart(
        DateTime(DateTime.now().year, DateTime.now().month, 1),
      ),
    );
    Hive.box<ShiftModel>(HiveService.shiftsBoxName)
        .listenable()
        .addListener(_onBoxChanged);
    _rebuildDayIndexes();
  }

  @override
  void dispose() {
    _hiveDebounce?.cancel();
    _visibleMonthNv.dispose();
    Hive.box<ShiftModel>(HiveService.shiftsBoxName)
        .listenable()
        .removeListener(_onBoxChanged);
    _monthPageController.dispose();
    super.dispose();
  }

  void _onBoxChanged() {
    _hiveDebounce?.cancel();
    _hiveDebounce = Timer(const Duration(milliseconds: 40), () {
      if (!mounted) return;
      _rebuildDayIndexes();
      setState(() {});
    });
  }

  int _monthPageIndexFor(DateTime monthStart) =>
      _monthPageIndexForMonthStart(monthStart);

  DateTime _monthStartFromPageIndex(int pageIndex) {
    final m = pageIndex + 1;
    final y = _firstCalendarYear + (m - 1) ~/ 12;
    final month = ((m - 1) % 12) + 1;
    return DateTime(y, month, 1);
  }

  void _rebuildDayIndexes() {
    _shiftsByDayIndex.clear();
    _monthGridCache.clear();

    final shiftsBox = Hive.box<ShiftModel>(HiveService.shiftsBoxName);
    for (final shift in shiftsBox.values) {
      final key = calendarDayKey(shift.date);
      (_shiftsByDayIndex[key] ??= <ShiftModel>[]).add(shift);
    }

  }

  MonthGridData _monthDataFor(
    DateTime monthStart,
    ColorScheme scheme,
  ) {
    final key = calendarMonthKey(monthStart);
    return _monthGridCache.putIfAbsent(
      key,
      () => MonthGridData.build(
        monthStart: monthStart,
        shiftsByDay: _shiftsByDayIndex,
        colorScheme: scheme,
      ),
    );
  }

  List<ShiftModel> _getShiftsForDay(DateTime day) {
    final key = calendarDayKey(day);
    return _shiftsByDayIndex[key] ?? const <ShiftModel>[];
  }

  void _onMonthPageChanged(int index) {
    if (!mounted || index == _visibleMonthNv.value) return;
    _visibleMonthNv.value = index;
  }

  void _onCalendarDayTapped(DateTime day) {
    final page = _monthPageIndexFor(calendarMonthStart(day));
    setState(() => _selectedDay = day);
    if (_monthPageController.hasClients &&
        _monthPageController.page?.round() != page) {
      _monthPageController.jumpToPage(page);
    }
  }

  void _goToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final page = _monthPageIndexFor(calendarMonthStart(today));
    setState(() => _selectedDay = today);
    if (_viewType != ViewType.month) return;
    if (_monthPageController.hasClients) {
      if (_monthPageController.page?.round() != page) {
        _monthPageController.jumpToPage(page);
      } else {
        _visibleMonthNv.value = page;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top + 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildHeader(context, scheme),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _viewType == ViewType.day
                  ? _buildDayView(context, scheme)
                  : _viewType == ViewType.week
                      ? _buildWeekView(context, scheme)
                      : _buildMonthView(context, scheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IntrinsicWidth(
            child: SegmentedButton<ViewType>(
              segments: const <ButtonSegment<ViewType>>[
                ButtonSegment<ViewType>(
                  value: ViewType.day,
                  label: Text('日'),
                  icon: Icon(Icons.today_outlined, size: 18),
                ),
                ButtonSegment<ViewType>(
                  value: ViewType.week,
                  label: Text('周'),
                  icon: Icon(Icons.view_week_outlined, size: 18),
                ),
                ButtonSegment<ViewType>(
                  value: ViewType.month,
                  label: Text('月'),
                  icon: Icon(Icons.calendar_month_outlined, size: 18),
                ),
              ],
              selected: <ViewType>{_viewType},
              onSelectionChanged: (Set<ViewType> next) {
                setState(() => _viewType = next.first);
                if (_viewType == ViewType.month) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    final p =
                        _monthPageIndexFor(calendarMonthStart(_selectedDay));
                    if (_monthPageController.hasClients &&
                        _monthPageController.page?.round() != p) {
                      _monthPageController.jumpToPage(p);
                    }
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _viewType == ViewType.month
            ? ValueListenableBuilder<int>(
                valueListenable: _visibleMonthNv,
                builder: (context, pageIdx, _) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          _monthFormat.format(
                            _monthStartFromPageIndex(pageIdx),
                          ),
                          textAlign: TextAlign.start,
                          style: titleStyle,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _goToToday,
                        icon: Icon(
                          Icons.event_available_outlined,
                          size: 20,
                          color: scheme.primary,
                        ),
                        label: Text(
                          '今日',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  );
                },
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _viewType == ViewType.week
                      ? _weekFormat.format(_selectedDay)
                      : _dayFormat.format(_selectedDay),
                  textAlign: TextAlign.start,
                  style: titleStyle,
                ),
              ),
      ],
    );
  }

  Widget _buildMonthView(BuildContext context, ColorScheme scheme) {
    final today = DateTime.now();
    final todayKey = calendarDayKey(
      DateTime(today.year, today.month, today.day),
    );

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildWeekdayRow(scheme),
          Expanded(
            child: PageView.builder(
              controller: _monthPageController,
              itemCount: _monthPageCount,
              clipBehavior: Clip.hardEdge,
              onPageChanged: _onMonthPageChanged,
              // BouncingScrollPhysics 在页面对齐结束时常有轻微回弹，左右边缘列最明显
              physics: const ClampingScrollPhysics(),
              itemBuilder: (context, pageIndex) {
                final monthStart = _monthStartFromPageIndex(pageIndex);
                final data = _monthDataFor(monthStart, scheme);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                  child: _MonthGridBody(
                    cells: data.cells,
                    visibleMonthStart: monthStart,
                    selectedDay: _selectedDay,
                    todayKey: todayKey,
                    colorScheme: scheme,
                    onDayTap: _onCalendarDayTapped,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayRow(ColorScheme scheme) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: List.generate(7, (i) {
          final weekend = i >= 5;
          return Expanded(
            child: Center(
              child: Text(
                labels[i],
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: weekend ? scheme.error : scheme.onSurfaceVariant,
                    ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayView(BuildContext context, ColorScheme scheme) {
    final shifts = _getShiftsForDay(_selectedDay);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '全天',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: shifts.isEmpty
                          ? [
                              Text(
                                '当日无班次',
                                style: TextStyle(color: scheme.outline),
                              ),
                            ]
                          : shifts
                              .map(
                                (shift) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Material(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () {},
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: shiftTypeColor(
                                                  shift.shiftType,
                                                  scheme,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    shift.shiftType,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                  Text(
                                                    '班表',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 24 * 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 24,
                      itemBuilder: (context, index) {
                        return SizedBox(
                          height: 56,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${index.toString().padLeft(2, '0')}:00',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: scheme.outline),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      child: ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 24,
                        itemBuilder: (context, index) {
                          return Container(
                            height: 56,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekView(BuildContext context, ColorScheme scheme) {
    final weekday = _selectedDay.weekday;
    final startOfWeek = _selectedDay.subtract(Duration(days: weekday - 1));
    final weekDays =
        List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
    const weekDayNames = ['一', '二', '三', '四', '五', '六', '日'];

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Center(
                    child: Text(
                      '全天',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: weekDays.map((day) {
                      final shifts = _getShiftsForDay(day);
                      return Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ),
                          child: shifts.isEmpty
                              ? null
                              : Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: shiftTypeColor(
                                      shifts.first.shiftType,
                                      scheme,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    shifts.first.shiftType,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: weekDays.asMap().entries.map((e) {
                      final i = e.key;
                      final day = e.value;
                      final weekend =
                          day.weekday == DateTime.saturday ||
                              day.weekday == DateTime.sunday;
                      return Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              bottom: BorderSide(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                weekDayNames[i],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: weekend
                                      ? scheme.error
                                      : scheme.onSurface,
                                ),
                              ),
                              Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: weekend
                                      ? scheme.error
                                      : scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 48,
                    child: Column(
                      children: List.generate(24, (index) {
                        return SizedBox(
                          height: 52,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6, top: 2),
                              child: Text(
                                '${index.toString().padLeft(2, '0')}:00',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: scheme.outline),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: weekDays.map((day) {
                        return Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            child: Column(
                              children: List.generate(24, (index) {
                                return Container(
                                  height: 52,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: scheme.outlineVariant
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthGridBody extends StatelessWidget {
  const _MonthGridBody({
    required this.cells,
    required this.visibleMonthStart,
    required this.selectedDay,
    required this.todayKey,
    required this.colorScheme,
    required this.onDayTap,
  });

  final List<MonthCellVm> cells;
  final DateTime visibleMonthStart;
  final DateTime selectedDay;
  final int todayKey;
  final ColorScheme colorScheme;
  final void Function(DateTime day) onDayTap;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iw = constraints.maxWidth.round().clamp(1, 1 << 20);
        final ih = constraints.maxHeight.round().clamp(1, 1 << 20);
        final colBase = iw ~/ 7;
        final colExtra = iw % 7;
        double colW(int c) =>
            (colBase + (c < colExtra ? 1 : 0)).toDouble();
        final rowBase = ih ~/ 6;
        final rowExtra = ih % 6;
        double rowH(int r) =>
            (rowBase + (r < rowExtra ? 1 : 0)).toDouble();

        return Column(
          children: List.generate(6, (row) {
            return SizedBox(
              height: rowH(row),
              child: Row(
                children: List.generate(7, (col) {
                  final i = row * 7 + col;
                  final vm = cells[i];
                  final dayKey = calendarDayKey(vm.day);
                  final selected = _sameDay(vm.day, selectedDay) &&
                      _sameMonth(vm.day, visibleMonthStart);
                  final isToday = dayKey == todayKey;

                  return SizedBox(
                    width: colW(col),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: _MonthDayTile(
                        vm: vm,
                        selected: selected,
                        isToday: isToday,
                        scheme: colorScheme,
                        onTap: () => onDayTap(vm.day),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        );
      },
    );
  }
}

class _MonthDayTile extends StatelessWidget {
  const _MonthDayTile({
    required this.vm,
    required this.selected,
    required this.isToday,
    required this.scheme,
    required this.onTap,
  });

  final MonthCellVm vm;
  final bool selected;
  final bool isToday;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekend =
        vm.day.weekday == DateTime.saturday || vm.day.weekday == DateTime.sunday;

    Color dayNumColor;
    if (vm.isOutside) {
      dayNumColor = scheme.outline.withValues(alpha: 0.45);
    } else if (weekend) {
      dayNumColor = scheme.error;
    } else {
      dayNumColor = scheme.onSurface;
    }

    if (selected) {
      dayNumColor = scheme.onPrimaryContainer;
    }

    Color subColor;
    if (selected) {
      subColor = scheme.onPrimaryContainer.withValues(alpha: 0.9);
    } else if (vm.isOutside) {
      subColor = scheme.outline.withValues(alpha: 0.35);
    } else {
      switch (vm.subTextKind) {
        case CalendarSubTextKind.holiday:
          subColor = scheme.error;
        case CalendarSubTextKind.solarTerm:
          subColor = scheme.primary;
        case CalendarSubTextKind.lunar:
          subColor = scheme.onSurfaceVariant;
      }
    }

    final showTodayRing = isToday && !selected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: scheme.primary.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: showTodayRing
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.35),
              width: showTodayRing ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isToday ? '今' : '${vm.day.day}',
                maxLines: 1,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: dayNumColor,
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                vm.subText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: subColor,
                      height: 1.05,
                    ),
              ),
              if (vm.shiftLabel != null && vm.shiftColor != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: vm.shiftColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    vm.shiftLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
