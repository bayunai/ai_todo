import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'models/todo_model.dart';
import 'services/hive_service.dart';
import 'widgets/todo_editor_sheet.dart';
import 'widgets/todo_quick_actions.dart';

/// 时间线 Tab：按提醒时间（remindAt）把待办排在一条竖直时间轴上。
///
/// 布局：
/// - 顶部：已逾期（remindAt 已过且未完成）
/// - 中部：按日期分组（今天 / 明天 / 其它日期）
/// - 末尾：以后（未设提醒时间的收纳分组）
class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<Box<TodoModel>>(
          valueListenable: HiveService.listenableTodos(),
          builder: (context, box, _) {
            final all = box.values.where((t) => !t.done).toList();
            final sections = _buildSections(all);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '时间线',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _subtitle(sections),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: sections.every((s) => s.items.isEmpty)
                      ? _buildEmpty(context, scheme)
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            12,
                            8,
                            12,
                            MediaQuery.viewPaddingOf(context).bottom + 120,
                          ),
                          itemCount: sections.length,
                          itemBuilder: (context, i) => _SectionBlock(
                            section: sections[i],
                            scheme: scheme,
                            theme: theme,
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom + 70,
        ),
        child: FloatingActionButton.extended(
          onPressed: () => showTodoEditor(
            context,
            defaultRemindAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          icon: const Icon(Icons.add),
          label: const Text('新建提醒'),
        ),
      ),
    );
  }

  String _subtitle(List<_Section> sections) {
    int overdue = 0;
    int today = 0;
    int upcoming = 0;
    for (final s in sections) {
      switch (s.kind) {
        case _SectionKind.overdue:
          overdue = s.items.length;
          break;
        case _SectionKind.today:
          today = s.items.length;
          break;
        case _SectionKind.date:
        case _SectionKind.later:
          upcoming += s.items.length;
          break;
      }
    }
    final parts = <String>[];
    if (overdue > 0) parts.add('逾期 $overdue');
    parts.add('今天 $today');
    if (upcoming > 0) parts.add('后续 $upcoming');
    return parts.join(' · ');
  }

  Widget _buildEmpty(BuildContext context, ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timelapse_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            '暂无待办',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '点右下角「新建提醒」或到「待办」页添加',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 将待办切成若干分组。已完成待办不进入时间线。
  List<_Section> _buildSections(List<TodoModel> todos) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final overdue = <_TimelineItem>[];
    final todayItems = <_TimelineItem>[];
    final dateBuckets = <DateTime, List<_TimelineItem>>{};
    final later = <_TimelineItem>[];

    for (final t in todos) {
      final r = t.remindAt;
      if (r == null) {
        later.add(_TimelineItem(todo: t, occursAt: null));
        continue;
      }
      if (r.isBefore(now)) {
        overdue.add(_TimelineItem(todo: t, occursAt: r));
        continue;
      }
      final day = DateTime(r.year, r.month, r.day);
      if (day.isAtSameMomentAs(today)) {
        todayItems.add(_TimelineItem(todo: t, occursAt: r));
      } else {
        dateBuckets.putIfAbsent(day, () => []).add(
              _TimelineItem(todo: t, occursAt: r),
            );
      }
    }

    int compareByTime(_TimelineItem a, _TimelineItem b) {
      final ao = a.occursAt;
      final bo = b.occursAt;
      if (ao == null && bo == null) return 0;
      if (ao == null) return 1;
      if (bo == null) return -1;
      return ao.compareTo(bo);
    }

    overdue.sort(compareByTime);
    todayItems.sort(compareByTime);
    for (final v in dateBuckets.values) {
      v.sort(compareByTime);
    }

    final sortedDays = dateBuckets.keys.toList()..sort();

    final sections = <_Section>[
      _Section(
        kind: _SectionKind.overdue,
        title: '已逾期',
        subtitle: overdue.isEmpty ? null : '点击处理',
        items: overdue,
      ),
      _Section(
        kind: _SectionKind.today,
        title: '今天',
        subtitle: _formatDayCn(today),
        items: todayItems,
      ),
      for (final d in sortedDays)
        _Section(
          kind: _SectionKind.date,
          title: d.isAtSameMomentAs(tomorrow) ? '明天' : _formatDayCn(d),
          subtitle: d.isAtSameMomentAs(tomorrow)
              ? DateFormat('M月d日').format(d)
              : null,
          items: dateBuckets[d]!,
        ),
      _Section(
        kind: _SectionKind.later,
        title: '以后',
        subtitle: later.isEmpty ? null : '未设提醒时间',
        items: later,
      ),
    ];

    // 空的分组不丢弃：「今天」始终保留作为参照；其它空分组过滤掉
    return sections
        .where((s) => s.kind == _SectionKind.today || s.items.isNotEmpty)
        .toList();
  }
}

enum _SectionKind { overdue, today, date, later }

class _Section {
  final _SectionKind kind;
  final String title;
  final String? subtitle;
  final List<_TimelineItem> items;

  const _Section({
    required this.kind,
    required this.title,
    this.subtitle,
    required this.items,
  });
}

class _TimelineItem {
  final TodoModel todo;

  /// 该项在时间线上的"具体触发时间"：
  /// - 普通提醒：remindAt 本身
  /// - 无 remindAt（以后分组）：null，不在左侧时间列显示
  final DateTime? occursAt;

