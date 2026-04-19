import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/todo_model.dart';
import 'services/hive_service.dart';
import 'services/notification_service.dart';
import 'services/todo_overlay_bridge.dart';
import 'widgets/todo_editor_sheet.dart';
import 'widgets/todo_quick_actions.dart';

/// 未完成 && 提醒时间已过
bool _isTodoOverdue(TodoModel t) {
  if (t.done) return false;
  final r = t.remindAt;
  if (r == null) return false;
  return r.isBefore(DateTime.now());
}

enum TodoFilter { all, pending, done, overdue }

extension on TodoFilter {
  String get label {
    switch (this) {
      case TodoFilter.all:
        return '全部';
      case TodoFilter.pending:
        return '进行中';
      case TodoFilter.done:
        return '已完成';
      case TodoFilter.overdue:
        return '逾期';
    }
  }

  IconData get icon {
    switch (this) {
      case TodoFilter.all:
        return Icons.all_inbox_outlined;
      case TodoFilter.pending:
        return Icons.radio_button_unchecked;
      case TodoFilter.done:
        return Icons.check_circle_outline;
      case TodoFilter.overdue:
        return Icons.error_outline;
    }
  }
}

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  TodoFilter _filter = TodoFilter.all;
  final Set<String> _expanded = <String>{};
  StreamSubscription<String>? _notificationSub;

  @override
  void initState() {
    super.initState();
    // 冷启动：从通知拉起时，首帧完成后消费 pending payload
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = NotificationService.consumePendingPayload();
      if (pending != null) _openTodoByNotification(pending);
    });
    _notificationSub = NotificationService.onTap.listen((payload) {
      if (!mounted) return;
      _openTodoByNotification(payload);
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  /// 收到通知点击后：
  /// - `panel:add` → 打开新建待办编辑器
  /// - `panel:open` → 仅切换 Tab（MainPage 已处理）
  /// - 其它：按 todo.id 解析，展开祖先；Android 可开悬浮窗时优先悬浮窗，否则居中快捷弹窗。
  void _openTodoByNotification(String payload) {
    if (!mounted) return;
    if (payload == NotificationService.panelAddPayload) {
      showTodoEditor(context);
      return;
    }
    if (payload == NotificationService.panelOpenPayload) return;
    final target = HiveService.getTodoById(payload);
    if (target == null) return;
    setState(() {
      var pid = target.parentId;
      while (pid != null) {
        _expanded.add(pid);
        final p = HiveService.getTodoById(pid);
        pid = p?.parentId;
      }
    });
    unawaited(_openTodoQuickUiAfterExpand(payload, target));
  }

  Future<void> _openTodoQuickUiAfterExpand(
    String payload,
    TodoModel target,
  ) async {
    if (await TodoOverlayBridge.consumeOverlaySkipTodoQuickUiIfShowing(
          payload,
        )) {
      return;
    }
    final usedOverlay =
        await TodoOverlayBridge.tryShowQuickActionsForTodoId(payload);
    if (!mounted) return;
    if (!usedOverlay) {
      showTodoQuickActions(context, target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<Box<TodoModel>>(
          valueListenable: HiveService.listenableTodos(),
          builder: (context, box, _) {
            final all = box.values.toList();
            final stats = _Stats.from(all);
            final rows = _flatten(all);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _buildHeader(context, scheme, stats),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFilterBar(context, scheme, stats),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: rows.isEmpty
                      ? _buildEmpty(context, scheme)
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            12,
                            8,
                            12,
                            MediaQuery.viewPaddingOf(context).bottom + 120,
                          ),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _TodoCard(
                                row: row,
                                scheme: scheme,
                                onToggleDone: () =>
                                    HiveService.toggleDone(row.todo.id),
                                onToggleExpand: () => setState(() {
                                  if (_expanded.contains(row.todo.id)) {
                                    _expanded.remove(row.todo.id);
                                  } else {
                                    _expanded.add(row.todo.id);
                                  }
                                }),
                                onQuickActions: () =>
                                    showTodoQuickActions(context, row.todo),
                                onEdit: () =>
                                    showTodoEditor(context, todo: row.todo),
                                onAddChild: () => showTodoEditor(context,
                                    parentId: row.todo.id),
                                onDelete: () => _confirmDelete(row.todo),
                              ),
                            );
                          },
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
        child: FloatingActionButton(
          onPressed: () => showTodoEditor(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme scheme, _Stats stats) {
    final theme = Theme.of(context);
    final pct = stats.total == 0 ? 0.0 : stats.done / stats.total;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '待办',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stats.total == 0
                    ? '今天还没有待办'
                    : '已完成 ${stats.done}/${stats.total}'
                        '${stats.overdue > 0 ? '  ·  逾期 ${stats.overdue}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    ColorScheme scheme,
    _Stats stats,
  ) {
    int countOf(TodoFilter f) {
      switch (f) {
        case TodoFilter.all:
          return stats.total;
        case TodoFilter.pending:
          return stats.pending;
        case TodoFilter.done:
          return stats.done;
        case TodoFilter.overdue:
          return stats.overdue;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      child: Row(
        children: TodoFilter.values.map((f) {
          final selected = _filter == f;
          final count = countOf(f);
          final isOverdue = f == TodoFilter.overdue;
          final activeColor = isOverdue ? scheme.error : scheme.primary;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(
                f.icon,
                size: 16,
                color: selected ? Colors.white : activeColor,
              ),
              label: Text(
                count > 0 ? '${f.label} $count' : f.label,
                style: TextStyle(
                  color: selected ? Colors.white : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              selected: selected,
              showCheckmark: false,
              selectedColor: activeColor,
              backgroundColor: scheme.surfaceContainerHighest,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (_) => setState(() => _filter = f),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    String text;
    IconData icon;
    switch (_filter) {
      case TodoFilter.done:
        text = '还没有已完成的待办';
        icon = Icons.task_alt;
        break;
      case TodoFilter.overdue:
        text = '没有逾期的待办，继续保持！';
        icon = Icons.celebration_outlined;
        break;
      case TodoFilter.pending:
        text = '没有进行中的待办';
        icon = Icons.beach_access_outlined;
        break;
      case TodoFilter.all:
        text = '还没有待办，点右下角「+」创建一条';
        icon = Icons.checklist_rtl_outlined;
        break;
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 把树压成可见行列表，包含 [_filter] 过滤逻辑。
  List<_TodoRowVm> _flatten(List<TodoModel> all) {
    final byParent = <String?, List<TodoModel>>{};
    for (final t in all) {
      byParent.putIfAbsent(t.parentId, () => []).add(t);
    }

    int compare(TodoModel a, TodoModel b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.priority != b.priority) return a.priority.compareTo(b.priority);
      final ad = a.remindAt;
      final bd = b.remindAt;
      if (ad != null && bd != null) {
        final cmp = ad.compareTo(bd);
        if (cmp != 0) return cmp;
      } else if (ad != null) {
        return -1;
      } else if (bd != null) {
        return 1;
      }
      return a.orderIndex.compareTo(b.orderIndex);
    }

    for (final list in byParent.values) {
      list.sort(compare);
    }

    bool matches(TodoModel t) {
      switch (_filter) {
        case TodoFilter.all:
          return true;
        case TodoFilter.pending:
          return !t.done;
        case TodoFilter.done:
          return t.done;
        case TodoFilter.overdue:
          return _isTodoOverdue(t);
      }
    }

    // 计算每个节点的后代是否含命中项，用于在筛选时保留上下文
    final hasMatch = <String, bool>{};
    bool computeHas(TodoModel t) {
      if (hasMatch.containsKey(t.id)) return hasMatch[t.id]!;
      var any = matches(t);
      for (final c in byParent[t.id] ?? const <TodoModel>[]) {
        if (computeHas(c)) any = true;
      }
      hasMatch[t.id] = any;
      return any;
    }

    for (final t in all) {
      computeHas(t);
    }

    int doneDescendants(TodoModel t) {
      var n = 0;
      for (final c in byParent[t.id] ?? const <TodoModel>[]) {
        if (c.done) n++;
        n += doneDescendants(c);
      }
      return n;
    }

    int totalDescendants(TodoModel t) {
      var n = 0;
      for (final c in byParent[t.id] ?? const <TodoModel>[]) {
        n += 1 + totalDescendants(c);
      }
      return n;
    }

    final result = <_TodoRowVm>[];
    void visit(TodoModel t, int depth) {
      final children = byParent[t.id] ?? const <TodoModel>[];
      final hasChildren = children.isNotEmpty;
      final selfMatch = matches(t);
      final descMatch = (hasMatch[t.id] ?? false) && !selfMatch;
      // 仅在自身命中或后代命中时显示
      if (!selfMatch && !descMatch) return;
      final expanded = _expanded.contains(t.id);
      final total = totalDescendants(t);
      final doneN = doneDescendants(t);
      result.add(
        _TodoRowVm(
          todo: t,
          depth: depth,
          hasChildren: hasChildren,
          expanded: expanded,
          totalDescendants: total,
          doneDescendants: doneN,
          faded: descMatch && !selfMatch,
        ),
      );
      if (hasChildren && expanded) {
        for (final c in children) {
          visit(c, depth + 1);
        }
      }
    }

    for (final t in byParent[null] ?? const <TodoModel>[]) {
      visit(t, 0);
    }
    return result;
  }

  Future<void> _confirmDelete(TodoModel todo) async {
    final descendants = HiveService.collectSubtreeIds(todo.id).length - 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除待办'),
        content: Text(
          descendants > 0
              ? '将同时删除该待办及其 $descendants 个子待办，确定继续吗？'
              : '确定删除「${todo.title}」吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await HiveService.deleteSubtree(todo.id);
    }
  }
}

class _Stats {
  final int total;
  final int done;
  final int pending;
  final int overdue;

  const _Stats({
    required this.total,
    required this.done,
    required this.pending,
    required this.overdue,
  });

  factory _Stats.from(List<TodoModel> all) {
    var done = 0;
    var overdue = 0;
    for (final t in all) {
      if (t.done) {
        done++;
      } else if (_isTodoOverdue(t)) {
        overdue++;
      }
    }
    return _Stats(
      total: all.length,
      done: done,
      pending: all.length - done,
      overdue: overdue,
    );
  }
}

class _TodoRowVm {
  final TodoModel todo;
  final int depth;
  final bool hasChildren;
  final bool expanded;
  final int totalDescendants;
  final int doneDescendants;
  final bool faded;

  const _TodoRowVm({
    required this.todo,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
    required this.totalDescendants,
    required this.doneDescendants,
    required this.faded,
  });
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({
    required this.row,
    required this.scheme,
    required this.onToggleDone,
    required this.onToggleExpand,
    required this.onQuickActions,
    required this.onEdit,
    required this.onAddChild,
    required this.onDelete,
  });

  final _TodoRowVm row;
  final ColorScheme scheme;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleExpand;
  final VoidCallback onQuickActions;
  final VoidCallback onEdit;
  final VoidCallback onAddChild;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = row.todo;
    final priColor = TodoPriority.color(t.priority, scheme);
    final theme = Theme.of(context);
    final overdue = _isTodoOverdue(t);
    final indent = row.depth * 16.0;

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(
          alpha: t.done ? 0.25 : 0.45,
        ),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onQuickActions,
          onLongPress: () => _showActionMenu(context),
          child: Opacity(
            opacity: row.faded ? 0.55 : 1.0,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: priColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: Checkbox(
                                  value: t.done,
                                  onChanged: (_) => onToggleDone(),
                                  shape: const CircleBorder(),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.title,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            decoration: t.done
                                                ? TextDecoration.lineThrough
                                                : null,
                                            color: t.done
                                                ? scheme.onSurfaceVariant
                                                : scheme.onSurface,
                                          ),
                                    ),
                                    if (t.note.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        t.note,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _PriorityChip(
                                          priority: t.priority,
                                          scheme: scheme,
                                        ),
                                        if (t.remindAt != null)
                                          _TimeChip(
                                            icon: t.remindNotifyEnabled
                                                ? Icons
                                                    .notifications_active_outlined
                                                : Icons
                                                    .notifications_off_outlined,
                                            text: formatTodoTime(
                                              start: t.remindAt,
                                              end: t.remindEndAt,
                                              isAllDay: t.remindIsAllDay,
                                            ),
                                            color: overdue
                                                ? scheme.error
                                                : scheme.tertiary,
                                            scheme: scheme,
                                          ),
                                        if (t.remindRepeatRule !=
                                            TodoRepeat.none)
                                          _TimeChip(
                                            icon: Icons.repeat,
                                            text: TodoRepeat.label(
                                                t.remindRepeatRule),
                                            color: scheme.tertiary,
                                            scheme: scheme,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (row.hasChildren)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: AnimatedRotation(
                                    duration:
                                        const Duration(milliseconds: 180),
                                    turns: row.expanded ? 0.5 : 0,
                                    child: const Icon(
                                      Icons.expand_more,
                                      size: 22,
                                    ),
                                  ),
                                  onPressed: onToggleExpand,
                                ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.more_vert, size: 20),
                                onPressed: () => _showActionMenu(context),
                              ),
                            ],
                          ),
                          if (row.hasChildren) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '${row.doneDescendants}/${row.totalDescendants}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: row.totalDescendants == 0
                                          ? 0
                                          : row.doneDescendants /
                                              row.totalDescendants,
                                      minHeight: 3,
                                      backgroundColor:
                                          scheme.surfaceContainerHighest,
                                      color: priColor,
                                    ),
                                  ),
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
        ),
      ),
    );
  }

  void _showActionMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(ctx);
                  onEdit();
                },
              ),
              ListTile(
                leading: const Icon(Icons.subdirectory_arrow_right),
                title: const Text('添加子待办'),
                onTap: () {
                  Navigator.pop(ctx);
                  onAddChild();
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  '删除',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority, required this.scheme});
  final int priority;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final color = TodoPriority.color(priority, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            TodoPriority.label(priority),
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.icon,
    required this.text,
    required this.color,
    required this.scheme,
  });
  final IconData icon;
  final String text;
  final Color color;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

