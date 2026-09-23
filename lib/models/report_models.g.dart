// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserReportAdapter extends TypeAdapter<UserReport> {
  @override
  final int typeId = 31;

  @override
  UserReport read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserReport(
      id: fields[0] as String,
      reporterId: fields[1] as String,
      reportedUserId: fields[2] as String,
      type: fields[3] as ReportType,
      description: fields[4] as String?,
      createdAt: fields[5] as DateTime,
      status: fields[6] as String,
      moderatorNote: fields[7] as String?,
      resolvedAt: fields[8] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, UserReport obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.reporterId)
      ..writeByte(2)
      ..write(obj.reportedUserId)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.moderatorNote)
      ..writeByte(8)
      ..write(obj.resolvedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserReportAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ReportTypeAdapter extends TypeAdapter<ReportType> {
  @override
  final int typeId = 30;

  @override
  ReportType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ReportType.harassment;
      case 1:
        return ReportType.inappropriateContent;
      case 2:
        return ReportType.spam;
      case 3:
        return ReportType.fakeProfile;
      case 4:
        return ReportType.other;
      case 5:
        return ReportType.wrongAge;
      default:
        return ReportType.harassment;
    }
  }

  @override
  void write(BinaryWriter writer, ReportType obj) {
    switch (obj) {
      case ReportType.harassment:
        writer.writeByte(0);
        break;
      case ReportType.inappropriateContent:
        writer.writeByte(1);
        break;
      case ReportType.spam:
        writer.writeByte(2);
        break;
      case ReportType.fakeProfile:
        writer.writeByte(3);
        break;
      case ReportType.other:
        writer.writeByte(4);
        break;
      case ReportType.wrongAge:
        writer.writeByte(5);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
