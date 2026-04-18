import 'package:hive_flutter/hive_flutter.dart';
import '../models/event_model.dart';
import '../models/shift_model.dart';

class HiveService {
  static const String eventsBoxName = 'events';
  static const String shiftsBoxName = 'shifts';

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

    // 打开 Box
    await Hive.openBox<EventModel>(eventsBoxName);
    await Hive.openBox<ShiftModel>(shiftsBoxName);
  }

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
}

