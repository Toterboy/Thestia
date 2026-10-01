import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Wachhund für den App-Start.
///
/// Problem, das er löst: stirbt die App während des Startens, sieht der
/// Nutzer nur den Splash und danach die Systemmeldung "Die App konnte
/// nicht gestartet werden". Kein Log, kein Fehlerbildschirm, kein
/// Hinweis, an welcher Stelle es passiert ist. Das [CrashJournal] hilft
/// dafür nicht: es schreibt asynchron, und ein Prozess, der sofort
/// stirbt, kommt nicht mehr dazu.
///
/// Deshalb wird der Start als Liste von Schritten geführt. Nach jedem
/// Schritt wird der zuletzt erreichte in SharedPreferences geschrieben.
/// Wird der Prozess danach beendet, steht beim nächsten Start fest: der
/// letzte Schritt, und - falls eine Ausnahme auftrat - deren Text.
///
/// Am Ende wird [markAlive] gerufen. Fehlt dieses Kennzeichen beim
/// nächsten Start, ist der letzte Versuch gestorben, und die App zeigt
/// einen Bildschirm mit dem Befund an, statt den Fehler zu verschlucken.
///
/// EINE EINSCHRÄNKUNG, die man nicht wegdefinieren kann: stirbt der
/// Prozess, bevor Dart überhaupt läuft (Absturz in der Application oder
/// in der Activity, also nativ), wird nichts aufgezeichnet. Dann
/// bleibt [lastStep] auf `null` - und genau das ist die
/// Unterscheidung, die man im Fehlerfall braucht: `null` heißt
/// "nichts erreicht, also vor Dart" und ist selbst die Information.
///
/// Auf der Platte steht nur ein Schrittname und ein Fehlertext. Keine
/// Nutzerdaten, keine Tokens, keine Gerätekennungen.
class StartupWatchdog {
  StartupWatchdog._();

  static const String _stepKey = 'startup_last_step';
  static const String _errorKey = 'startup_last_error';
  static const String _aliveKey = 'startup_alive';
  static const String _timeKey = 'startup_last_time';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// Kette der Schreibvorgaenge.
  ///
  /// [reached] ist absichtlich fire-and-forget, damit der Start nie
  /// wartet. Preis davon: mehrere Schritte schreiben gleichzeitig, und
  /// SharedPreferences garantiert fuer parallele Schreibvorgaenge keine
  /// Reihenfolge. Ohne diese Kette kann der AELTERE Schritt zuletzt
  /// ankommen, und im Bericht stuende "Schritt 1", obwohl "Schritt 3"
  /// erreicht war. Genau darauf verlaesst man sich, wenn man den
  /// Bildschirm liest.
  static Future<void> _queue = Future<void>.value();

  static void _enqueue(Future<void> Function() action) {
    _queue = _queue.then((_) => action()).catchError((Object _) {});
  }

  /// Die Schritte des Startvorgangs, in fester Reihenfolge.
  ///
  /// Der Name ist absichtlich grobkörnig: er wird angezeigt, und ein
  /// Nutzer kann mit "Schritt 4 von 7" nichts anfangen. Mit dem Namen
  /// schon eher.
  static const List<String> steps = <String>[
    'dart-main',            // main() läuft
    'binding',              // Flutter-Binding steht
    'keystore',             // Keystore-Migration durch oder übersprungen
    'ui',                   // runApp() gerufen, erster Frame möglich
    'dienste',              // Supabase, Prefs, Env
    'app',                  // Bootstrap fertig, echte App läuft
  ];

  /// Meldet einen erreichten Schritt.
  ///
  /// Bewusst `fire and forget`: der Schritt darf den Start nie
  /// aufhalten. Eine Exception hier wird verschluckt - ein Wächter, der
  /// durch sein eigenes Scheitern einen Absturz auslöst, wäre
  /// widersinnig.
  static void reached(int step, {Object? error}) {
    if (step < 0 || step >= steps.length) return;
    _enqueue(() => _write(steps[step], error));
  }

