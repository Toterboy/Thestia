import 'package:flutter/foundation.dart';

/// Führt einen Schritt aus, dessen Fehler den Ablauf nicht stoppen darf.
///
/// WOFÜR DAS DA IST (05.11.2026): Beim Aufräumen - Abmelden, Konto
/// löschen, Gerät abmelden - darf ein fehlgeschlagener Einzelschritt
/// den ganzen Vorgang nicht abbrechen. Bricht er ab, bleiben fremde
/// Reste zurück: Verlauf, Entwürfe, Schlüssel, Crash-Journal. Der
/// nächste Account auf demselben Gerät sieht sie.
///
/// WAS SICH AENDERT: Vorher war das ein leeres `catch (_) {}` - der
/// Fehler wurde spurlos geschluckt, niemand konnte sehen, dass beim
/// Aufräumen etwas schiefging. Jetzt wird er protokolliert. Im
/// Release ist [debugPrint] stumm, im Debug steht im Log, welcher
/// Schritt fehlgeschlagen ist.
///
/// [beschreibung] sagt, welcher Schritt das war - zum Beispiel
/// 'Verlauf löschen'. Sie steht im Log, deshalb sollte sie den
/// Schritt benennen und nicht den Fehler beschreiben.
///
/// [schritt] ist die Arbeit selbst. Der Fehler wird geschluckt, aber
/// nicht vergessen: Der Aufrufer macht weiter.
Future<void> bestEffort(
  String beschreibung,
  Future<void> Function() schritt,
) async {
  try {
    await schritt();
  } catch (fehler, stapel) {
    _melde(beschreibung, fehler, stapel);
  }
}

/// Wie [bestEffort], aber für einen Schritt, der nicht wartet.
///
/// Für Schritte, die sofort fertig sind (ein Cache leeren, eine
/// Identität zurücksetzen) - dort wäre ein `await` auf einen
/// synchronen Aufruf nur eine leere Warteschleife.
void bestEffortSync(
  String beschreibung,
  void Function() schritt,
) {
  try {
    schritt();
  } catch (fehler, stapel) {
    _melde(beschreibung, fehler, stapel);
  }
}

/// Wie [bestEffort], aber der Schritt liefert einen Wert.
///
/// [fallback] ist das Ergebnis, wenn der Schritt fehlschlägt. Damit
/// lassen sich die Fälle abbilden, in denen ein `return` im alten
/// `try`-Block stand:
///
/// ```dart
/// // vorher
/// try {
///   final x = await lade();
///   if (x.fehlt) return false;
/// } catch (_) {}
///
/// // jetzt
/// final fehlt = await bestEffortOr('laden', () async {
///   final x = await lade();
///   return x.fehlt;
/// }, false);
/// if (fehlt) return false;
/// ```
Future<T> bestEffortOr<T>(
  String beschreibung,
  Future<T> Function() schritt,
  T fallback,
) async {
  try {
    return await schritt();
  } catch (fehler, stapel) {
    _melde(beschreibung, fehler, stapel);
    return fallback;
  }
}

/// Wie [bestEffortOr], aber für einen Schritt, der nicht wartet.
T bestEffortOrSync<T>(
  String beschreibung,
  T Function() schritt,
  T fallback,
) {
  try {
    return schritt();
  } catch (fehler, stapel) {
    _melde(beschreibung, fehler, stapel);
    return fallback;
  }
}

void _melde(String beschreibung, Object fehler, StackTrace stapel) {
  debugPrint('[BEST-EFFORT] $beschreibung fehlgeschlagen: $fehler');
  if (kDebugMode) {
    debugPrintStack(stackTrace: stapel, label: beschreibung);
  }
}
