import 'package:thestia/utils/common/json_leser.dart';

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
    // BEFUND (22.11.2026, Fuzzing): Die Casts hier warfen bei jedem
    // falschen Typ - die Zeile kommt vom Server.
    return MeetIntent(
      matchId: textOf(json, ['matchId']) ?? '',
      eligible: boolOf(json, ['eligible']) ?? false,
      myWants: boolOf(json, ['myWants']) ?? false,
      partnerWants: boolOf(json, ['partnerWants']) ?? false,
      metConfirmed: boolOf(json, ['metConfirmed']) ?? false,
    );
  }
}
