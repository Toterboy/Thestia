import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:thestia/services/local_storage.dart';

/// "Neu in dieser Version"-Gate (NUTZERWUNSCH): Bei einem APP-UPDATE
/// (Build-Nummer gestiegen) bekommen bereits REGISTRIERTE Nutzer einmalig
/// ein Popup mit der Änderungs-Kurzfassung - plus Nachfragen zu NEUEN
/// Angaben (z. B. Geburtstags-Stil, Migration 115).
///
/// Sicherheit gegen Probleme (bewusste Design-Entscheidungen):
///  - Markiert wird der Build bereits BEIM ANZEIGEN (nicht erst beim
///    Bestätigen) - ein App-Kill mitten im Popup führt nicht zu einer
///    Endlos-Schleife beim nächsten Start.
///  - Fail-open: Jeder Fehler (PackageInfo/Storage) deaktiviert das Gate,
///    nie blockiert es den App-Start.
///  - Zeigt nie auf für nicht-eingerichtete Konten (Erst-Onboarding
///    läuft ohnehin) und nicht bei < buildNummern-Sprüngen.
///  - Der Inhalt (l10n-Keys) ist versioniert im Code; der Screen rendert
///    nur Zeilen für die aktuelle Version.
class WhatsNewService {
  WhatsNewService._();

  /// Prefs-Key der zuletzt gezeigten Build-Nummer.
  static const String shownBuildKey = 'whatsnew_shown_build';

  /// Die ersten Builds mit "Neu"-Inhalt: Build 30 (v0.9.2) hat die
  /// Herzensstärken + Geburtstags-Stil gebracht.
  static const int firstContentBuild = 22;

  /// Zusammenfassung je Version (l10n-Keys). NUR Titel-Bullets - Details
  /// stehen in den Release Notes.
  ///
  /// REGEL: Ein Listeneintrag ist EIN Anzeigepunkt und damit EIN
  /// vollstaendiger Satz. Frueher stand hier der Text als Satzbausteine
  /// ('Vorstellungen, die sich nicht wiederholen: die Ideen-Karten',
  /// 'rotieren jetzt. Wer die App oft oeffnet, ...') - zehn Bausteine
  /// fuer vier Aussagen. Die Abschneidegrenze in [keysFor] hat daraufhin
  /// mitten im Satz abgeschnitten: die Anzeige begann mit
  /// 'fuer Funken, Daumen und Nachrichten. ...' (Satzrumpf) und der
  /// Punkt 'Vorstellungen rotieren' - die erste sichtbare Aenderung von
  /// 0.9.2 - fehlte vollstaendig. Zusaetzlich war der Text nicht
  /// uebersetzt; englische Nutzer sahen Deutsch.
  static const Map<int, List<String>> contentByBuild = {
    // v0.10.0 (Build 31): Standort-Privatisierung. Die drei Punkte sind
    // bewusst ueber die Waechter-Begrenzung gesetzt - es sind die
    // einzigen Aenderungen, bei denen jemand in einer alten App
    // zurueckblinzelt ("wo ist mein Ort hin?") und deshalb NICHT auf
    // einen späteren Release vertrauen sollte.
    31: [
      'whatsnew.v1000.noCity',
      'whatsnew.v1000.grid',
      'whatsnew.v1000.distanceOptIn',
    ],

    30: [
      'whatsnew.v092.rotatingPrompts',
      'whatsnew.v092.emailRequired',
      'whatsnew.v092.safetyNumber',
      'whatsnew.v092.proximityJitter',
    ],

    22: [
      'whatsnew.v090.sparkMoments',
      'whatsnew.v090.friendship',
      'whatsnew.v090.bucketList',
      'whatsnew.v090.birthdayStyles',
    ],
  };

  /// Hoechstzahl gleichzeitig gezeigter Punkte.
  ///
  /// Wirkt nur noch als Schutz gegen eine Ausreiessliste. Weil ein
  /// Eintrag jetzt ein vollstaendiger Punkt ist, kann das Abschneiden
  /// keinen Satz mehr zerstoeren - es faellt nur eine ganze Aussage
  /// weg. Fuer die Oberflaeche ist eine Ausreiessliste schlimmer als
  /// weglassen, deshalb wird abgeschnitten, aber nach der neuen Logik:
  /// die JUENGSTE Version zuerst, aeltere nur, solange Platz ist.
  static const int maxPoints = 6;

  /// Neue ANGABEN, die im Flow abgefragt werden (z. B. Geburtstags-Stil).
  static bool hasNewInputs(int build) =>
      build >= firstContentBuild; // birthday_style ab Build 22

  /// Build-Nummer der installierten App (0 bei Fehlern -> Gate aus).
  static Future<int> currentBuild() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (e) {
      if (kDebugMode) debugPrint('[WhatsNew] Build-Ermittlung fehl: $e');
      return 0;
    }
  }

  /// Reine Gate-Logik (testbar): Soll der Screen gezeigt werden?
  ///
  /// [registered]: Nutzer eingeloggt (Session vorhanden).
  /// [onboardingDone]: Einrichtung mindestens einmal abgeschlossen
  /// (serverseitig gespiegelt, Migration 065) - schließt frische
  /// Registrierungen aus.
  static bool shouldShow({
    required int currentBuild,
    required int? shownBuild,
    required bool registered,
    required bool onboardingDone,
  }) {
    if (currentBuild <= 0) return false;
    if (!registered || !onboardingDone) return false;
    final last = shownBuild ?? 0;
    if (currentBuild <= last) return false;
    // Nur zeigen, wenn es für diese Build-Range Inhalt gibt.
    return contentByBuild.keys.any((b) => b > last && b <= currentBuild);
  }

  /// Merkt den gezeigten Build (LOKAL - der Wert ist pro Gerät gültig;
  /// ein Server-Write wäre für diese UX unnötig und würde RLS/Offline
  /// komplizierter machen).
  static Future<void> markShown(
      LocalStorage storage, int build) async {
    try {
      await storage.saveInt(shownBuildKey, build);
    } catch (e) {
      debugPrint('[WhatsNew] Markieren fehlgeschlagen: $e');
    }
  }

  /// Zuletzt gezeigter Build (null = noch nie gezeigt).
  static Future<int?> shownBuild(LocalStorage storage) async {
    try {
      return await storage.getInt(shownBuildKey);
    } catch (_) {
      return null;
    }
  }

  /// Anzeigepunkte fuer den aktuellen Build.
  ///
  /// Reihenfolge: die JUENGSTE Version zuerst. Wer von einem alten Build
  /// direkt auf den aktuellen springt, soll zuerst sehen, was jetzt neu
  /// ist - nicht den Aeltesten. Die alte Logik nahm
  /// `out.sublist(out.length - 6)`, also die LETZTEN sechs einer
  /// aufsteigend zusammengebauten Liste; bei einem Sprung ueber
  /// mehrere Versionen verdraengte damit eine alte Version den Inhalt
  /// der aktuellen.
  ///
  /// Jeder Eintrag ist ein vollstaendiger Punkt (siehe [contentByBuild]),
  /// das Abschneiden zerstoert deshalb keinen Satz mehr.
  static List<String> keysFor({
    required int currentBuild,
    required int? shownBuild,
  }) {
    final last = shownBuild ?? 0;
    final relevant = contentByBuild.entries
        .where((e) => e.key > last && e.key <= currentBuild)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // juengste zuerst
    final out = <String>[];
    for (final entry in relevant) {
      out.addAll(entry.value);
      if (out.length >= maxPoints) break;
    }
    return out.length > maxPoints ? out.sublist(0, maxPoints) : out;
  }
}
