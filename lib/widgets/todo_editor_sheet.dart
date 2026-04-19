import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/todo_model.dart';
import '../services/hive_service.dart';
import '../services/notification_service.dart';
import 'todo_time_picker_dialog.dart';

/// 打开编辑/新建待办的底部弹窗。
///
/// - [todo] 非空则是编辑该待办；空则新建
/// - [parentId] 新建子待办时传入父 id
/// - [defaultRemindAt] 新建场景下预填的提醒时间（例如时间线入口按 now+1h）
Future<void> showTodoEditor(
  BuildContext context, {
  TodoModel? todo,
  String? parentId,
  DateTime? defaultRemindAt,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => TodoEditorSheet(
      initialParentId: todo?.parentId ?? parentId,
      editing: todo,
      allTodos: HiveService.getAllTodos(),
      defaultRemindAt: defaultRemindAt,
    ),
  );
}

/// 编辑/新建待办底部弹窗。直接使用 [showTodoEditor] 更方便，
/// 若需自定义容器可以直接 new 这个 widget。
class TodoEditorSheet extends StatefulWidget {
  const TodoEditorSheet({
    super.key,
    required this.initialParentId,
    required this.editing,
    required this.allTodos,
    this.defaultRemindAt,
  });

  final String? initialParentId;
  final TodoModel? editing;
  final List<TodoModel> allTodos;
  final DateTime? defaultRemindAt;

  @override
  State<TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends State<TodoEditorSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  int _priority = TodoPriority.normal;
  DateTime? _remindAt;
  DateTime? _remindEndAt;
  bool _remindIsAllDay = false;
  int _remindRepeat = TodoRepeat.none;
  String? _parentId;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _priority = e?.priority ?? TodoPriority.normal;
    _remindAt = e?.remindAt ?? widget.defaultRemindAt;
    _remindEndAt = e?.remindEndAt;
    _remindIsAllDay = e?.remindIsAllDay ?? false;
    _remindRepeat = e?.remindRepeatRule ?? TodoRepeat.none;
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
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    // 不用固定 height 的 SizedBox，避免内容少时整块撑满 88% 屏高；内层 Column 必须 min，
    // 否则在 Expanded 里会纵向撑满，父待办下出现大块空白。
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(context, scheme),
            Flexible(
              fit: FlexFit.loose,
              child: ListView(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
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
                  _buildParentSelector(context, scheme),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            _buildMetaToolbar(context, scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _save,
            child: Text(_isEditing ? '保存' : '添加'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaToolbar(BuildContext context, ColorScheme scheme) {
    final hasRemind = _remindAt != null;
    final remindSummary = hasRemind
        ? formatTodoTime(
            start: _remindAt,
            end: _remindEndAt,
            isAllDay: _remindIsAllDay,
          )
        : '设置提醒时间';

    // 略大于此前「一半」尺寸；底边留出安全区 + 额外间距，避免贴底被圆角/手势条裁切
    const double kIconSize = 18;
    const double kBtn = 36;
    final bottomInset =
        MediaQuery.viewPaddingOf(context).bottom + 14;
    final remindColor = scheme.primary;
    final remindBg = remindColor.withValues(alpha: 0.14);
    final priColor = TodoPriority.color(_priority, scheme);
    final priBg = priColor.withValues(alpha: 0.14);

    ButtonStyle smallColoredIcon({
      required Color fg,
      required Color bg,
    }) {
      return IconButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(kBtn, kBtn),
        maximumSize: const Size(kBtn, kBtn),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );
    }

    return Material(
      color: scheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, bottomInset),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Tooltip(
              message: hasRemind
                  ? '$remindSummary\n长按可清除提醒'
                  : remindSummary,
              child: IconButton(
                style: smallColoredIcon(fg: remindColor, bg: remindBg),
                onPressed: _pickRemind,
                onLongPress: hasRemind ? _clearRemind : null,
                icon: Icon(
                  hasRemind ? Icons.schedule : Icons.schedule_outlined,
                  size: kIconSize,
                ),
              ),
            ),
            const SizedBox(width: 10),
            MenuAnchor(
              menuChildren: [
                for (final p in TodoPriority.values)
                  MenuItemButton(
                    onPressed: () {
                      setState(() => _priority = p);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.flag_rounded,
                          size: 20,
                          color: TodoPriority.color(p, scheme),
                        ),
                        const SizedBox(width: 10),
                        Text(TodoPriority.label(p)),
                        if (p == _priority) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check, size: 18, color: scheme.primary),
                        ],
                      ],
                    ),
                  ),
              ],
              builder: (context, controller, child) {
                return Tooltip(
                  message: '紧急程度：${TodoPriority.label(_priority)}',
                  child: IconButton(
                    style: smallColoredIcon(fg: priColor, bg: priBg),
                    onPressed: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    icon: Icon(
                      Icons.flag_rounded,
                      size: kIconSize,
                      color: priColor,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _clearRemind() {
    setState(() {
      _remindAt = null;
      _remindEndAt = null;
      _remindIsAllDay = false;
      _remindRepeat = TodoRepeat.none;
    });
  }

  Future<void> _pickRemind() async {
    final result = await TodoTimePickerDialog.show(
      context,
      title: '提醒时间',
      initial: _remindAt == null
          ? null
          : TodoTimeSelection(
              start: _remindAt,
              end: _remindEndAt,
              isAllDay: _remindIsAllDay,
              repeatRule: _remindRepeat,
            ),
    );
    if (result == null) return;
    setState(() {
      _remindAt = result.start;
      _remindEndAt = result.end;
      _remindIsAllDay = result.isAllDay;
      _remindRepeat = result.repeatRule;
    });
  }

  Widget _buildParentSelector(BuildContext context, ColorScheme scheme) {
    final forbidden = _forbiddenParentIds();
    final candidates =
        widget.allTodos.where((t) => !forbidden.contains(t.id)).toList();

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
            initialValue:
                candidates.any((c) => c.id == _parentId) ? _parentId : null,
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
        remindAt: _remindAt,
        parentId: _parentId,
        orderIndex: HiveService.nextOrderIndex(_parentId),
        remindEndAt: _remindEndAt,
        remindIsAllDay: _remindIsAllDay,
        remindRepeatRule: _remindRepeat,
      );
      await HiveService.addTodo(todo);
    } else {
      e.title = title;
      e.note = _noteCtrl.text.trim();
      e.priority = _priority;
      e.remindAt = _remindAt;
      e.remindEndAt = _remindEndAt;
      e.remindIsAllDay = _remindIsAllDay;
      e.remindRepeatRule = _remindRepeat;
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

/// 把 [start] / [end] / [isAllDay] 组装成一个适合展示的字符串。
/// 外部（TodoPage / TimelinePage / TodoEditor）都走这个实现，
/// 保持文案一致。
String formatTodoTime({
  required DateTime? start,
  required DateTime? end,
  required bool isAllDay,
}) {
  if (start == null) return '--';
  final now = DateTime.now();
  String dayOf(DateTime d) {
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == -1) return '昨天';
    if (d.year == now.year) return DateFormat('M月d日').format(d);
    return DateFormat('y年M月d日').format(d);
  }

  String hm(DateTime d) => DateFormat('HH:mm').format(d);

  if (isAllDay) {
    return '${dayOf(start)} 全天';
  }
  if (end != null) {
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) {
      return '${dayOf(start)} ${hm(start)}-${hm(end)}';
    }
    return '${dayOf(start)} ${hm(start)} → ${dayOf(end)} ${hm(end)}';
  }
  return '${dayOf(start)} ${hm(start)}';
}
