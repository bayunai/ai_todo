// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TodoModelAdapter extends TypeAdapter<TodoModel> {
  @override
  final int typeId = 2;

  @override
  TodoModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TodoModel(
      id: fields[0] as String,
      title: fields[1] as String,
      note: fields[2] as String,
      priority: fields[3] as int,
      dueAt: fields[4] as DateTime?,
      remindAt: fields[5] as DateTime?,
      done: fields[6] as bool,
      doneAt: fields[7] as DateTime?,
      parentId: fields[8] as String?,
      orderIndex: fields[9] as int,
      createdAt: fields[10] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, TodoModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.note)
      ..writeByte(3)
      ..write(obj.priority)
      ..writeByte(4)
      ..write(obj.dueAt)
      ..writeByte(5)
      ..write(obj.remindAt)
      ..writeByte(6)
      ..write(obj.done)
      ..writeByte(7)
      ..write(obj.doneAt)
      ..writeByte(8)
      ..write(obj.parentId)
      ..writeByte(9)
      ..write(obj.orderIndex)
      ..writeByte(10)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
