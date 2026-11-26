import 'package:flutter_test/flutter_test.dart';
import '../support/quelltext.dart';

/// Test für die Reihenfolge der Lösch-Punkte.
///
/// BETREIBER (06.11.2026): "Konto löschen und Daten löschen sollen
/// die untersten Punkte sein."
///
/// Ein zerstörerischer Eintrag mitten in der Liste wird leicht
/// versehentlich angefasst - die Lösch-Wege gehören ans Ende.
///
/// Der Test liest den Quelltext (bewusst so, wie die anderen
/// Reihenfolge-Prüfer in diesem Projekt): Die Reihenfolge ergibt sich
/// aus dem Aufbau des Widgets, nicht aus einer Liste, die man
/// umsortieren kännte.
void main() {
  group('Die Reihenfolge der Loesch-Punkte', () {
    late String settings;
    late String privacy;

    setUp(() {
      settings = liesQuelltext('lib/screens/settings/settings_screen.dart');
      privacy = liesQuelltext('lib/screens/privacy/privacy_screen.dart');
    });

    test('in den Einstellungen stehen sie in der Gefahrenzone', () {
      expect(
        settings.contains("'privacy.dangerZone'"),
        isTrue,
        reason:
            'die Einstellungen brauchen einen eigenen Gefahrenzone-Abschnitt',
      );
      // Der Abschnitt steht HINTER dem Abmelden-Knopf.
      final ausloggen = settings.indexOf("'settings.logout'");
      final gefahr = settings.indexOf("'privacy.dangerZone'");
      expect(
        gefahr,
        greaterThan(ausloggen),
        reason:
            'die Gefahrenzone muss der LETZTE Abschnitt der Einstellungen '
            'sein - sonst steht "Daten loeschen" mitten in der Liste',
      );
    });

    test('"Daten löschen" steht in der Gefahrenzone, nicht davor', () {
      final gefahr = settings.indexOf("'privacy.dangerZone'");
      final daten = settings.indexOf("'settings.deleteData'");
      final konto = settings.indexOf("'privacy.deleteAccount'");
      expect(daten, greaterThan(gefahr));
      expect(konto, greaterThan(gefahr));
    });

    test('im Datenschutz-Bereich stehen beide Loesch-Wege zusammen', () {
      final gefahr = privacy.indexOf("'privacy.dangerZone'");
      expect(gefahr, greaterThan(0));
      expect(
        privacy.indexOf("'settings.deleteData'"),
        greaterThan(gefahr),
        reason:
            'im Datenschutz-Bereich gehoeren "Daten loeschen" und "Konto '
            'loeschen" zusammen in der Gefahrenzone',
      );
      expect(privacy.indexOf("'privacy.deleteAccount'"), greaterThan(gefahr));
    });

    test('der Lösch-Ablauf wird nur einmal implementiert', () {
      // Der Ablauf (MFA-Step-up, Bestätigung, Löschung) liegt in
      // delete_account_action.dart - beide Bildschirme nutzen ihn. Sonst
      // gibt es zwei Varianten, und nur eine wird gepflegt.
      final action = liesQuelltext(
        'lib/screens/privacy/delete_account_action.dart',
      );
      expect(action.contains('deleteAccountWithConfirmation'), isTrue);
      expect(
        action.contains('promptTotpCode'),
        isTrue,
        reason:
            'das MFA-Step-up gehoert zum Ablauf - es darf nicht nur an '
            'einer Stelle stehen',
      );
    });
  });
}
