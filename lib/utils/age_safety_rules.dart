// Zentrale Alters-Schutz-Regeln für die Blind Date App.
//
// Stufenweise Sichtbarkeitsregeln:
// - 16-17: nur untereinander sichtbar.
// - 18+: kann 16+ sehen.
// - 19+: kann 17+ sehen.
// - 20+: kann 18+ sehen.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'package:thestia/utils/constants.dart';

/// Repräsentiert die Altersgruppe eines Nutzers für Schutz-Regeln.
enum AgeGroup {
  /// 16-17 Jahre: Minderjährig, strengster Schutz
  minor,

  /// 18 Jahre: kann 16+ sehen
  adult18,

  /// 19 Jahre: kann 17+ sehen
  adult19,

  /// 20+ Jahre: kann 18+ sehen
  adult,
}

/// Ergebnis der Alters-Sicherheits-Prüfung für einen Nutzer.
class AgeSafetyRules {
  const AgeSafetyRules._();

  /// Bestimmt die Altersgruppe basierend auf dem Alter.
  static AgeGroup ageGroup(int age) {
    if (age < 18) return AgeGroup.minor;
    if (age == 18) return AgeGroup.adult18;
    if (age == 19) return AgeGroup.adult19;
    return AgeGroup.adult;
  }

  /// Prüft, ob ein Nutzer (viewer) einen anderen Nutzer (target) im Feed sehen darf.
  ///
  /// DIESE REGEL ENTSPRICHT DEM SERVER (Migration 154 + 155):
  ///
  /// Der Server filtert die Discovery über
  /// `age_compatible_bidirectional(viewer.birth_date, target.birth_date)`,
  /// und das ist `age_compatible(a→b) UND age_compatible(b→a)`.
  /// `age_compatible` (Migration 056) lautet:
  ///
  ///   Viewer < 18  → Ziel ∈ [16, 18)
  ///   Viewer = 18  → Ziel ≥ 16
  ///   Viewer = 19  → Ziel ≥ 17
  ///   Viewer ≥ 20  → Ziel ≥ 18
  ///
  /// Beidseitig angewandt heißt das:
  ///
  ///   * 16/17 sehen NUR 16/17.
  ///   * Erwachsene sehen NUR Erwachsene.
  ///   * 18↔16/17 ist gesperrt, 19↔17 ist gesperrt.
  ///
  /// Bis 04.11.2026 stand hier die EINSEITIGE Regel ("18+ kann 16+
  /// sehen"). Die war zwar unbenutzt - aber sie war eine Falle: Wer sie
  /// benutzt hätte, hätte eine Altersfreigabe gebaut, die der Server
  /// nie erteilt. Ein 18-Jähriger sieht keinen 16-Jährigen, und ein
  /// 19-Jähriger keinen 17-Jährigen.
  static bool canViewProfile({
    required int viewerAge,
    required int targetAge,
  }) {
    if (kDebugMode) debugPrint('[AGE_SAFETY] canViewProfile: viewerAge=$viewerAge, targetAge=$targetAge');
    // Die beidseitige Server-Regel in ihrer einfachsten Form:
    // Minderjaehrige sehen nur Minderjaehrige, Erwachsene nur
    // Erwachsene.
    //
    // WICHTIG: Der Vergleich laeuft ueber die Grenze 18, NICHT ueber
    // [ageGroup]. Die Enum-Werte adult18/adult19/adult unterscheiden
    // noch die alte gestufte Regel - im Enum sind 18 und 19
    // verschiedene Gruppen, nach der beidseitigen Server-Regel sind
    // beide schlicht "Erwachsen". Mit dem Enum-Vergleich waere ein
    // 18-Jaehriger fuer einen 19-Jaehrigen unsichtbar - der Server
    // liefert ihn aber.
    final viewerMinderjaehrig = viewerAge < 18;
    final targetMinderjaehrig = targetAge < 18;
    final erlaubt = viewerMinderjaehrig == targetMinderjaehrig;
    if (kDebugMode) debugPrint('[AGE_SAFETY] beidseitig -> erlaubt=$erlaubt');
    return erlaubt;
  }

