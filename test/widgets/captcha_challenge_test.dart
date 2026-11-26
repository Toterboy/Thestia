// Der Sicherheitscheck (CAPTCHA) im Fenster.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/settings/captcha_challenge.dart 70 offene Zeilen bei 1
// gedeckten - der Screen war ungetestet. Das ist der Weg, den die
// Registrierung und der Login jedes Nutzers geht.
//
// ZWEI SACHEN MUSSTEN DAZU:
//   1) der WebView (test/support/webview_fake.dart) - ohne ihn lässt
//      sich das Fenster gar nicht bauen,
//   2) ein Sitekey in der Umgebung - sonst ist das CAPTCHA
//      abgeschaltet (AppConstants.captchaEnabled) und der Weg wird nie
//      betreten. Der Test setzt ihn mit dotenv.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne aktiviertes CAPTCHA gibt es kein Fenster (und kein Token),
//   * das Fenster lädt die Turnstile-Seite von auth.thestia.de,
//   * ein Token schließt das Fenster (und kommt beim Aufrufer an),
//   * ein unplausibles Token wird verworfen (Sicherheit!),
//   * die Fehlercodes von Cloudflare werden übersetzt,
//   * nur die erlaubten Adressen werden geladen,
//   * "Erneut versuchen" lädt die Seite neu,
//   * "Abbrechen" schließt das Fenster ohne Token.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
// Die WebView-Schnittstelle kommt als Transitivum über webview_flutter -
// der Test braucht nur ihre Typen.
// ignore_for_file: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/settings/captcha_challenge.dart';

import '../support/webview_fake.dart';

/// Der Sitekey, den der Test setzt (ein öffentlicher Schlüssel).
const String _sitekey = '0x4AAAAAAFDhMgIL_nrpUokM';

