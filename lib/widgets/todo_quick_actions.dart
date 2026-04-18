import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/todo_model.dart';
import '../services/hive_service.dart';
import 'todo_editor_sheet.dart';

/// 单击待办行时弹出的中央快捷操作弹窗：完成 / 修改 / 取消。
///
/// [onEditRequested] 可选自定义"修改"按钮行为（默认会 `showTodoEditor`）。
Future<void> showTodoQuickActions(
  BuildContext context,
  TodoModel todo, {
  VoidCallback? onEditRequested,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final doneLabel = todo.done ? '标记为未完成' : '完成';
      final doneIcon = todo.done ? Icons.undo : Icons.check_circle;

      return Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                todo.title.isEmpty ? '未命名任务' : todo.title,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
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
                                  style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  todo.note.trim().isEmpty
                                      ? '无'
                                      : todo.note.trim(),
                                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                        color: todo.note.trim().isEmpty
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
                                  style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatQuickActionRemind(todo),
                                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
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
                    child: _QuickActionButton(
                      icon: doneIcon,
                      label: doneLabel,
                      background: scheme.primary,
                      foreground: scheme.onPrimary,
                      onPressed: () {
                        Navigator.pop(ctx);
                        HiveService.toggleDone(todo.id);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.edit_outlined,
                      label: '修改',
                      background: scheme.secondaryContainer,
                      foreground: scheme.onSecondaryContainer,
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (onEditRequested != null) {
                          onEditRequested();
                        } else {
                          showTodoEditor(context, todo: todo);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.close,
                      label: '取消',
                      background: scheme.surfaceContainerHighest,
                      foreground: scheme.onSurfaceVariant,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _formatQuickActionRemind(TodoModel t) {
  final r = t.remindAt;
  if (r == null) return '未设置';
  final repeat = t.remindRepeatRule != TodoRepeat.none
      ? ' · ${TodoRepeat.label(t.remindRepeatRule)}'
      : '';
  if (t.remindIsAllDay) {
    return '${DateFormat('yyyy年M月d日').format(r)} 全天$repeat';
  }
  final now = DateTime.now();
  final dateStr = r.year != now.year
      ? DateFormat('yyyy/M/d').format(r)
      : DateFormat('M月d日').format(r);
  return '$dateStr ${DateFormat('HH:mm').format(r)}$repeat';
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
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