  const _TimelineItem({required this.todo, required this.occursAt});
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.section,
    required this.scheme,
    required this.theme,
  });

  final _Section section;
  final ColorScheme scheme;
  final ThemeData theme;

  Color get _headerColor {
    switch (section.kind) {
      case _SectionKind.overdue:
        return scheme.error;
      case _SectionKind.today:
        return scheme.primary;
      case _SectionKind.date:
        return scheme.onSurface;
      case _SectionKind.later:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (section.items.isEmpty && section.kind != _SectionKind.today) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _headerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  section.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _headerColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (section.subtitle != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    section.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                if (section.items.isNotEmpty)
                  Text(
                    '${section.items.length} 项',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (section.items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 8, 16, 8),
              child: Text(
                '今天还没有提醒',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < section.items.length; i++)
              _TimelineRow(
                item: section.items[i],
                scheme: scheme,
                theme: theme,
                isFirst: i == 0,
                isLast: i == section.items.length - 1,
                isOverdueSection: section.kind == _SectionKind.overdue,
              ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.item,
    required this.scheme,
    required this.theme,
    required this.isFirst,
    required this.isLast,
    required this.isOverdueSection,
  });

  final _TimelineItem item;
  final ColorScheme scheme;
  final ThemeData theme;
  final bool isFirst;
  final bool isLast;
  final bool isOverdueSection;

  @override
  Widget build(BuildContext context) {
    final t = item.todo;
    final priColor = TodoPriority.color(t.priority, scheme);
    final isAllDay = t.remindIsAllDay;
    final nodeColor = isOverdueSection ? scheme.error : priColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 72,
            child: _TimeRail(
              time: item.occursAt,
              isAllDay: isAllDay,
              nodeColor: nodeColor,
              lineColor: scheme.outlineVariant,
              isFirst: isFirst,
              isLast: isLast,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 4, bottom: 10),
              child: _TimelineCard(
                todo: t,
                priColor: priColor,
                scheme: scheme,
                theme: theme,
                overdue: isOverdueSection,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRail extends StatelessWidget {
  const _TimeRail({
    required this.time,
    required this.isAllDay,
    required this.nodeColor,
    required this.lineColor,
    required this.isFirst,
    required this.isLast,
  });

  final DateTime? time;
  final bool isAllDay;
  final Color nodeColor;
  final Color lineColor;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final label = time == null
        ? '—'
        : isAllDay
            ? '全天'
            : DateFormat('HH:mm').format(time!);

    return CustomPaint(
      painter: _RailPainter(
        color: lineColor,
        isFirst: isFirst,
        isLast: isLast,
        nodeColor: nodeColor,
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.color,
    required this.nodeColor,
    required this.isFirst,
    required this.isLast,
  });

  final Color color;
  final Color nodeColor;
  final bool isFirst;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    // 竖直虚线：x 固定在右边距 8px
    final x = size.width - 8;
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // 节点半径
    const r = 5.0;
    final centerY = 16.0;

    // 画虚线：节点上方（若非首行）+ 节点下方（若非末行）
    void dashLine(double y1, double y2) {
      const dash = 3.0;
      const gap = 3.0;
      var y = y1;
      while (y < y2) {
        final next = (y + dash).clamp(y, y2);
        canvas.drawLine(Offset(x, y), Offset(x, next), line);
        y = next + gap;
      }
    }

    if (!isFirst) {
      dashLine(0, centerY - r);
    }
    if (!isLast) {
      dashLine(centerY + r, size.height);
    }

    // 节点圆点
    final fill = Paint()..color = nodeColor;
    canvas.drawCircle(Offset(x, centerY), r, fill);
    final ring = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(x, centerY), r + 1.5, ring);
  }

  @override
  bool shouldRepaint(covariant _RailPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.nodeColor != nodeColor ||
      oldDelegate.isFirst != isFirst ||
      oldDelegate.isLast != isLast;
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.todo,
    required this.priColor,
    required this.scheme,
    required this.theme,
    required this.overdue,
  });

  final TodoModel todo;
  final Color priColor;
  final ColorScheme scheme;
  final ThemeData theme;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final t = todo;
    final repeatLabel = t.remindRepeatRule == TodoRepeat.none
        ? null
        : TodoRepeat.label(t.remindRepeatRule);

    return Material(
      color: overdue
          ? scheme.errorContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showTodoQuickActions(context, t),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: priColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Checkbox(
                                value: t.done,
                                onChanged: (_) =>
                                    HiveService.toggleDone(t.id),
                                shape: const CircleBorder(),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title.isEmpty ? '未命名' : t.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (t.note.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    t.note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (repeatLabel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(left: 6, top: 2),
                              decoration: BoxDecoration(
                                color: scheme.tertiary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.repeat,
                                      size: 11, color: scheme.tertiary),
                                  const SizedBox(width: 2),
                                  Text(
                                    repeatLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.tertiary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (overdue || t.remindEndAt != null) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (overdue && t.remindAt != null)
                              _InlineBadge(
                                text:
                                    '已过 ${_humanizeAgo(t.remindAt!)}',
                                color: scheme.error,
                              ),
                            if (t.remindEndAt != null && t.remindAt != null)
                              _InlineBadge(
                                text: _rangeText(t.remindAt!, t.remindEndAt!),
                                color: scheme.tertiary,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 把日期格式化成"M月d日 周X"（不依赖 intl 的 locale 数据）
String _formatDayCn(DateTime d) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final wd = weekdays[(d.weekday - 1).clamp(0, 6)];
  return '${DateFormat('M月d日').format(d)} $wd';
}

String _humanizeAgo(DateTime past) {
  final diff = DateTime.now().difference(past);
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟';
  if (diff.inHours < 24) return '${diff.inHours}小时';
  return '${diff.inDays}天';
}

String _rangeText(DateTime start, DateTime end) {
  String hm(DateTime d) => DateFormat('HH:mm').format(d);
  final sameDay = start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (sameDay) return '${hm(start)}-${hm(end)}';
  return '${DateFormat('M/d HH:mm').format(start)} → ${DateFormat('M/d HH:mm').format(end)}';
}
