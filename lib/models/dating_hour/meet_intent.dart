/// Status des "echtes Treffen"-Vorschlags für ein Match.
///
/// Liegt serverseitig (meet_intents), damit beide Chat-Partner synchron
/// den gleichen Stand sehen.
class MeetIntent {
  const MeetIntent({
    required this.matchId,
    required this.eligible,
    required this.myWants,
    required this.partnerWants,
    required this.metConfirmed,
  });

  /// Match-ID (entspricht matches.id).
  final String matchId;

  /// Match ist alt genug (>= 14 Tage) für den Vorschlag.
  final bool eligible;

  /// Der aktuelle Nutzer möchte sich treffen.
  final bool myWants;

  /// Der Partner möchte sich treffen.
  final bool partnerWants;

  /// Beide haben bestätigt, sich getroffen zu haben.
  final bool metConfirmed;

  /// True, wenn beide Seiten zugestimmt haben (Planungsphase).
  bool get bothWant => myWants && partnerWants;

  factory MeetIntent.fromJson(Map<String, dynamic> json) {
    return MeetIntent(
      matchId: (json['matchId'] as num).toString(),
      eligible: json['eligible'] as bool? ?? false,
      myWants: json['myWants'] as bool? ?? false,
      partnerWants: json['partnerWants'] as bool? ?? false,
      metConfirmed: json['metConfirmed'] as bool? ?? false,
    );
  }
}
