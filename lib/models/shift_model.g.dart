// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shift_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ShiftModelAdapter extends TypeAdapter<ShiftModel> {
  @override
  final int typeId = 1;

  @override
  ShiftModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ShiftModel(
      date: fields[0] as DateTime,
      shiftType: fields[1] as String,
      startHour: fields[2] as int,
      startMinute: fields[3] as int,
      endHour: fields[4] as int,
      endMinute: fields[5] as int,
      notes: fields[6] as String,
      id: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ShiftModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.shiftType)
      ..writeByte(2)
      ..write(obj.startHour)
      ..writeByte(3)
      ..write(obj.startMinute)
      ..writeByte(4)
      ..write(obj.endHour)
      ..writeByte(5)
      ..write(obj.endMinute)
      ..writeByte(6)
      ..write(obj.notes)
      ..writeByte(7)
      ..write(obj.id);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShiftModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
