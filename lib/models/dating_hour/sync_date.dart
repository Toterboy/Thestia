// Das Sync-Date: ein Treffen zur selben Zeit an verschiedenen Orten.
//
// ANLASS (27.11.2026): Der Plan für 0.11.0 ("Begegnung statt
// Bildschirm") und der Wunsch des Betreibers: Zwei Menschen, die weit
// auseinander wohnen, sollen sich zur SELBEN ZEIT treffen können -
// beide gehen spazieren und telefonieren dabei, beide starten denselben
// Film, beide kochen dasselbe Rezept.
//
// WARUM EIN EIGENER ZUSTAND: Der Termin liegt auf dem Server
// (sync_dates), damit beide Seiten denselben Startzeitpunkt sehen und
// beide sehen, ob der andere schon angenommen hat. Die Geräteuhren
// weichen ab - ein lokaler Zeitpunkt wäre falsch.

import 'package:thestia/utils/common/json_leser.dart';

/// Die Ideen, die als Sync-Date taugen.
///
/// DER KATALOG: Jede Idee funktioniert über die Distanz, weil beide
/// zur selben Zeit etwas tun - und telefonieren. Die Ideen stehen auch
/// in der Datenbank (CHECK-Bedingung in der Migration 223), damit
/// niemand Unsinn in die Zeile schreibt.
enum SyncDateIdee {
  /// Beide gehen spazieren und telefonieren dabei.
  spaziergangAnruf,

  /// Beide starten denselben Film zur selben Zeit.
  gleicherFilm,

  /// Beide kochen dasselbe Rezept gleichzeitig.
  kochDuell,

  /// Beide schauen nach oben - und telefonieren.
  sterneGucken;

  /// Der Schlüssel, den der Server kennt.
  String get wert => switch (this) {
    SyncDateIdee.spaziergangAnruf => 'spaziergangAnruf',
    SyncDateIdee.gleicherFilm => 'gleicherFilm',
    SyncDateIdee.kochDuell => 'kochDuell',
    SyncDateIdee.sterneGucken => 'sterneGucken',
  };

  /// Der Text-Schlüssel (die App-Texte stehen in lib/l10n).
  String get textKey => 'sync.idea.$wert';

  /// Liest die Idee aus dem Server-Wert.
  ///
  /// Unbekanntes wird zu [spaziergangAnruf] - ein kaputter Wert darf
  /// das Date nicht verschwinden lassen.
  static SyncDateIdee ausWert(String? wert) {
    return SyncDateIdee.values.firstWhere(
      (i) => i.wert == wert,
      orElse: () => SyncDateIdee.spaziergangAnruf,
    );
  }
}

/// Der Stand eines Sync-Dates (aus der Sicht des eigenen Nutzers).
class SyncDate {
  const SyncDate({
    required this.matchId,
    required this.idea,
    required this.startAt,
    required this.proposedByMe,
    required this.acceptedByMe,
    required this.acceptedByPartner,
  });

  /// Match-ID (entspricht matches.id).
  final String matchId;

  /// Die Idee (was beide zur selben Zeit machen).
  final SyncDateIdee idea;

  /// Der gemeinsame Startzeitpunkt (Serverzeit).
  final DateTime startAt;

  /// Ich habe das Date vorgeschlagen.
  final bool proposedByMe;

  /// Ich habe angenommen.
  final bool acceptedByMe;

  /// Der Partner hat angenommen.
  final bool acceptedByPartner;

  /// Beide haben angenommen - das Date steht.
  bool get bothAccepted => acceptedByMe && acceptedByPartner;

  /// Läuft das Date gerade?
  ///
  /// DER WEG: Das Date beginnt zum Startzeitpunkt und endet, wenn der
  /// Anruf endet. Zwischen Start und Ende ist die App gesperrt (nur
  /// dieser Chat ist benutzbar).
  bool get laeuft {
    final jetzt = DateTime.now();
    return !jetzt.isBefore(startAt) && jetzt.isBefore(startAt.add(_maxDauer));
  }

  /// Die längste Laufzeit eines Dates (der Notfallschutz).
  ///
  /// DER GRUND: Der Anruf beendet das Date. Kommt das Ende nicht an
  /// (der Partner ist offline, die App wurde beendet), darf die App
  /// nicht für immer gesperrt bleiben.
  static const Duration _maxDauer = Duration(hours: 6);

  /// Wie lange es noch dauert (bis zum Ende des Fensters).
  Duration get restzeit {
    final ende = startAt.add(_maxDauer);
    final rest = ende.difference(DateTime.now());
    return rest.isNegative ? Duration.zero : rest;
  }

  factory SyncDate.fromJson(Map<String, dynamic> json) {
    // BEFUND (22.11.2026, Fuzzing): Die Casts hier warfen bei jedem
    // falschen Typ - die Zeile kommt vom Server.
    return SyncDate(
      matchId: textOf(json, ['matchId']) ?? '',
      idea: SyncDateIdee.ausWert(textOf(json, ['idea'])),
      startAt: dateOf(json, ['startAt']) ?? DateTime.now(),
      proposedByMe: boolOf(json, ['proposedByMe']) ?? false,
      acceptedByMe: boolOf(json, ['acceptedByMe']) ?? false,
      acceptedByPartner: boolOf(json, ['acceptedByPartner']) ?? false,
    );
  }
}
