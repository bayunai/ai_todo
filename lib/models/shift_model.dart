import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'shift_model.g.dart';

@HiveType(typeId: 1)
class ShiftModel extends HiveObject {
  @HiveField(0)
  final DateTime date;

  @HiveField(1)
  final String shiftType;

  @HiveField(2)
  final int startHour;

  @HiveField(3)
  final int startMinute;

  @HiveField(4)
  final int endHour;

  @HiveField(5)
  final int endMinute;

  @HiveField(6)
  final String notes;

  @HiveField(7)
  final String? id;

  ShiftModel({
    required this.date,
    required this.shiftType,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.notes = '',
    this.id,
  });

  // 从 TimeOfDay 创建
  factory ShiftModel.fromTimeOfDay({
    required DateTime date,
    required String shiftType,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    String notes = '',
  }) {
    return ShiftModel(
      date: date,
      shiftType: shiftType,
      startHour: startTime.hour,
      startMinute: startTime.minute,
      endHour: endTime.hour,
      endMinute: endTime.minute,
      notes: notes,
      id: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  // 转换为 TimeOfDay
  TimeOfDay get startTime => TimeOfDay(hour: startHour, minute: startMinute);
  TimeOfDay get endTime => TimeOfDay(hour: endHour, minute: endMinute);

  // 从旧 Shift 类转换
  factory ShiftModel.fromShift({
    required DateTime date,
    required String shiftType,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    String notes = '',
  }) {
    return ShiftModel.fromTimeOfDay(
      date: date,
      shiftType: shiftType,
      startTime: startTime,
      endTime: endTime,
      notes: notes,
    );
  }
}

