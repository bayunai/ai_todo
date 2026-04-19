import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/todo_model.dart';
import '../services/hive_service.dart';
import 'todo_editor_sheet.dart';

/// 快捷操作 UI 所需只读数据（主应用 / 悬浮窗共用）。
class TodoQuickActionViewData {
  const TodoQuickActionViewData({
    required this.id,
    required this.title,
    required this.note,
    required this.done,
    required this.remindAtMs,
    required this.remindEndAtMs,
    required this.remindIsAllDay,
    required this.remindRepeatRule,
  });

  final String id;
  final String title;
  final String note;
  final bool done;
  final int? remindAtMs;
  final int? remindEndAtMs;
  final bool remindIsAllDay;
  final int remindRepeatRule;

  factory TodoQuickActionViewData.fromModel(TodoModel t) {
    return TodoQuickActionViewData(
      id: t.id,
      title: t.title,
      note: t.note,
      done: t.done,
      remindAtMs: t.remindAt?.millisecondsSinceEpoch,
      remindEndAtMs: t.remindEndAt?.millisecondsSinceEpoch,
      remindIsAllDay: t.remindIsAllDay,
      remindRepeatRule: t.remindRepeatRule,
    );
  }

  /// 从 [map] 解析（悬浮窗侧）；字段缺失时尽量安全降级。
  factory TodoQuickActionViewData.fromMap(Map<Object?, Object?> map) {
    int? asInt(Object? o) {
      if (o == null) return null;
      if (o is int) return o;
      if (o is num) return o.toInt();
      return int.tryParse(o.toString());
    }

    bool asBool(Object? o, bool d) {
      if (o is bool) return o;
      return d;
    }

    return TodoQuickActionViewData(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      note: map['note']?.toString() ?? '',
      done: asBool(map['done'], false),
      remindAtMs: asInt(map['remindAt']),
      remindEndAtMs: asInt(map['remindEndAt']),
      remindIsAllDay: asBool(map['remindIsAllDay'], false),
      remindRepeatRule: asInt(map['remindRepeatRule']) ?? TodoRepeat.none,
    );
  }

  Map<String, dynamic> toShareMap() {
    return {
      'cmd': 'snapshot',
      'id': id,
      'title': title,
      'note': note,
      'done': done,
      'remindAt': remindAtMs,
      'remindEndAt': remindEndAtMs,
      'remindIsAllDay': remindIsAllDay,
      'remindRepeatRule': remindRepeatRule,
    };
  }
}

String formatQuickActionRemindFromData(TodoQuickActionViewData d) {
  final r = d.remindAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(d.remindAtMs!);
  if (r == null) return '未设置';
  final repeat = d.remindRepeatRule != TodoRepeat.none
      ? ' · ${TodoRepeat.label(d.remindRepeatRule)}'
      : '';
  if (d.remindIsAllDay) {
    return '${DateFormat('yyyy年M月d日').format(r)} 全天$repeat';
  }
  final now = DateTime.now();
  final dateStr = r.year != now.year
      ? DateFormat('yyyy/M/d').format(r)
      : DateFormat('M月d日').format(r);
  return '$dateStr ${DateFormat('HH:mm').format(r)}$repeat';
}

/// 与 [showTodoQuickActions] 弹窗 / 悬浮窗共用的中间内容区。
class TodoQuickActionsBody extends StatelessWidget {
  const TodoQuickActionsBody({
    super.key,
    required this.data,
    required this.onDone,
    required this.onEdit,
    required this.onCancel,
  });

  final TodoQuickActionViewData data;
  final VoidCallback onDone;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final doneLabel = data.done ? '标记为未完成' : '完成';
    final doneIcon = data.done ? Icons.undo : Icons.check_circle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          data.title.isEmpty ? '未命名任务' : data.title,
          style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '备注',
                            style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data.note.trim().isEmpty ? '无' : data.note.trim(),
                            style: theme.textTheme.bodySmall?.copyWith(
                                  color: data.note.trim().isEmpty
                                      ? scheme.onSurfaceVariant
                                      : scheme.onSurface,
                                ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '提醒时间',
                            style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatQuickActionRemindFromData(data),
                            style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TodoQuickActionButton(
                icon: doneIcon,
                label: doneLabel,
                background: scheme.primary,
                foreground: scheme.onPrimary,
                onPressed: onDone,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TodoQuickActionButton(
                icon: Icons.edit_outlined,
                label: '修改',
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
                onPressed: onEdit,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TodoQuickActionButton(
                icon: Icons.close,
                label: '取消',
                background: scheme.surfaceContainerHighest,
                foreground: scheme.onSurfaceVariant,
                onPressed: onCancel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 单击待办行时弹出的中央快捷操作弹窗：完成 / 修改 / 取消。
///
/// [onEditRequested] 可选自定义"修改"按钮行为（默认会 `showTodoEditor`）。
Future<void> showTodoQuickActions(
  BuildContext context,
  TodoModel todo, {
  VoidCallback? onEditRequested,
}) {
  final data = TodoQuickActionViewData.fromModel(todo);
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: TodoQuickActionsBody(
            data: data,
            onDone: () {
              Navigator.pop(ctx);
              HiveService.toggleDone(todo.id);
            },
            onEdit: () {
              Navigator.pop(ctx);
              if (onEditRequested != null) {
                onEditRequested();
              } else {
                showTodoEditor(context, todo: todo);
              }
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      );
    },
  );
}

class TodoQuickActionButton extends StatelessWidget {
  const TodoQuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
