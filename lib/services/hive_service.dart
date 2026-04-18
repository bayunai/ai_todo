import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/event_model.dart';
import '../models/shift_model.dart';
import '../models/todo_model.dart';
import 'notification_service.dart';

class HiveService {
  static const String eventsBoxName = 'events';
  static const String shiftsBoxName = 'shifts';
  static const String todosBoxName = 'todos';
  static const String settingsBoxName = 'settings';

  // 初始化 Hive
  static Future<void> init() async {
    await Hive.initFlutter();

    // 注册适配器
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(EventModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ShiftModelAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(TodoModelAdapter());
    }

    // 打开 Box
    await Hive.openBox<EventModel>(eventsBoxName);
    await Hive.openBox<ShiftModel>(shiftsBoxName);
    await Hive.openBox<TodoModel>(todosBoxName);
    await Hive.openBox(settingsBoxName);
  }

  // ========== 设置（轻量 KV 存储） ==========

  static Box get _settingsBox => Hive.box(settingsBoxName);

  static T getSetting<T>(String key, T defaultValue) {
    final v = _settingsBox.get(key);
    if (v is T) return v;
    return defaultValue;
  }

  static Future<void> setSetting<T>(String key, T value) async {
    await _settingsBox.put(key, value);
  }

  static ValueListenable<Box> listenableSettings(List<String> keys) =>
      _settingsBox.listenable(keys: keys);

  // ========== 事件相关操作 ==========
  
  static Box<EventModel> get _eventsBox => Hive.box<EventModel>(eventsBoxName);

  // 获取所有事件
  static List<EventModel> getAllEvents() {
    return _eventsBox.values.toList();
  }

  // 根据日期获取事件
  static List<EventModel> getEventsByDate(DateTime date) {
    return _eventsBox.values.where((event) {
      return event.date.year == date.year &&
          event.date.month == date.month &&
          event.date.day == date.day;
    }).toList();
  }

  // 添加事件
  static Future<void> addEvent(EventModel event) async {
    await _eventsBox.add(event);
  }

  // 更新事件
  static Future<void> updateEvent(int index, EventModel event) async {
    await _eventsBox.putAt(index, event);
  }

  // 删除事件
  static Future<void> deleteEvent(int index) async {
    await _eventsBox.deleteAt(index);
  }

  // 根据 ID 删除事件
  static Future<void> deleteEventById(String id) async {
    final index = _eventsBox.values.toList().indexWhere((e) => e.id == id);
    if (index != -1) {
      await _eventsBox.deleteAt(index);
    }
  }

  // 清空所有事件
  static Future<void> clearAllEvents() async {
    await _eventsBox.clear();
  }

  // ========== 班次相关操作 ==========

  static Box<ShiftModel> get _shiftsBox => Hive.box<ShiftModel>(shiftsBoxName);