  /// Gibt die maximal erlaubte obere Altersgrenze für den Filter-Slider zurück.
  ///
  /// - 16-17: maximal 17 Jahre. Der Server liefert fuer Minderjaehrige
  ///   ausschliesslich 16 und 17 (age_compatible_bidirectional), ein
  ///   Wert darueber waere ein toter Filter.
  /// - 18+: maximal 99 Jahre. Die Obergrenze bleibt bewusst offen - wer
  ///   aeltere Menschen sehen will, soll das koennen.
  static int maxFilterAge(int viewerAge) {
    final group = ageGroup(viewerAge);
    if (group == AgeGroup.minor) return 17;
    return 99;
  }

  /// Gibt die minimal erlaubte untere Altersgrenze für den Filter-Slider zurück.
  ///
  /// - 16-17: 16 Jahre (untereinander ja)
  /// - 18: 18 Jahre
  /// - 19: 18 Jahre
  /// - 20+: hoechstens 10 Jahre unter dem eigenen Alter, aber nie
  ///   unter 18.
  ///
  /// WICHTIG (04.11.2026): Bis hierher stand fuer 18-Jaehrige die
  /// Grenze 16 und fuer 19-Jaehrige die Grenze 17. Das war ein TOTER
  /// FILTER: Der Server filtert die Discovery beidseitig (Migration
  /// 154), ein 18-Jaehriger bekommt also NIE einen 16- oder
  /// 17-Jaehrigen zu sehen - und ein 19-Jaehriger nie einen
  /// 17-Jaehrigen. Wer die Grenze auf 16/17 stellte, bekam eine leere
  /// Liste und keine Erklaerung.
  ///
  /// Die Grenze steht hier bewusst UEBER dem, was der Server als
  /// kleinstes Zielalter zulaesst: nach oben wegzulassen ist harmlos
  /// (der Filter grenzt nur ein), nach unten zu gehen bedeutet "gar
  /// keine Ergebnisse".
  ///
  /// Fuer 20+ bleibt das Fenster "hoechstens 10 Jahre unter mir" - das
  /// ist eine Produktentscheidung, keine Jugendschutzgrenze. Der
  /// Server liefert dort mehr, als der Filter zulaesst.
  static int minFilterAge(int viewerAge) {
    if (viewerAge < 18) return 16;
    // Ab 18 liefert der Server ausschliesslich Erwachsene
    // (age_compatible_bidirectional). Der Filter darf deshalb nicht
    // unter 18 gehen - sonst ist er tot.
    if (viewerAge <= 19) return 18;
    return math.max(18, viewerAge - 10);
  }

  /// Prüft, ob der Nutzer die "Persönlichkeit vor Aussehen" (Blind Mode) Einstellung
  /// für die FOTO-SICHTBARKEIT überschreiben darf.
  ///
  /// - 16-17: Blind Mode wird ERZWUNGEN
  /// - 18+: Nutzer kann Blind Mode frei wählen
  static bool isBlindModeForced(int viewerAge) {
    return ageGroup(viewerAge) == AgeGroup.minor;
  }

  /// Dürfen Minderjährige (16-17) die **grobe Entfernung** anzeigen?
  ///
  /// BETREIBER-ENTSCHEIDUNG (02.11.2026): "Die grobe Entfernung
  /// dürfen 16 und 17 jährige auch nicht aktivieren können."
  ///
  /// Hintergrund: Der Schalter "Entfernung anzeigen" stand für alle
  /// offen. Damit konnte ein 16-Jähriger mitteilen, wie weit weg
  /// jemand wohnt - in einem Umfeld, in dem das mehr verrät als bei
  /// Erwachsenen.
  ///
  /// - 16-17: gesperrt
  /// - 18+: frei wählbar
  ///
  /// Die maechtige Sperre sitzt in der Datenbank
  /// (`profile_distance_km`, Migration 163): sie benutzt das
  /// VERIFIZIERTE Alter. Diese Regel hier ist die freundliche Seite -
  /// damit der Schalter gar nicht erst angeboten wird.
  static bool isRoughDistanceForced(int viewerAge) {
    return ageGroup(viewerAge) == AgeGroup.minor;
  }

  /// Höchster Suchradius (in km) für Minderjährige (16-17).
  ///
  /// BETREIBER-ENTSCHEIDUNG (03.11.2026): "für 16 und 17 jährige
  /// entweder gleiches Bundesland oder max. 25 Km".
  ///
  /// Der Wert steht hier und in der Datenbank (Migration 164, Body von
  /// `profile_discovery_visible`). Beide Stellen müssen zusammenpassen -
  /// ein zweiter, abweichender Wert in der Datenbank wäre die klassische
  /// Stelle, an der eine Grenze auseinanderläuft.
  static const int minorMaxDiscoveryRadiusKm = 25;

