import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'models/todo_model.dart';
import 'services/hive_service.dart';
import 'services/notification_service.dart';

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

  /// 收到通知点击后：展开路径上的祖先，并打开该待办的编辑弹窗
  void _openTodoByNotification(String id) {
    final target = HiveService.getTodoById(id);
    if (target == null || !mounted) return;
    setState(() {
      var pid = target.parentId;
      while (pid != null) {
        _expanded.add(pid);
        final p = HiveService.getTodoById(pid);
        pid = p?.parentId;
      }
    });
    _openEditor(edit: target);
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
                                    _showQuickActions(context, row.todo),
                                onEdit: () => _openEditor(parentId: null, edit: row.todo),
                                onAddChild: () =>
                                    _openEditor(parentId: row.todo.id),
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
        child: FloatingActionButton.extended(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('添加待办'),
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
        text = '还没有待办，点右下角 “添加待办” 创建一条';
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
      final ad = a.dueAt;
      final bd = b.dueAt;
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
          return t.isOverdue;
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

  void _showQuickActions(BuildContext context, TodoModel todo) {
    showDialog<void>(
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
                  style: Theme.of(ctx).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
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
                          _openEditor(edit: todo);
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

  Future<void> _openEditor({String? parentId, TodoModel? edit}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TodoEditorSheet(
        initialParentId: edit?.parentId ?? parentId,
        editing: edit,
        allTodos: HiveService.getAllTodos(),
      ),
    );
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
      } else if (t.isOverdue) {
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
    final overdue = t.isOverdue;
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
                                        if (t.dueAt != null)
                                          _TimeChip(
                                            icon: Icons.event_outlined,
                                            text: _formatDateTime(t.dueAt!),
                                            color: overdue
                                                ? scheme.error
                                                : scheme.primary,
                                            scheme: scheme,
                                          ),
                                        if (t.remindAt != null)
                                          _TimeChip(
                                            icon: Icons
                                                .notifications_active_outlined,
                                            text:
                                                _formatDateTime(t.remindAt!),
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

String _formatDateTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(dt.year, dt.month, dt.day);
  final diff = target.difference(today).inDays;
  final hm = DateFormat('HH:mm').format(dt);
  if (diff == 0) return '今天 $hm';
  if (diff == 1) return '明天 $hm';
  if (diff == -1) return '昨天 $hm';
  if (dt.year == now.year) {
    return DateFormat('M月d日 HH:mm').format(dt);
  }
  return DateFormat('y年M月d日 HH:mm').format(dt);
}

// ============================================================
// 编辑/新建底部弹窗
// ============================================================

class _TodoEditorSheet extends StatefulWidget {
  const _TodoEditorSheet({
    required this.initialParentId,
    required this.editing,
    required this.allTodos,
  });

  final String? initialParentId;
  final TodoModel? editing;
  final List<TodoModel> allTodos;

  @override
  State<_TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends State<_TodoEditorSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  int _priority = TodoPriority.normal;
  DateTime? _dueAt;
  DateTime? _remindAt;
  String? _parentId;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _priority = e?.priority ?? TodoPriority.normal;
    _dueAt = e?.dueAt;
    _remindAt = e?.remindAt;
    _parentId = e?.parentId ?? widget.initialParentId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 编辑时，候选父节点不能是自身或自身的后代（避免成环）
  Set<String> _forbiddenParentIds() {
    final e = widget.editing;
    if (e == null) return const <String>{};
    return HiveService.collectSubtreeIds(e.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              _isEditing ? '编辑待办' : '新建待办',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              textInputAction: TextInputAction.next,
              autofocus: !_isEditing,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Text('紧急程度',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: TodoPriority.values.map((p) {
                final selected = _priority == p;
                final color = TodoPriority.color(p, scheme);
                return ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(
                    Icons.flag_rounded,
                    size: 14,
                    color: selected ? Colors.white : color,
                  ),
                  label: Text(
                    TodoPriority.label(p),
                    style: TextStyle(
                      color: selected ? Colors.white : scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: selected,
                  selectedColor: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                  side: BorderSide.none,
                  onSelected: (_) => setState(() => _priority = p),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _buildTimeRow(
              context: context,
              scheme: scheme,
              icon: Icons.event_outlined,
              label: '截止时间',
              value: _dueAt,
              onPick: () async {
                final picked = await _pickDateTime(_dueAt);
                if (picked != null) setState(() => _dueAt = picked);
              },
              onClear: () => setState(() => _dueAt = null),
            ),
            const SizedBox(height: 8),
            _buildTimeRow(
              context: context,
              scheme: scheme,
              icon: Icons.notifications_active_outlined,
              label: '提醒时间',
              value: _remindAt,
              onPick: () async {
                final picked = await _pickDateTime(_remindAt);
                if (picked != null) setState(() => _remindAt = picked);
              },
              onClear: () => setState(() => _remindAt = null),
            ),
            const SizedBox(height: 16),
            _buildParentSelector(context, scheme),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: Text(_isEditing ? '保存' : '添加'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRow({
    required BuildContext context,
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required DateTime? value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        if (value == null)
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加'),
          )
        else
          InputChip(
            avatar: Icon(Icons.schedule, size: 16, color: scheme.primary),
            label: Text(_formatDateTime(value)),
            onPressed: onPick,
            onDeleted: onClear,
            deleteIcon: const Icon(Icons.close, size: 16),
            side: BorderSide.none,
            backgroundColor: scheme.primary.withValues(alpha: 0.1),
          ),
      ],
    );
  }

  Widget _buildParentSelector(BuildContext context, ColorScheme scheme) {
    final forbidden = _forbiddenParentIds();
    final candidates = widget.allTodos
        .where((t) => !forbidden.contains(t.id))
        .toList();

    String labelOf(String? id) {
      if (id == null) return '无（作为顶级待办）';
      final t = widget.allTodos.firstWhere(
        (e) => e.id == id,
        orElse: () => TodoModel.create(title: '已删除'),
      );
      return t.title;
    }

    return Row(
      children: [
        Icon(Icons.account_tree_outlined,
            size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('父待办', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: candidates.any((c) => c.id == _parentId)
                ? _parentId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            items: <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(
                value: null,
                child: Text(labelOf(null)),
              ),
              ...candidates.map(
                (t) => DropdownMenuItem<String?>(
                  value: t.id,
                  child: Text(t.title, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _parentId = v),
          ),
        ),
      ],
    );
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final base = initial ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写标题')),
      );
      return;
    }

    // 若设置了提醒：先申请通知/精确闹钟权限，未授予也不阻塞保存，仅提示
    String? permWarning;
    if (_remindAt != null) {
      final granted = await NotificationService.ensurePermissions();
      if (!granted) {
        permWarning = '通知或精确闹钟权限未授予，提醒可能无法按时触发，可前往系统设置开启';
      }
    }

    final e = widget.editing;
    if (e == null) {
      final todo = TodoModel.create(
        title: title,
        note: _noteCtrl.text.trim(),
        priority: _priority,
        dueAt: _dueAt,
        remindAt: _remindAt,
        parentId: _parentId,
        orderIndex: HiveService.nextOrderIndex(_parentId),
      );
      await HiveService.addTodo(todo);
    } else {
      e.title = title;
      e.note = _noteCtrl.text.trim();
      e.priority = _priority;
      e.dueAt = _dueAt;
      e.remindAt = _remindAt;
      if (e.parentId != _parentId) {
        e.parentId = _parentId;
        e.orderIndex = HiveService.nextOrderIndex(_parentId);
      }
      await HiveService.updateTodo(e);
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();
    if (permWarning != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(permWarning)),
      );
    }
  }
}
