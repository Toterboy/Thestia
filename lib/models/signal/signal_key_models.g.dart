// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signal_key_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SignalIdentityKeyPairAdapterAdapter
    extends TypeAdapter<SignalIdentityKeyPairAdapter> {
  @override
  final int typeId = 0;

  @override
  SignalIdentityKeyPairAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SignalIdentityKeyPairAdapter(
      identityKeyPairJson: fields[0] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SignalIdentityKeyPairAdapter obj) {
    writer
      ..writeByte(1)
      ..writeByte(0)
      ..write(obj.identityKeyPairJson);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalIdentityKeyPairAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SignalPreKeyRecordAdapterAdapter
    extends TypeAdapter<SignalPreKeyRecordAdapter> {
  @override
  final int typeId = 1;

  @override
  SignalPreKeyRecordAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SignalPreKeyRecordAdapter(
      keyId: fields[0] as int,
      keyPairJson: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SignalPreKeyRecordAdapter obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.keyId)
      ..writeByte(1)
      ..write(obj.keyPairJson);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalPreKeyRecordAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SignalSignedPreKeyRecordAdapterAdapter
    extends TypeAdapter<SignalSignedPreKeyRecordAdapter> {
  @override
  final int typeId = 2;

  @override
  SignalSignedPreKeyRecordAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SignalSignedPreKeyRecordAdapter(
      keyId: fields[0] as int,
      keyPairJson: fields[1] as String,
      signatureJson: fields[2] as String,
      timestamp: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, SignalSignedPreKeyRecordAdapter obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.keyId)
      ..writeByte(1)
      ..write(obj.keyPairJson)
      ..writeByte(2)
      ..write(obj.signatureJson)
      ..writeByte(3)
      ..write(obj.timestamp);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalSignedPreKeyRecordAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SignalSessionRecordAdapterAdapter
    extends TypeAdapter<SignalSessionRecordAdapter> {
  @override
  final int typeId = 3;

  @override
  SignalSessionRecordAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SignalSessionRecordAdapter(
      sessionId: fields[0] as String,
      recordJson: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SignalSessionRecordAdapter obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.sessionId)
      ..writeByte(1)
      ..write(obj.recordJson);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalSessionRecordAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SignalSenderKeyRecordAdapterAdapter
    extends TypeAdapter<SignalSenderKeyRecordAdapter> {
  @override
  final int typeId = 4;

  @override
  SignalSenderKeyRecordAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SignalSenderKeyRecordAdapter(
      senderKeyId: fields[0] as String,
      recordJson: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SignalSenderKeyRecordAdapter obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.senderKeyId)
      ..writeByte(1)
      ..write(obj.recordJson);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalSenderKeyRecordAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class EncryptedMessageAdapterAdapter
    extends TypeAdapter<EncryptedMessageAdapter> {
  @override
  final int typeId = 5;

  @override
  EncryptedMessageAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EncryptedMessageAdapter(
      senderId: fields[0] as String,
      recipientId: fields[1] as String,
      ciphertext: fields[2] as String,
      messageType: fields[3] as int,
      timestamp: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, EncryptedMessageAdapter obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.senderId)
      ..writeByte(1)
      ..write(obj.recipientId)
      ..writeByte(2)
      ..write(obj.ciphertext)
      ..writeByte(3)
      ..write(obj.messageType)
      ..writeByte(4)
      ..write(obj.timestamp);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncryptedMessageAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SignalIdentityKeyStoreAdapterAdapter
    extends TypeAdapter<SignalIdentityKeyStoreAdapter> {
  @override
  final int typeId = 6;

  @override
  SignalIdentityKeyStoreAdapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SignalIdentityKeyStoreAdapter(
      trustedKeyJson: fields[0] as String,
      recipientId: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SignalIdentityKeyStoreAdapter obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.trustedKeyJson)
      ..writeByte(1)
      ..write(obj.recipientId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalIdentityKeyStoreAdapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
