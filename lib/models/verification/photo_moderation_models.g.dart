// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_moderation_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PhotoModerationFlagAdapter extends TypeAdapter<PhotoModerationFlag> {
  @override
  final int typeId = 22;

  @override
  PhotoModerationFlag read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PhotoModerationFlag(
      id: fields[0] as String,
      userId: fields[1] as String,
      photoUrl: fields[2] as String,
      type: fields[3] as PhotoModerationType,
      status: fields[4] as PhotoModerationStatus,
      createdAt: fields[5] as DateTime,
      resolvedAt: fields[6] as DateTime?,
      resolvedBy: fields[7] as String?,
      details: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PhotoModerationFlag obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.photoUrl)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.resolvedAt)
      ..writeByte(7)
      ..write(obj.resolvedBy)
      ..writeByte(8)
      ..write(obj.details);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoModerationFlagAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class UserModerationRecordAdapter extends TypeAdapter<UserModerationRecord> {
  @override
  final int typeId = 23;

  @override
  UserModerationRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserModerationRecord(
      userId: fields[0] as String,
      faceMismatchWarnings: fields[1] as int,
      isBanned: fields[2] as bool,
      bannedAt: fields[3] as DateTime?,
      banReason: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, UserModerationRecord obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.userId)
      ..writeByte(1)
      ..write(obj.faceMismatchWarnings)
      ..writeByte(2)
      ..write(obj.isBanned)
      ..writeByte(3)
      ..write(obj.bannedAt)
      ..writeByte(4)
      ..write(obj.banReason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModerationRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PhotoModerationTypeAdapter extends TypeAdapter<PhotoModerationType> {
  @override
  final int typeId = 20;

  @override
  PhotoModerationType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PhotoModerationType.faceMismatch;
      case 1:
        return PhotoModerationType.nudityContent;
      case 2:
        return PhotoModerationType.otherViolation;
      default:
        return PhotoModerationType.faceMismatch;
    }
  }

  @override
  void write(BinaryWriter writer, PhotoModerationType obj) {
    switch (obj) {
      case PhotoModerationType.faceMismatch:
        writer.writeByte(0);
        break;
      case PhotoModerationType.nudityContent:
        writer.writeByte(1);
        break;
      case PhotoModerationType.otherViolation:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoModerationTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PhotoModerationStatusAdapter extends TypeAdapter<PhotoModerationStatus> {
  @override
  final int typeId = 21;

  @override
  PhotoModerationStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return PhotoModerationStatus.pending;
      case 1:
        return PhotoModerationStatus.approved;
      case 2:
        return PhotoModerationStatus.flagged;
      case 3:
        return PhotoModerationStatus.deleted;
      default:
        return PhotoModerationStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, PhotoModerationStatus obj) {
    switch (obj) {
      case PhotoModerationStatus.pending:
        writer.writeByte(0);
        break;
      case PhotoModerationStatus.approved:
        writer.writeByte(1);
        break;
      case PhotoModerationStatus.flagged:
        writer.writeByte(2);
        break;
      case PhotoModerationStatus.deleted:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoModerationStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
