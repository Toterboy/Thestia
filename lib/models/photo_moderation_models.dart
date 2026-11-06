import 'package:hive/hive.dart';

part 'photo_moderation_models.g.dart';

/// Typ einer Moderations-Flag.
@HiveType(typeId: 20)
enum PhotoModerationType {
  /// Profilbild stimmt nicht mit Verifizierungs-Video überein (Gesichtsabgleich).
  @HiveField(0)
  faceMismatch,

  /// Nacktinhalt / sexuelle Inhalte erkannt.
  @HiveField(1)
  nudityContent,

  /// Anderer Verstoß (Gewalt, Hass, etc.).
  @HiveField(2)
  otherViolation,
}

/// Status einer Moderations-Prüfung.
@HiveType(typeId: 21)
enum PhotoModerationStatus {
  /// Noch nicht geprüft.
  @HiveField(0)
  pending,

  /// Bestanden (kein Verstoß).
  @HiveField(1)
  approved,

  /// Verstoß erkannt.
  @HiveField(2)
  flagged,

  /// Bild gelöscht.
  @HiveField(3)
  deleted,
}

/// Model für eine Moderations-Flag eines Bildes.
@HiveType(typeId: 22)
class PhotoModerationFlag extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String userId;

  @HiveField(2)
  final String photoUrl;

  @HiveField(3)
  final PhotoModerationType type;

  @HiveField(4)
  final PhotoModerationStatus status;

  @HiveField(5)
  final DateTime createdAt;

  @HiveField(6)
  DateTime? resolvedAt;

  @HiveField(7)
  String? resolvedBy; // 'auto' oder 'admin'

  @HiveField(8)
  String? details; // Zusatzinfos (z. B. Confidence-Score)

  PhotoModerationFlag({
    required this.id,
    required this.userId,
    required this.photoUrl,
    required this.type,
    this.status = PhotoModerationStatus.pending,
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.details,
  });

  PhotoModerationFlag copyWith({
    String? id,
    String? userId,
    String? photoUrl,
    PhotoModerationType? type,
    PhotoModerationStatus? status,
    DateTime? createdAt,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? details,
  }) {
    return PhotoModerationFlag(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      photoUrl: photoUrl ?? this.photoUrl,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      details: details ?? this.details,
    );
  }
}

/// Model für Verwarnungen/Sperren bei wiederholten Verstößen.
@HiveType(typeId: 23)
class UserModerationRecord extends HiveObject {
  @HiveField(0)
  final String userId;

  @HiveField(1)
  int faceMismatchWarnings;

  @HiveField(2)
  bool isBanned;

  @HiveField(3)
  DateTime? bannedAt;

  @HiveField(4)
  String? banReason;

  UserModerationRecord({
    required this.userId,
    this.faceMismatchWarnings = 0,
    this.isBanned = false,
    this.bannedAt,
    this.banReason,
  });

  UserModerationRecord copyWith({
    String? userId,
    int? faceMismatchWarnings,
    bool? isBanned,
    DateTime? bannedAt,
    String? banReason,
  }) {
    return UserModerationRecord(
      userId: userId ?? this.userId,
      faceMismatchWarnings: faceMismatchWarnings ?? this.faceMismatchWarnings,
      isBanned: isBanned ?? this.isBanned,
      bannedAt: bannedAt ?? this.bannedAt,
      banReason: banReason ?? this.banReason,
    );
  }
}
