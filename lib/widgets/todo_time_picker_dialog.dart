import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/todo_model.dart';

enum TodoPickerMode { point, range, allDay }

/// 返回给编辑器的选择结果
class TodoTimeSelection {
  final DateTime? start;
  final DateTime? end;
  final bool isAllDay;
  final int repeatRule;

  const TodoTimeSelection({
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.repeatRule,
  });

  bool get isEmpty => start == null && end == null;
}

/// 居中时间选择弹窗：
/// 顶部 Tab(时间点 / 时间段 / 全天) + 月历 + 时间行 + 重复行 + 取消/确定
class TodoTimePickerDialog extends StatefulWidget {
  const TodoTimePickerDialog({
    super.key,
    required this.title,
    this.initial,
  });

  final String title;
  final TodoTimeSelection? initial;

  static Future<TodoTimeSelection?> show(
    BuildContext context, {
    required String title,
    TodoTimeSelection? initial,
  }) {
    return showDialog<TodoTimeSelection>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => TodoTimePickerDialog(
        title: title,
        initial: initial,
      ),
    );
  }

  @override
  State<TodoTimePickerDialog> createState() => _TodoTimePickerDialogState();
}

class _TodoTimePickerDialogState extends State<TodoTimePickerDialog> {
  late TodoPickerMode _mode;
  late DateTime _visibleMonth;
  DateTime? _start;
  DateTime? _end;
  int _repeatRule = TodoRepeat.none;
  /// `initial == null` 时默认开启（与原先默认草稿时间一致）；若传入 `initial` 且 `start == null` 则关闭。
  late bool _reminderEnabled;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final now = DateTime.now();