  static Future<void> _write(String step, Object? error) async {
    try {
      final p = await _prefs();
      await p.setString(_stepKey, step);
      await p.setString(_timeKey, DateTime.now().toIso8601String());
      if (error != null) {
        final text = error.toString();
        await p.setString(
            _errorKey, text.substring(0, text.length.clamp(0, 400)));
      } else {
        await p.remove(_errorKey);
      }
    } catch (_) {
      // never let the watchdog cause the failure it watches
    }
  }

  /// Markiert den Start als erfolgreich abgeschlossen.
  static void markAlive() {
    _enqueue(_markAlive);
  }

  static Future<void> _markAlive() async {
    try {
      final p = await _prefs();
      await p.setBool(_aliveKey, true);
      await p.remove(_errorKey);
    } catch (_) {}
  }

  /// Befund über den letzten Startversuch.
  ///
  /// `null`, wenn der letzte Versuch sauber durchgelaufen ist. Sonst
  /// [hadPreviousFailure] mit Schritt, Fehlertext und Zeitpunkt.
  static Future<StartupFailure?> readPreviousAttempt() async {
    try {
      final p = await _prefs();
      if (p.getBool(_aliveKey) == true) {
        // Letzter Start war gut. Aufräumen, damit der nächste Fehler
        // nicht mit einem alten Eintrag verwechselt wird.
        await p.remove(_stepKey);
        await p.remove(_errorKey);
        await p.remove(_timeKey);
        return null;
      }
      final step = p.getString(_stepKey);
      if (step == null) {
        // Kein Schritt und kein "alive": entweder der allererste Start
        // nach der Installation, oder der Prozess starb vor Dart.
        return StartupFailure(
          step: null,
          stepIndex: -1,
          error: p.getString(_errorKey),
          time: p.getString(_timeKey),
          diedBeforeDart: true,
        );
      }
      return StartupFailure(
        step: step,
        stepIndex: steps.indexOf(step),
        error: p.getString(_errorKey),
        time: p.getString(_timeKey),
        diedBeforeDart: false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Befund eines fehlgeschlagenen Startversuchs.
class StartupFailure {
  const StartupFailure({
    required this.step,
    required this.stepIndex,
    required this.error,
    required this.time,
    required this.diedBeforeDart,
  });

  /// Name des letzten erreichten Schritts, `null` wenn nichts erreicht
  /// wurde.
  final String? step;

  /// Position von [step] in [StartupWatchdog.steps], `-1` wenn nichts.
  final int stepIndex;

  /// Text der Ausnahme, falls eine auftrat.
  final String? error;

  /// Zeitpunkt des Abbruchs (ISO-8601).
  final String? time;

  /// Ob der Prozess starb, bevor Dart überhaupt lief.
  ///
  /// Der wichtigste Unterschied überhaupt: dann hilft kein Dart-Werkzeug
  /// weiter, und man muss nativ suchen.
  final bool diedBeforeDart;

  /// Kurztext zum Anzeigen.
  String get headline => diedBeforeDart
      ? 'Absturz vor dem Start der App-Logik'
      : 'Absturz bei Schritt ${stepIndex + 1} von '
          '${StartupWatchdog.steps.length}: $step';

  /// Vollständiger Text zum Kopieren und Teilen.
  String toReport() {
    final b = StringBuffer()
      ..writeln('Thestia - Startprotokoll')
      ..writeln('Schritt: $headline')
      ..writeln('Zeitpunkt: ${time ?? 'unbekannt'}');
    if (error != null) {
      b.writeln();
      b.writeln('Fehler:');
      b.writeln(error);
    }
    if (diedBeforeDart) {
      b.writeln();
      b.writeln('Hinweis: Es wurde kein Dart-Schritt erreicht. Der '
          'Absturz liegt damit vor dem Start der App-Logik, also im '
          'nativen Teil (Application/Activity) oder in einem Plugin, '
          'das beim Laden fehlschlaegt.');
    }
    b.writeln();
    b.writeln('Schritte: ${StartupWatchdog.steps.join(' -> ')}');
    return b.toString();
  }

  @override
  String toString() => 'StartupFailure($headline)';
}