  // 获取所有班次
  static List<ShiftModel> getAllShifts() {
    return _shiftsBox.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  // 根据日期获取班次
  static List<ShiftModel> getShiftsByDate(DateTime date) {
    return _shiftsBox.values.where((shift) {
      return shift.date.year == date.year &&
          shift.date.month == date.month &&
          shift.date.day == date.day;
    }).toList();
  }

  // 添加班次
  static Future<void> addShift(ShiftModel shift) async {
    await _shiftsBox.add(shift);
  }

  // 更新班次
  static Future<void> updateShift(int index, ShiftModel shift) async {
    await _shiftsBox.putAt(index, shift);
  }

  // 删除班次
  static Future<void> deleteShift(int index) async {
    await _shiftsBox.deleteAt(index);
  }

  // 根据 ID 删除班次
  static Future<void> deleteShiftById(String id) async {
    final index = _shiftsBox.values.toList().indexWhere((s) => s.id == id);
    if (index != -1) {
      await _shiftsBox.deleteAt(index);
    }
  }

  // 清空所有班次
  static Future<void> clearAllShifts() async {
    await _shiftsBox.clear();
  }

  // 获取班次在 Box 中的索引
  static int? getShiftIndex(ShiftModel shift) {
    final list = _shiftsBox.values.toList();
    final index = list.indexWhere((s) => s.id == shift.id);
    return index != -1 ? index : null;
  }

  // 获取事件在 Box 中的索引
  static int? getEventIndex(EventModel event) {
    final list = _eventsBox.values.toList();
    final index = list.indexWhere((e) => e.id == event.id);
    return index != -1 ? index : null;
  }

  // ========== 待办相关操作 ==========

  static Box<TodoModel> get _todosBox => Hive.box<TodoModel>(todosBoxName);

  /// 监听待办 Box 变更（供 ValueListenableBuilder 使用）
  static ValueListenable<Box<TodoModel>> listenableTodos() =>
      _todosBox.listenable();

  static List<TodoModel> getAllTodos() => _todosBox.values.toList();

  static TodoModel? getTodoById(String id) {
    for (final t in _todosBox.values) {
      if (t.id == id) return t;
    }
    return null;
  }

  static List<TodoModel> getChildren(String? parentId) {
    return _todosBox.values.where((t) => t.parentId == parentId).toList();
  }

  /// 同级最大 orderIndex + 1
  static int nextOrderIndex(String? parentId) {
    final siblings = getChildren(parentId);
    if (siblings.isEmpty) return 0;
    return siblings
            .map((e) => e.orderIndex)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  static Future<void> addTodo(TodoModel todo) async {
    await _todosBox.add(todo);
    await NotificationService.scheduleForTodo(todo);
  }

  static Future<void> updateTodo(TodoModel todo) async {
    if (todo.isInBox) {
      await todo.save();
    } else {
      final list = _todosBox.values.toList();
      final index = list.indexWhere((t) => t.id == todo.id);
      if (index != -1) {
        await _todosBox.putAt(index, todo);
      }
    }
    await NotificationService.scheduleForTodo(todo);
  }

  /// 切换完成状态。完成时记录时间，并取消通知；取消完成后重新排期。
  static Future<void> toggleDone(String id) async {
    final todo = getTodoById(id);
    if (todo == null) return;
    todo.done = !todo.done;
    todo.doneAt = todo.done ? DateTime.now() : null;
    await todo.save();
    if (todo.done) {
      await NotificationService.cancelForTodo(todo.id);
      // 勾选完成时给一次轻触感 + 系统点击音
      await NotificationService.playCompleteCue();
    } else {
      await NotificationService.scheduleForTodo(todo);
    }
  }

  /// 递归收集 [id] 及其所有后代的 id
  static List<String> collectSubtreeIds(String id) {
    final all = _todosBox.values.toList();
    final result = <String>[id];
    final queue = <String>[id];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final t in all) {
        if (t.parentId == current) {
          result.add(t.id);
          queue.add(t.id);
        }
      }
    }
    return result;
  }

  /// 删除单个待办（不连带子树）
  static Future<void> deleteTodo(String id) async {
    final list = _todosBox.values.toList();
    final index = list.indexWhere((t) => t.id == id);
    if (index != -1) {
      await _todosBox.deleteAt(index);
      await NotificationService.cancelForTodo(id);
    }
  }

  /// 删除节点及其所有后代
  static Future<void> deleteSubtree(String id) async {
    final ids = collectSubtreeIds(id).toSet();
    final list = _todosBox.values.toList();
    final keys = <dynamic>[];
    for (var i = 0; i < list.length; i++) {
      if (ids.contains(list[i].id)) {
        keys.add(list[i].key);
      }
    }
    await _todosBox.deleteAll(keys);
    for (final tid in ids) {
      await NotificationService.cancelForTodo(tid);
    }
  }

  static Future<void> clearAllTodos() async {
    await _todosBox.clear();
  }
}

