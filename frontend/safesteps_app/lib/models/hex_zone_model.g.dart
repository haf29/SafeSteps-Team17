// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hex_zone_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HexZoneAdapter extends TypeAdapter<HexZone> {
  @override
  final int typeId = 0;

  @override
  HexZone read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HexZone(
      zoneId: fields[0] as String,
      boundary: (fields[1] as List)
          .map((dynamic e) => (e as List).cast<double>())
          .toList(),
      colorValue: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HexZone obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.zoneId)
      ..writeByte(1)
      ..write(obj.boundary)
      ..writeByte(2)
      ..write(obj.colorValue);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HexZoneAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
