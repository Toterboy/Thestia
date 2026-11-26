// Die Passwort-Regeln der REGISTRIERUNG.
//
// ANLASS (19.11.2026): Bei der Coverage-Messung war
// `lib/utils/security/validators.dart` nur zu 63 % abgedeckt - genau die beiden
// Methoden, die die Server-Policy durchsetzen, fehlten:
// `registrationPassword` und `passwordStrength`.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Registrierung verlangt 8 Zeichen, Klein- UND Großbuchstabe,
//     eine Zahl und ein Sonderzeichen,
//   * fehlende Regeln werden ALLE genannt (sonst sieht der Nutzer nur
//     die erste und weiß nicht, was noch fehlt),
//   * die Blockliste wirkt auch, wenn das Passwort Sonderzeichen hat
//     (sonst wäre sie wirkungslos),
//   * die Stärke-Anzeige stuft nach den Klassen ein.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/security/validators.dart';

/// Liefert einen BuildContext (Default-Locale Deutsch, wie ohne Scope).
Future<BuildContext> _ctx(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    ),
  );
  return ctx;
}

void main() {
  group('Die Passwort-Regeln fuer die Registrierung', () {
    testWidgets('ein leeres Passwort wird abgelehnt', (tester) async {
      final ctx = await _ctx(tester);
      expect(Validators.registrationPassword(ctx, null), isNotNull);
      expect(Validators.registrationPassword(ctx, ''), isNotNull);
    });

    testWidgets('ein Passwort mit allen Klassen wird angenommen', (
      tester,
    ) async {
      final ctx = await _ctx(tester);
      expect(Validators.registrationPassword(ctx, 'Sicher!7x'), isNull);
    });

    testWidgets('zu kurze Passwoerter werden abgelehnt', (tester) async {
      final ctx = await _ctx(tester);
      final fehler = Validators.registrationPassword(ctx, 'Aa1!bb');
      expect(fehler, isNotNull);
      expect(fehler, contains('8 Zeichen'));
    });

    testWidgets('fehlende Klassen werden ALLE genannt', (tester) async {
      final ctx = await _ctx(tester);
      // Nur Kleinbuchstaben und eine Zahl: es fehlen Großbuchstabe
      // und Sonderzeichen.
      final fehler = Validators.registrationPassword(ctx, 'passwort7');
      expect(fehler, isNotNull);
      expect(fehler, contains('einen Großbuchstaben'));
      expect(fehler, contains('ein Sonderzeichen'));
      // Die vorhandenen Klassen werden NICHT bemängelt.
      expect(fehler, isNot(contains('einen Kleinbuchstaben')));
      expect(fehler, isNot(contains('eine Zahl')));
    });

    testWidgets('ohne jede Klasse fehlen alle vier Regeln', (tester) async {
      final ctx = await _ctx(tester);
      // Nur Buchstaben klein: die Zahl, der Großbuchstabe und das
      // Sonderzeichen fehlen (die Länge ist mit 8 Zeichen erfüllt).
      final fehler = Validators.registrationPassword(ctx, 'abcdefgh');
      expect(fehler, isNotNull);
      expect(fehler, contains('einen Großbuchstaben'));
      expect(fehler, contains('eine Zahl'));
      expect(fehler, contains('ein Sonderzeichen'));
    });

    testWidgets('Umlaute zaehlen als Klein- und Grossbuchstabe', (
      tester,
    ) async {
      final ctx = await _ctx(tester);
      // "äöü" (klein) und "ÄÖÜ" (groß) - mit Zahl und Sonderzeichen.
      expect(Validators.registrationPassword(ctx, 'äöüÄÖÜ7!'), isNull);
    });

    testWidgets('ein haeufiges Passwort wird auch mit Sonderzeichen '
        'abgelehnt', (tester) async {
      final ctx = await _ctx(tester);
      // DER GRUND für die Normalisierung: "Passwort1!" enthält alle
      // Klassen, ist aber ein bekanntes Passwort. Ohne Normalisierung
      // (klein, ohne Sonderzeichen) wäre die Blockliste wirkungslos.
      final fehler = Validators.registrationPassword(ctx, 'Passwort1!');
      expect(fehler, isNotNull);
      expect(fehler, contains('zu häufig'));
    });
  });

  group('Die Staerke-Anzeige', () {
    testWidgets('ein kurzes, einfaches Passwort ist schwach', (tester) async {
      final ctx = await _ctx(tester);
      expect(Validators.passwordStrength(ctx, 'abc'), 'Schwach');
    });

    testWidgets('ein Passwort mit mehreren Klassen ist mittel', (tester) async {
      final ctx = await _ctx(tester);
      // 8 Zeichen + Klein + Groß + Zahl = 4 Punkte -> mittel.
      expect(Validators.passwordStrength(ctx, 'Abcdefg7'), 'Mittel');
    });

    testWidgets('ein langes Passwort mit allen Klassen ist stark', (
      tester,
    ) async {
      final ctx = await _ctx(tester);
      // 12 Zeichen + alle vier Klassen = 6 Punkte -> stark.
      expect(Validators.passwordStrength(ctx, 'Abcdefg7!hij'), 'Stark');
    });

    testWidgets('die Grenze 12 Zeichen zaehlt extra', (tester) async {
      final ctx = await _ctx(tester);
      // 11 Zeichen (1) + Klein (1) + Groß (1) + Zahl (1) = 4 -> mittel.
      expect(Validators.passwordStrength(ctx, 'Abcdefg7hij'), 'Mittel');
      // 12 Zeichen (2 Punkte statt 1) + dieselben Klassen = 5 -> stark.
      expect(Validators.passwordStrength(ctx, 'Abcdefg7hijk'), 'Stark');
    });
  });
}
