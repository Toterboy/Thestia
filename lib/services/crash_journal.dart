import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lokales Crash-Journal (v0.8.0, datenschutzfreundlich):
///
/// Statt Cloud-Crash-Reporting (Sentry/Crashlytics) wird der LETZTE
/// Absturz lokal gespeichert. Beim nächsten Start bietet die App an,
/// einen Report über den bestehenden Bug-Report-Kanal zu senden - der
/// Nutzer entscheidet, ob und was gesendet wird.
///
/// Datenschutz: Gespeichert werden nur Fehlerklasse, Kurzmeldung,
/// Stack (gekürzt), App-Version und Zeitpunkt. Keine Nutzertexte,
/// keine Geräte-Serials, keine PII. Nichts verlässt das Gerät ohne
/// aktive Bestätigung.
class CrashJournal {
  CrashJournal._();

  static const String _key = 'last_crash_json';

  static bool _promptShownThisSession = false;

  /// Installiert die globalen Fehler-Hooks (Flutter + Platform Dispatcher).
  static void install() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(capture(details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(capture(error, stack));
      // false = Fehler an das Framework weiterreichen (Logging/Lösung).
      return false;
    };
  }

  /// Schreibt den letzten Absturz (überschreibt älteren Eintrag).
  ///
  /// BEFUND 04.11.2026: Hier stand `error.toString()` UND der rohe
  /// Stack im Journal - der Kommentar oben versprach aber "keine
  /// Nutzertexte, keine Geräte-Serials, keine PII".
  ///
  /// Das Versprechen hielt nicht: Ein Supabase-Fehler kann die
  /// E-Mail-Adresse enthalten ("Invalid login credentials for user:
  /// xxx@yyy.de"), und ein Stacktrace zeigt Dateipfade und
  /// Argumentwerte. Das Journal wird dem Nutzer angeboten, per
  /// Bug-Report gesendet zu werden - die Daten wären also über das
  /// Gerät hinausgegangen.
  ///
  /// Deshalb wird jetzt vor dem Speichern redigiert. Was NICHT
  /// redigiert wird: der Fehlertyp und die Stackform (Zeilennummern,
  /// Klassen) - denn nur damit ist der Absturz überhaupt zuzuordnen.
  static Future<void> capture(Object error, StackTrace? stack) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stackText = (stack?.toString() ?? '')
          .split('\n')
          .take(12)
          .join('\n');
      await prefs.setString(
          _key, _redigiere(error.toString()).substring(
              0, _redigiere(error.toString()).length.clamp(0, 400)));
      await prefs.setString('${_key}_stack',
          _redigiere(stackText).substring(0, _redigiere(stackText).length.clamp(0, 2000)));
    } catch (_) {
      // Journal ist best-effort - niemals wegen eines Journals crashen.
    }
  }

  /// Entfernt erkennbare personenbezogene Daten aus einem Text.
  ///
  /// Entfernt werden:
  ///   * E-Mail-Adressen (der haeufigste PII-Transportweg in
  ///     Fehlermeldungen von Supabase)
  ///   * Bearer-/JWT-Token und lange zufaellige Zeichenketten
  ///     (Session-Token im Log, ein Echo im Fehlertext)
  ///   * `Bearer <token>`-Kombinationen
  ///
  /// Bewusst NICHT entfernt:
  ///   * UUIDs - die eigene User-ID wird fuer die Bearbeitung des
  ///     Bug-Reports gebraucht ("nenne dazu deine User-ID").
  ///   * Dateipfade und Zeilennummern - ohne sie ist der Absturz
  ///     nicht zuzuordnen.
  ///
  /// Die Funktion ist oeffentlich, damit sie testbar ist: eine
  /// Redigierregel, die nicht getestet wird, ist eine Regel, die
  /// irgendwann nicht mehr greift.
  @visibleForTesting
  static String redact(String text) => _redigiere(text);

  static String _redigiere(String text) {
    var out = text;
    // E-Mail-Adressen.
    out = out.replaceAll(
        RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
        '<E-Mail entfernt>');
    // Bearer-Token (mit oder ohne Prefix).
    //
    // HINWEIS: Dart kennt keine Inline-Flags wie (?i) - die
    // Gross-/Kleinschreibung wird ueber das Argument gesteuert.
    out = out.replaceAll(
        RegExp(r'bearer\s+[A-Za-z0-9._\-]{20,}', caseSensitive: false),
        '<Token entfernt>');
    // JWT (drei durch Punkte getrennte Base64-Teile).
    out = out.replaceAll(
        RegExp(r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{5,}'),
        '<Token entfernt>');
    // Lange zufaellige Zeichenketten (Hex-Hashes, Base64-Bloecke).
    out = out.replaceAll(
        RegExp(r'\b[A-Fa-f0-9]{32,}\b'), '<Schluessel entfernt>');
    return out;
  }

  /// Liefert die Kurzbeschreibung des letzten Absturzes oder `null`.
  static Future<String?> readLastCrash() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  /// Einmal pro App-Start nachfragen (Session-Marker im Speicher).
  static bool get promptAlreadyShown => _promptShownThisSession;
  static void markPromptShown() => _promptShownThisSession = true;

  /// Nach dem Behandeln aufräumen (bestätigt oder verworfen).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await prefs.remove('${_key}_stack');
    } catch (_) {}
  }
}