void main() {
  late FakeWebViewPlattform webview;

  setUp(() {
    webview = FakeWebViewPlattform();
    // DAS CAPTCHA EIN: Ohne Sitekey ist es abgeschaltet - der Weg wäre
    // nicht zu betreten. (Die App lädt die Werte aus der .env; der
    // Test setzt sie direkt in den Speicher der Umgebung.)
    dotenv.loadFromString(envString: 'CAPTCHA_SITEKEY=$_sitekey');
  });

  tearDown(() {
    // Das CAPTCHA wieder aus: sonst laufen die anderen Tests der Datei
    // mit aktiviertem CAPTCHA.
    dotenv.clean();
  });

  /// Baut eine einfache Seite, die den Sicherheitscheck aufruft.
  Future<String?> zeigeChallenge(
    WidgetTester tester, {
    bool abbrechen = false,
    double schriftGroesse = 0.5,
  }) async {
    String? ergebnis;
    await tester.pumpWidget(
      MediaQuery(
        // DIE SCHRIFTGRÖSSE (50 %): Der Test-Font ist übertrieben
        // (jeder Buchstabe ein Quadrat) - mit der echten Schrift passt
        // der Fehlertext ohne Scrollen. Für den Fall "riesige
        // Systemschrift" gibt es einen eigenen Test unten.
        data: MediaQueryData(textScaler: TextScaler.linear(schriftGroesse)),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  ergebnis = await showCaptchaChallenge(context);
                  if (!abbrechen) return;
                },
                child: const Text('Sicherheitscheck starten'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sicherheitscheck starten'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return ergebnis;
  }

  group('Der Sicherheitscheck', () {
    testWidgets('ohne aktiviertes CAPTCHA gibt es kein Fenster', (
      tester,
    ) async {
      dotenv.clean();

      await zeigeChallenge(tester);

      expect(find.text('Sicherheitscheck starten'), findsOneWidget);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'Ohne Sitekey gibt es keinen Sicherheitscheck - die App laeuft '
            'ohne Bot-Schutz (und meldet das dem Server nicht).',
      );
    });

    testWidgets('das Fenster laedt die Turnstile-Seite', (tester) async {
      await zeigeChallenge(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('auth.captcha')),
        findsOneWidget,
        reason: 'Der Dialog muss benennen, was er ist.',
      );
      expect(
        webview.geladeneAdresse.toString(),
        'https://auth.thestia.de/',
        reason:
            'Das Turnstile prueft den Hostnamen der Seite - die Seite muss '
            'also genau dort geladen werden (nicht als HTML-String).',
      );
    });

    testWidgets('ein Token schliesst das Fenster', (tester) async {
      String? ergebnis;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    ergebnis = await showCaptchaChallenge(context);
                  },
                  child: const Text('Sicherheitscheck starten'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sicherheitscheck starten'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // DIE SEITE MELDET EIN TOKEN (so, wie es die echte Turnstile-Seite
      // über den JavaScript-Bridge tut).
      webview.sendeAusDerSeite('1.lAbV5RcI1e_abcdef.0123456789');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        ergebnis,
        '1.lAbV5RcI1e_abcdef.0123456789',
        reason:
            'Das Token muss beim Aufrufer ankommen - er gibt es an den '
            'Server weiter.',
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('ein unplausibles Token wird verworfen', (tester) async {
      await zeigeChallenge(tester);

      // EINE MANIPULIERTE SEITE: Sie meldet etwas, das kein
      // Turnstile-Token ist. Die App darf es nicht durchreichen.
      webview.sendeAusDerSeite('nur-ein-String');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'Der Dialog bleibt offen - es gab kein brauchbares Token.',
      );
      expect(
        find.textContaining('invalid-token'),
        findsOneWidget,
        reason:
            'Der Nutzer muss sehen, dass es nicht geklappt hat - sonst '
            'wartet er ewig auf eine Antwort, die nicht kommt.',
      );
    });

    testWidgets('bei riesiger Systemschrift bleibt der Dialog benutzbar', (
      tester,
    ) async {
      // DIE GROSSE SYSTEMSCHRIFT (300 %): Die App erlaubt bis 3,2x. Der
      // Dialog hat eine feste Höhe (200 Pixel) - der Fehlertext passte
      // dort nicht hinein und lief über. Das hat den Dialog unbrauchbar
      // gemacht: der Nutzer konnte weder die Meldung lesen noch auf
      // "Erneut versuchen" tippen.
      await zeigeChallenge(tester, schriftGroesse: 3.0);

      webview.sendeAusDerSeite('ERROR:CAPTCHA_ERROR:110200');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Der Dialog darf bei grosser Schrift nicht ueberlaufen - sonst '
            'ist er fuer genau die Nutzer unbrauchbar, die ihn am '
            'meisten brauchen.',
      );
      expect(
        find.text(L10n.tWithoutContext('captcha.retry')),
        findsOneWidget,
        reason:
            'Der Knopf "Erneut versuchen" muss erreichbar bleiben - sonst '
            'kann der Nutzer den Fehler nicht beheben.',
      );
      expect(
        find.textContaining('110200'),
        findsOneWidget,
        reason: 'Der Fehlercode muss sichtbar bleiben.',
      );
    });

    testWidgets('der Fehler der Seite wird mit Erklaerung gezeigt', (
      tester,
    ) async {
      await zeigeChallenge(tester);

      // CLOUDFLARE MELDET: "Die Domain ist nicht freigeschaltet".
      webview.sendeAusDerSeite('ERROR:CAPTCHA_ERROR:110200');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('110200'),
        findsOneWidget,
        reason:
            'Der Code muss sichtbar bleiben - ohne ihn ist der Fehler '
            'nicht zuzuordnen.',
      );
      expect(
        find.textContaining(
          L10n.tWithoutContext('captcha.err.domainNotAuthorized'),
        ),
        findsOneWidget,
        reason: 'Der Code braucht eine Erklaerung in Klartext.',
      );
      expect(
        find.text(L10n.tWithoutContext('captcha.retry')),
        findsOneWidget,
        reason: 'Der Nutzer muss es noch einmal versuchen koennen.',
      );
    });

    testWidgets('die bekannten Fehlercodes werden uebersetzt', (tester) async {
      const codes = <String, String>{
        '110100': 'captcha.err.badSitekey',
        '110110': 'captcha.err.badSitekey',
        '400020': 'captcha.err.badSitekey',
        '200500': 'captcha.err.blocked',
        '300000': 'captcha.err.botDetected',
        '600000': 'captcha.err.botDetected',
        '200100': 'captcha.err.clock',
        '110600': 'captcha.err.timeout',
      };

      for (final eintrag in codes.entries) {
        await zeigeChallenge(tester);
        webview.sendeAusDerSeite('ERROR:CAPTCHA_ERROR:${eintrag.key}');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.textContaining(L10n.tWithoutContext(eintrag.value)),
          findsOneWidget,
          reason:
              'Der Code ${eintrag.key} braucht die Erklaerung '
              '"${eintrag.value}" - sonst weiss der Nutzer nicht, was er '
              'tun soll.',
        );
        // Der Dialog wird für den nächsten Fall geschlossen.
        await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
    });

    testWidgets('nur die erlaubten Adressen werden geladen', (tester) async {
      await zeigeChallenge(tester);

      // DIE ERLAUBTEN: die Seite selbst und die Turnstile-Dateien.
      expect(
        await webview.frageNavigation('https://auth.thestia.de/'),
        NavigationDecision.navigate,
      );
      expect(
        await webview.frageNavigation(
          'https://challenges.cloudflare.com/turnstile/v0/api.js',
        ),
        NavigationDecision.navigate,
      );
      expect(
        await webview.frageNavigation(
          'https://challenges.cloudflare.com/turnstile/v0/extra.js',
        ),
        NavigationDecision.navigate,
      );

      // ALLES ANDERE: Eine manipulierte Seite darf nicht geladen werden.
      expect(
        await webview.frageNavigation('https://evil.example.com/'),
        NavigationDecision.prevent,
        reason:
            'Nur der Sicherheitscheck und seine Dateien duerfen geladen '
            'werden - sonst koennte eine fremde Seite das Token abfangen.',
      );
      expect(
        await webview.frageNavigation('https://auth.thestia.de.evil.com/'),
        NavigationDecision.prevent,
        reason:
            'Der Vergleich muss host-genau sein - sonst passt eine Domain '
            'mit dem Namen am Ende.',
      );
    });

    testWidgets('"Erneut versuchen" laedt die Seite neu', (tester) async {
      await zeigeChallenge(tester);

      webview.sendeAusDerSeite('ERROR:CAPTCHA_ERROR:110200');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text(L10n.tWithoutContext('captcha.retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        webview.neuGeladen,
        1,
        reason: 'Die Seite muss neu geladen werden.',
      );
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'Der Dialog bleibt offen - der Nutzer versucht es noch einmal.',
      );
    });

    testWidgets('"Abbrechen" schliesst das Fenster ohne Token', (tester) async {
      await zeigeChallenge(tester);

      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
