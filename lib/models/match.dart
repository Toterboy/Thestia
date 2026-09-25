import 'package:thestia/models/user_profile.dart';

/// Repräsentiert ein Match zwischen zwei Nutzern.
///
/// Wichtig für den Blind Mode: [photosUnlocked] gibt an, ob die Fotos
/// beider Seiten bereits freigeschaltet wurden (erst nach beidseitigem Like).
/// [isQrContact] = true wenn der Kontakt via QR-Code-Scan entstanden ist.
class Match {
  /// Eindeutige Match-ID.
  final String id;

  /// Das gematchte Gegenüber-Profil.
  final UserProfile partner;

  /// Zeitpunkt des Matches.
  final DateTime matchedAt;

  /// Wurden die Fotos bereits freigeschaltet?
  final bool photosUnlocked;

  /// Ungelesene Nachrichtenanzahl (für Badge).
  final int unreadCount;

  /// Kontakt via QR-Code-Scan (nicht via gegenseitiges Like).
  final bool isQrContact;

  const Match({
    required this.id,
    required this.partner,
    required this.matchedAt,
    this.photosUnlocked = false,
    this.unreadCount = 0,
    this.isQrContact = false,
  });

  Match copyWith({
    String? id,
    UserProfile? partner,
    DateTime? matchedAt,
    bool? photosUnlocked,
    int? unreadCount,
    bool? isQrContact,
  }) {
    return Match(
      id: id ?? this.id,
      partner: partner ?? this.partner,
      matchedAt: matchedAt ?? this.matchedAt,
      photosUnlocked: photosUnlocked ?? this.photosUnlocked,
      unreadCount: unreadCount ?? this.unreadCount,
      isQrContact: isQrContact ?? this.isQrContact,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Match && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
