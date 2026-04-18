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

  @HiveField(4)
  DateTime? dueAt;

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

  TodoModel({
    required this.id,
    required this.title,
    this.note = '',
    this.priority = TodoPriority.normal,
    this.dueAt,
    this.remindAt,
    this.done = false,
    this.doneAt,
    this.parentId,
    this.orderIndex = 0,
    required this.createdAt,
  });

  factory TodoModel.create({
    required String title,
    String note = '',
    int priority = TodoPriority.normal,
    DateTime? dueAt,
    DateTime? remindAt,
    String? parentId,
    int orderIndex = 0,
  }) {
    final now = DateTime.now();
    return TodoModel(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      note: note,
      priority: priority,
      dueAt: dueAt,
      remindAt: remindAt,
      parentId: parentId,
      orderIndex: orderIndex,
      createdAt: now,
    );
  }

  bool get isOverdue {
    if (done) return false;
    final d = dueAt;
    if (d == null) return false;
    return d.isBefore(DateTime.now());
  }
}
