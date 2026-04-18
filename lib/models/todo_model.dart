import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'todo_model.g.dart';

/// 4 级紧急程度。数值越小越紧急，便于按 priority 升序排序。
class TodoPriority {
  static const int urgent = 0;
  static const int important = 1;
  static const int normal = 2;
  static const int low = 3;

  static const List<int> values = [urgent, important, normal, low];

  static String label(int p) {
    switch (p) {
      case urgent:
        return '紧急';
      case important:
        return '重要';
      case normal:
        return '普通';
      case low:
        return '低';
      default:
        return '普通';
    }
  }

  /// 优先级配色：紧急用 error；重要用橙色；普通用 primary；低用 outline
  static Color color(int p, ColorScheme scheme) {
    switch (p) {
      case urgent:
        return scheme.error;
      case important:
        return const Color(0xFFFB8C00);
      case normal:
        return scheme.primary;
      case low:
        return scheme.outline;
      default:
        return scheme.primary;
    }
  }
}

/// 时间重复规则。数值与 Hive 字段保持一致，向后追加即可。
class TodoRepeat {
  static const int none = 0;
  static const int daily = 1;
  static const int weekly = 2;
  static const int monthly = 3;
  static const int yearly = 4;

  static const List<int> values = [none, daily, weekly, monthly, yearly];

  static String label(int r) {
    switch (r) {
      case daily:
        return '每天';
      case weekly:
        return '每周';
      case monthly:
        return '每月';
      case yearly:
        return '每年';
      case none:
      default:
        return '无';
    }
  }
}

@HiveType(typeId: 2)
class TodoModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String note;

  /// 4 级优先级，参见 [TodoPriority]
  @HiveField(3)
  int priority;

  // NOTE: HiveField id 4 / 11 / 12 / 13 历史上分别是 dueAt / dueEndAt /
  // dueRepeatRule / dueIsAllDay，已彻底移除。这些 id 保留不再使用，
  // 旧记录里的槽位字节在反序列化时会被丢弃。

  @HiveField(5)
  DateTime? remindAt;

  @HiveField(6)
  bool done;

  @HiveField(7)
  DateTime? doneAt;

  /// 父待办 id；null 表示根节点
  @HiveField(8)
  String? parentId;

  /// 同级排序索引
  @HiveField(9)
  int orderIndex;

  @HiveField(10)
  DateTime createdAt;

  /// 提醒时间段终点（仅展示，不影响调度）
  @HiveField(14)
  DateTime? remindEndAt;

  /// 提醒的重复规则，见 [TodoRepeat]
  @HiveField(15, defaultValue: 0)
  int remindRepeatRule;

  /// 提醒是否全天（true 时调度时默认改为当日 09:00）
  @HiveField(16, defaultValue: false)
  bool remindIsAllDay;

  TodoModel({
    required this.id,
    required this.title,
    this.note = '',
    this.priority = TodoPriority.normal,
    this.remindAt,
    this.done = false,
    this.doneAt,
    this.parentId,
    this.orderIndex = 0,
    required this.createdAt,
    this.remindEndAt,
    this.remindRepeatRule = TodoRepeat.none,
    this.remindIsAllDay = false,
  });

  factory TodoModel.create({
    required String title,
    String note = '',
    int priority = TodoPriority.normal,
    DateTime? remindAt,
    String? parentId,
    int orderIndex = 0,
    DateTime? remindEndAt,
    int remindRepeatRule = TodoRepeat.none,
    bool remindIsAllDay = false,
  }) {
    final now = DateTime.now();
    return TodoModel(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      note: note,
      priority: priority,
      remindAt: remindAt,
      parentId: parentId,
      orderIndex: orderIndex,
      createdAt: now,
      remindEndAt: remindEndAt,
      remindRepeatRule: remindRepeatRule,
      remindIsAllDay: remindIsAllDay,
    );
  }
}
