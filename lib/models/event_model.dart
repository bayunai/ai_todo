import 'package:hive/hive.dart';

part 'event_model.g.dart';

@HiveType(typeId: 0)
class EventModel extends HiveObject {
  @HiveField(0)
  final String title;

  @HiveField(1)
  final String description;

  @HiveField(2)
  final DateTime date;

  @HiveField(3)
  final String? id;

  EventModel({
    required this.title,
    required this.description,
    required this.date,
    this.id,
  });

  // 从旧 Event 类转换
  factory EventModel.fromEvent(String title, String description, DateTime date) {
    return EventModel(
      title: title,
      description: description,
      date: date,
      id: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  // 转换为旧 Event 类（如果需要）
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'id': id,
    };
  }
}