    if (i == null || i.start == null) {
      _mode = TodoPickerMode.point;
      _start = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      _end = null;
      _repeatRule = TodoRepeat.none;
    } else {
      _start = i.start;
      _end = i.end;
      _repeatRule = i.repeatRule;
      if (i.isAllDay) {
        _mode = TodoPickerMode.allDay;
      } else if (i.end != null) {
        _mode = TodoPickerMode.range;
      } else {
        _mode = TodoPickerMode.point;
      }
    }
    final anchor = _start ?? now;
    _visibleMonth = DateTime(anchor.year, anchor.month);
    final ini = widget.initial;
    _reminderEnabled = ini == null || ini.start != null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final media = MediaQuery.of(context);
    // 小屏 / 横屏 / 系统导航条会挤占高度；不限制则 Column 底部溢出
    final maxH = (media.size.height -
            media.padding.vertical -
            media.viewInsets.bottom -
            32)
        .clamp(240.0, media.size.height * 0.92);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH, maxWidth: 420),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, scheme),
                const SizedBox(height: 8),
                _buildTabs(scheme),
                const SizedBox(height: 12),
                _buildMonthSwitcher(context, scheme),
                const SizedBox(height: 8),
                _buildWeekdayHeader(theme, scheme),
                const SizedBox(height: 4),
                _buildMonthGrid(context, scheme),
                const SizedBox(height: 8),
                if (_mode != TodoPickerMode.allDay) ...[
                  const Divider(height: 1),
                  Opacity(
                    opacity: _reminderEnabled ? 1.0 : 0.45,
                    child: IgnorePointer(
                      ignoring: !_reminderEnabled,
                      child: _buildTimeRow(context, scheme),
                    ),
                  ),
                ],
                _buildReminderSwitchRow(context, scheme),
                const Divider(height: 1),
                Opacity(
                  opacity: _reminderEnabled ? 1.0 : 0.45,
                  child: IgnorePointer(
                    ignoring: !_reminderEnabled,
                    child: _buildRepeatRow(context, scheme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Header: cancel / tab / confirm -----------------------------------

  Widget _buildHeader(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(56, 36),
          ),
          child: const Text('取消'),
        ),
        const Spacer(),
        TextButton(
          onPressed: _canConfirm() ? _onConfirm : null,
          style: TextButton.styleFrom(
            foregroundColor: scheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(56, 36),
          ),
          child: const Text(
            '确定',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs(ColorScheme scheme) {
    Widget tab(String label, TodoPickerMode mode) {
      final selected = _mode == mode;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _mode = mode;
            if (mode != TodoPickerMode.range) {
              _end = null;
            } else if (_start != null && _end == null) {
              final s = _start!;
              _end = DateTime(s.year, s.month, s.day, s.hour + 1, s.minute);
            }
            if (mode == TodoPickerMode.allDay && _start != null) {
              final s = _start!;
              _start = DateTime(s.year, s.month, s.day);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          tab('时间点', TodoPickerMode.point),
          const SizedBox(width: 4),
          tab('时间段', TodoPickerMode.range),
          const SizedBox(width: 4),
          tab('全天', TodoPickerMode.allDay),
        ],
      ),
    );
  }

  // --- Month switcher ---------------------------------------------------

  Widget _buildMonthSwitcher(BuildContext context, ColorScheme scheme) {
    final label =
        '${_visibleMonth.year}/${_visibleMonth.month.toString().padLeft(2, '0')}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => setState(() {
            _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month - 1);
          }),
          icon: const Icon(Icons.chevron_left),
          visualDensity: VisualDensity.compact,
          color: scheme.onSurfaceVariant,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        IconButton(
          onPressed: () => setState(() {
            _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month + 1);
          }),
          icon: const Icon(Icons.chevron_right),
          visualDensity: VisualDensity.compact,
          color: scheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader(ThemeData theme, ColorScheme scheme) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: labels
          .map((e) => Expanded(
                child: Center(
                  child: Text(
                    e,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  // --- Month grid -------------------------------------------------------

  Widget _buildMonthGrid(BuildContext context, ColorScheme scheme) {
    // 周一为一周起点
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final weekdayOfFirst = first.weekday; // 1..7 (Mon..Sun)
    final gridStart = first.subtract(Duration(days: weekdayOfFirst - 1));
    final today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 1.1,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final day = gridStart.add(Duration(days: index));
        final inMonth = day.month == _visibleMonth.month;
        final isToday = _sameDay(day, today);

        final s = _start;
        final e = _end;
        bool isStart = s != null && _sameDay(day, s);
        bool isEnd = e != null && _sameDay(day, e);
        bool inRange = false;
        if (_mode == TodoPickerMode.range && s != null && e != null) {
          final a = _dateOnly(s);
          final b = _dateOnly(e);
          final d = _dateOnly(day);
          inRange = !d.isBefore(a) && !d.isAfter(b);
        }
        final selected = isStart || isEnd;

        return _buildDayCell(
          context: context,
          scheme: scheme,
          day: day,
          inMonth: inMonth,
          isToday: isToday,
          selected: selected,
          inRange: inRange,
          onTap: () => _onPickDay(day),
        );
      },
    );
  }

  Widget _buildDayCell({
    required BuildContext context,
    required ColorScheme scheme,
    required DateTime day,
    required bool inMonth,
    required bool isToday,
    required bool selected,
    required bool inRange,
    required VoidCallback onTap,
  }) {
    final textColor = !inMonth
        ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
        : selected
            ? scheme.onPrimary
            : scheme.onSurface;

    final bg = selected
        ? scheme.primary
        : inRange
            ? scheme.primary.withValues(alpha: 0.16)
            : Colors.transparent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: isToday && !selected
              ? Border.all(color: scheme.primary, width: 1.2)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(
            color: textColor,
            fontWeight: selected || isToday ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _onPickDay(DateTime day) {
    setState(() {
      if (_mode == TodoPickerMode.range) {
        if (_start == null || (_start != null && _end != null)) {
          final h = _start?.hour ?? DateTime.now().hour;
          final m = _start?.minute ?? DateTime.now().minute;
          _start = DateTime(day.year, day.month, day.day, h, m);
          _end = null;
        } else {
          final s = _start!;
          final eh = s.hour + 1;
          final em = s.minute;
          var picked = DateTime(day.year, day.month, day.day, eh, em);
          if (picked.isBefore(s)) {
            // 点到更早日期：交换
            _end = s;
            _start = DateTime(day.year, day.month, day.day, s.hour, s.minute);
          } else {
            _end = picked;
          }
        }
      } else {
        final now = DateTime.now();
        final h = _mode == TodoPickerMode.allDay
            ? 0
            : (_start?.hour ?? now.hour);
        final mi = _mode == TodoPickerMode.allDay
            ? 0
            : (_start?.minute ?? now.minute);
        _start = DateTime(day.year, day.month, day.day, h, mi);
        _end = null;
      }
      _visibleMonth = DateTime(day.year, day.month);
    });
  }

  // --- Time row ---------------------------------------------------------

  Widget _buildTimeRow(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    Widget chip(String label, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('时间', style: theme.textTheme.bodyMedium),
          const Spacer(),
          if (_mode == TodoPickerMode.range) ...[
            chip(_formatHm(_start), () => _pickTime(isEnd: false)),
            Icon(Icons.arrow_right_alt, color: scheme.onSurfaceVariant),
            chip(_formatHm(_end ?? _start), () => _pickTime(isEnd: true)),
          ] else ...[
            chip(_formatHm(_start), () => _pickTime(isEnd: false)),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTime({required bool isEnd}) async {
    if (!_reminderEnabled) return;
    final base =
        (isEnd ? (_end ?? _start) : _start) ?? DateTime.now();
    var temp = DateTime(
      base.year,
      base.month,
      base.day,
      base.hour,
      base.minute,
    );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        setState(() {
                          if (isEnd) {
                            final anchor =
                                _end ?? _start ?? DateTime.now();
                            _end = DateTime(
                              anchor.year,
                              anchor.month,
                              anchor.day,
                              temp.hour,
                              temp.minute,
                            );
                            if (_start != null &&
                                _end!.isBefore(_start!)) {
                              final tmp = _start!;
                              _start = _end;
                              _end = tmp;
                            }
                          } else {
                            final anchor = _start ?? DateTime.now();
                            _start = DateTime(
                              anchor.year,
                              anchor.month,
                              anchor.day,
                              temp.hour,
                              temp.minute,
                            );
                            if (_end != null &&
                                _end!.isBefore(_start!)) {
                              _end = DateTime(
                                anchor.year,
                                anchor.month,
                                anchor.day,
                                temp.hour + 1,
                                temp.minute,
                              );
                            }
                          }
                        });
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 216,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: temp,
                  onDateTimeChanged: (d) {
                    temp = DateTime(
                      base.year,
                      base.month,
                      base.day,
                      d.hour,
                      d.minute,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReminderSwitchRow(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text('提醒', style: theme.textTheme.bodyMedium),
      subtitle: Text(
        '关闭后确定将不保存提醒时间',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      value: _reminderEnabled,
      onChanged: (v) => setState(() => _reminderEnabled = v),
    );
  }

  // --- Repeat row -------------------------------------------------------

  Widget _buildRepeatRow(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _pickRepeat,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.repeat, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('重复', style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              TodoRepeat.label(_repeatRule),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRepeat() async {
    if (!_reminderEnabled) return;
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: TodoRepeat.values.map((r) {
                return ListTile(
                  title: Text(TodoRepeat.label(r)),
                  trailing: r == _repeatRule
                      ? Icon(Icons.check,
                          color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, r),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
    if (result != null) setState(() => _repeatRule = result);
  }

  // --- Confirm / output -------------------------------------------------

  bool _canConfirm() {
    if (!_reminderEnabled) return true;
    if (_start == null) return false;
    if (_mode == TodoPickerMode.range) {
      return _end != null && !_end!.isBefore(_start!);
    }
    return true;
  }

  void _onConfirm() {
    if (!_canConfirm()) return;
    if (!_reminderEnabled) {
      Navigator.pop(
        context,
        const TodoTimeSelection(
          start: null,
          end: null,
          isAllDay: false,
          repeatRule: TodoRepeat.none,
        ),
      );
      return;
    }
    DateTime? s = _start;
    DateTime? e = _end;
    final allDay = _mode == TodoPickerMode.allDay;
    if (allDay && s != null) {
      s = DateTime(s.year, s.month, s.day);
      e = null;
    }
    if (_mode == TodoPickerMode.point) {
      e = null;
    }
    Navigator.pop(
      context,
      TodoTimeSelection(
        start: s,
        end: e,
        isAllDay: allDay,
        repeatRule: _repeatRule,
      ),
    );
  }

  // --- helpers ----------------------------------------------------------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatHm(DateTime? d) {
    if (d == null) return '--:--';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