  /// Dürfen Minderjährige (16-17) den Suchradius unbegrenzt wählen?
  ///
  /// - 16-17: begrenzt (25 km ODER nur das gleiche Bundesland)
  /// - 18+: frei wählbar
  ///
  /// Die maechtige Sperre sitzt in der Datenbank
  /// (`profile_discovery_visible`, Migration 164): sie benutzt das
  /// VERIFIZIERTE Alter und greift auch bei einem gepatchten Client.
  /// Diese Regel hier ist die freundliche Seite - damit gar nicht erst
  /// ein Radius angeboten wird, den der Server ohnehin verweigert.
  static bool isDiscoveryRadiusCapped(int viewerAge) {
    return ageGroup(viewerAge) == AgeGroup.minor;
  }

  /// Der größte wählbare Suchradius (in km) für diesen Nutzer.
  static int maxDiscoveryRadiusKm(int viewerAge) {
    return isDiscoveryRadiusCapped(viewerAge)
        ? minorMaxDiscoveryRadiusKm
        : AppConstants.maxDistanceKm;
  }

  /// Darf der Modus "Ganz Deutschland" gewählt werden?
  ///
  /// Server-seitig wird er für Minderjährige wie "maximal 25 km"
  /// behandelt (fail-closed, Migration 164). Hier wird er ausgegraut.
  static bool isWholeGermanyAllowed(int viewerAge) {
    return !isDiscoveryRadiusCapped(viewerAge);
  }

  /// Bestimmt den effektiven Foto-Sichtbarkeits-Modus für ein Profil.
  ///
  /// Berücksichtigt:
  /// - Altersgruppe des Profil-Besitzers (targetAge)
  /// - Altersgruppe des Betrachters (viewerAge)
  /// - Blind Mode Einstellung des Profil-Besitzers (nur für 18+ relevant)
  /// - revealPhotosAfterMatch Einstellung des Profil-Besitzers (nur für 18+ relevant)
  ///
  /// Rückgabe:
  /// - true = Fotos sind sichtbar (nach Match oder sofort je nach Einstellung)
  /// - false = Fotos sind verborgen (Blind Mode aktiv)
  static bool arePhotosVisible({
    required int targetAge, // Alter des Profil-Besitzers
    required int viewerAge, // Alter des Betrachters
    required bool blindModeEnabled, // Einstellung des Profil-Besitzers
    required bool revealPhotosAfterMatch, // Einstellung des Profil-Besitzers
    required bool isMatched, // Ob ein Match besteht
  }) {
    final targetGroup = ageGroup(targetAge);
    final viewerGroup = ageGroup(viewerAge);

    // 16-17: Fotos NUR für andere Minderjährige sichtbar
    if (targetGroup == AgeGroup.minor) {
      return viewerGroup == AgeGroup.minor;
    }

    // 18+: Regeln basierend auf Einstellungen
    if (!blindModeEnabled) {
      // Blind Mode aus -> Fotos sofort sichtbar
      return true;
    }
    // Blind Mode an -> Fotos nur nach Match
    return isMatched;
  }

  /// Prüft, ob der Nutzer die Foto-Sichtbarkeits-Einstellungen ändern darf.
  ///
  /// - 16-17: NEIN (strikt durch Altersgruppe erzwungen)
  /// - 18+: JA (frei wählbar)
  static bool canChangePhotoVisibilitySettings(int age) {
    return ageGroup(age) != AgeGroup.minor;
  }

  /// Prüft, ob ein Alters-Filter-Wert (min/max) für den Nutzer erlaubt ist.
  static bool isValidFilterAge({
    required int viewerAge,
    required int filterMin,
    required int filterMax,
  }) {
    final allowedMin = minFilterAge(viewerAge);
    final allowedMax = maxFilterAge(viewerAge);
    return filterMin >= allowedMin &&
        filterMax <= allowedMax &&
        filterMin <= filterMax;
  }

  /// Korrigiert einen Alters-Filter auf die erlaubten Grenzen.
  static (int min, int max) clampFilterAge({
    required int viewerAge,
    required int filterMin,
    required int filterMax,
  }) {
    final allowedMin = minFilterAge(viewerAge);
    final allowedMax = maxFilterAge(viewerAge);
    final clampedMin = filterMin.clamp(allowedMin, allowedMax);
    final clampedMax = filterMax.clamp(clampedMin, allowedMax);
    return (clampedMin, clampedMax);
  }
}
