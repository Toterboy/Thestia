import 'package:hive/hive.dart';

part 'signal_key_models.g.dart';

@HiveType(typeId: 0)
class SignalIdentityKeyPairAdapter extends HiveObject {
  @HiveField(0)
  final String identityKeyPairJson;

  SignalIdentityKeyPairAdapter({required this.identityKeyPairJson});
}

@HiveType(typeId: 1)
class SignalPreKeyRecordAdapter extends HiveObject {
  @HiveField(0)
  final int keyId;

  @HiveField(1)
  final String keyPairJson;

  SignalPreKeyRecordAdapter({required this.keyId, required this.keyPairJson});
}

@HiveType(typeId: 2)
class SignalSignedPreKeyRecordAdapter extends HiveObject {
  @HiveField(0)
  final int keyId;

  @HiveField(1)
  final String keyPairJson;

  @HiveField(2)
  final String signatureJson;

  @HiveField(3)
  final int timestamp;

  SignalSignedPreKeyRecordAdapter({
    required this.keyId,
    required this.keyPairJson,
    required this.signatureJson,
    required this.timestamp,
  });
}

@HiveType(typeId: 3)
class SignalSessionRecordAdapter extends HiveObject {
  @HiveField(0)
  final String sessionId;

  @HiveField(1)
  final String recordJson;

  SignalSessionRecordAdapter({
    required this.sessionId,
    required this.recordJson,
  });
}

@HiveType(typeId: 4)
class SignalSenderKeyRecordAdapter extends HiveObject {
  @HiveField(0)
  final String senderKeyId;

  @HiveField(1)
  final String recordJson;

  SignalSenderKeyRecordAdapter({
    required this.senderKeyId,
    required this.recordJson,
  });
}

@HiveType(typeId: 5)
class EncryptedMessageAdapter extends HiveObject {
  @HiveField(0)
  final String senderId;

  @HiveField(1)
  final String recipientId;

  @HiveField(2)
  final String ciphertext;

  @HiveField(3)
  final int messageType;

  @HiveField(4)
  final int timestamp;

  EncryptedMessageAdapter({
    required this.senderId,
    required this.recipientId,
    required this.ciphertext,
    required this.messageType,
    required this.timestamp,
  });
}

@HiveType(typeId: 6)
class SignalIdentityKeyStoreAdapter extends HiveObject {
  @HiveField(0)
  final String trustedKeyJson;

  @HiveField(1)
  final String recipientId;

  SignalIdentityKeyStoreAdapter({
    required this.trustedKeyJson,
    required this.recipientId,
  });
}
