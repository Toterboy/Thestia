// Der Slogan der App und die Geschlechtsregel der Dating Hour.
//
// BEFUND (14.11.2026, Betreiber):
//   * "Slogan der App: Dating, das dich ins echte Leben zurückführt."
//   * "Bei Dating Hour irgendweise umsetzen, dass von beiden
//      Geschlechtern welche in dem Event sind, wenn alle Hetero."
//
// WAS HIER GEPRUEFT WIRD:
//   * der Slogan steht als Ueberschrift des Willkommens-Screens (der
//     erste Bildschirm, den ein Nutzer sieht) - in beiden Sprachen,
//   * die Regeln der Dating Hour erklaeren, wie gepaart wird,
//   * der Wartezustand sagt, worauf man wartet.
//
// DIE REGEL SELBST (Server) wird von
// tool/check_dating_hour_gender_mix.py am lebenden Server geprueft -
// hier geht es um das, was der Nutzer davon sieht.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/dating_hour/dating_hour_rules_screen.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Der Slogan', () {
    test('er steht als Ueberschrift des Willkommens-Screens', () {
      // DER WEG UEBER DIE TEXTE UND NICHT UEBER DEN BILDSCHIRM: Der
      // Willkommens-Screen zeigt seinen Inhalt erst, wenn das Logo
      // geladen ist (precacheImage) - im Test gibt es das Bild nicht,
      // der Screen bleibt also leer. Der Text wird deshalb hier
      // geprueft (und der Bildschirm in der Quelle).
      expect(
        L10n.tWithoutContext('welcome.t1'),
        'Dating, das dich ins echte Leben zurückführt.',
        reason:
            'Der Slogan ist die Ueberschrift des ersten Bildschirms - er '
            'muss dort stehen.',
      );

      final quelle = File(
        'lib/screens/welcome/welcome_screen.dart',
      ).readAsStringSync();
      expect(
        quelle.contains("'welcome.t1'"),
        isTrue,
        reason:
            'Der Willkommens-Screen muss den Slogan als Ueberschrift '
            'nehmen.',
      );
    });

    test('er steht in beiden Sprachen', () {
      // Die englische Mappe ist privat - deshalb wird die Quelle
      // gelesen (so macht es der L10n-Test des Projekts auch).
      final quelle = File('lib/l10n/app_strings.dart').readAsStringSync();
      expect(
        quelle.contains(
          "'welcome.t1': 'Dating that brings you back into real life.',",
        ),
        isTrue,
        reason:
            'Der Slogan muss auch auf Englisch stehen - die App ist '
            'zweisprachig.',
      );
    });

    test('er steht auch im Store-Eintrag', () {
      // Der Store-Eintrag ist der zweite Ort, an dem der Slogan steht
      // (die kurze Beschreibung). Ohne das waeren App und Store
      // verschiedene Apps.
      for (final sprache in ['de-DE', 'en-US']) {
        final datei = File(
          'fastlane/metadata/android/$sprache/short_description.txt',
        );
        expect(
          datei.existsSync(),
          isTrue,
          reason: 'Die kurze Beschreibung fuer $sprache fehlt.',
        );
        final text = datei.readAsStringSync();
        expect(
          text.trim(),
          startsWith('Dating'),
          reason:
              'Die kurze Beschreibung im Store ist der Slogan-Slot - sie '
              'soll mit dem Slogan beginnen ($sprache).',
        );
      }
    });
  });

  group('Die Dating-Hour-Regel', () {
    testWidgets('die Regeln erklaeren, wie gepaart wird', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: DatingHourRulesScreen())),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Die neue Regel steht in der Uebersicht (zusammengeklappt -
      // der Titel ist sichtbar, der Text wird beim Aufklappen gezeigt).
      expect(
        find.text('Wer mit wem zusammenkommt'),
        findsOneWidget,
        reason:
            'Die Regel muss in den Regeln stehen - der Nutzer soll wissen, '
            'nach wem gesucht wird.',
      );
    });

    test('der Wartezustand sagt, worauf man wartet', () {
      expect(
        L10n.tWithoutContext('dh.event.genderMixHint'),
        contains('anderen Geschlechts'),
      );
      expect(
        L10n.tWithoutContext('dh.rules.7.body'),
        contains('anderen Geschlechts'),
      );
    });
  });
}
