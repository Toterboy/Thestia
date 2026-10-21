// Zentrale Alters-Schutz-Regeln für die Blind Date App.
//
// Stufenweise Sichtbarkeitsregeln:
// - 16-17: nur untereinander sichtbar.
// - 18+: kann 16+ sehen.
// - 19+: kann 17+ sehen.
// - 20+: kann 18+ sehen.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

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
  /// Stufenweise Regeln:
  /// - 16-17: nur untereinander sichtbar
  /// - 18+: kann 16+ sehen
  /// - 19+: kann 17+ sehen
  /// - 20+: kann 18+ sehen
  static bool canViewProfile({
    required int viewerAge,
    required int targetAge,
  }) {
    if (kDebugMode) debugPrint('[AGE_SAFETY] canViewProfile: viewerAge=$viewerAge, targetAge=$targetAge');
    final viewerGroup = ageGroup(viewerAge);
    final targetGroup = ageGroup(targetAge);
    if (kDebugMode) debugPrint('[AGE_SAFETY] viewerGroup=$viewerGroup, targetGroup=$targetGroup');

    // 16-17: nur untereinander sichtbar
    if (viewerGroup == AgeGroup.minor) {
      final allowed = targetGroup == AgeGroup.minor;
      if (kDebugMode) debugPrint('[AGE_SAFETY] MINOR viewer -> allowed=$allowed');
      return allowed;
    }

    // 18+: darf 16+ sehen
    if (viewerGroup == AgeGroup.adult18) {
      final allowed = targetAge >= 16;
      if (kDebugMode) debugPrint('[AGE_SAFETY] ADULT18 viewer -> allowed=$allowed');
      return allowed;
    }

    // 19+: darf 17+ sehen
    if (viewerGroup == AgeGroup.adult19) {
      final allowed = targetAge >= 17;
      if (kDebugMode) debugPrint('[AGE_SAFETY] ADULT19 viewer -> allowed=$allowed');
      return allowed;
    }

    // 20+: darf 18+ sehen
    final allowed = targetAge >= 18;
    if (kDebugMode) debugPrint('[AGE_SAFETY] ADULT20+ viewer -> allowed=$allowed');
    return allowed;
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
  /// - 18: 16 Jahre (der Server erlaubt einem 18-Jaehrigen, 16-Jaehrige
  ///   zu sehen - allerdings nicht umgekehrt, siehe [canViewProfile])
  /// - 19: 17 Jahre
  /// - 20+: hoechstens 10 Jahre unter dem eigenen Alter, aber nie
  ///   unter 18. Der Server erzwingt dasselbe (max_age_range_min,
  ///   Migration 154) - ohne diese Grenze war der Filter tot, ohne
  ///   dass die UI das erklaert haette.
  ///
  /// WICHTIG: Der Server filtert BEIDSEITIG (Migration 154). Ein
  /// 18-Jaehriger sieht also in der Praxis KEINE 16- und 17-Jaehrigen,
  /// auch wenn der Regler es erlauben wuerde. Die Grenze hier ist so
  /// gewaehlt, dass die App keine Werte anbietet, die der Server nicht
  /// liefert - sonst stellt der Nutzer einen Filter ein und wundert
  /// sich ueber leere Ergebnisse.
  static int minFilterAge(int viewerAge) {
    if (viewerAge < 18) return 16;
    if (viewerAge == 18) return 16;
    if (viewerAge == 19) return 17;
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
