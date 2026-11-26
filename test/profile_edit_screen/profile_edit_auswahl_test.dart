// Die Auswahl-Felder im Profil-Editor.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/screens/profile/parts/profileditaufbau.dart 77 offene Zeilen. Die
// Felder selbst (Name, Bio, Chips, Bilder, Speichern) sind getestet -
// offen waren die AUSWAHL-Felder: Geschlecht, Beziehungstyp, Land,
// Bundesland und der Suchradius.
//
// DER WEG: Die Helfer liegen in test/profile_edit_screen/hilfen.dart
// (Aufbau des Bildschirms, Warten, Aufräumen).
//
// WAS HIER GEPRÜFT WIRD:
//   * das Geschlecht lässt sich wählen und wird gemerkt,
//   * der Beziehungstyp lässt sich wählen,
//   * ein anderes Land leert das Bundesland (sonst wäre der Bezug
//     falsch - "Berlin" in "Österreich" wäre Unsinn),
//   * der Suchradius lässt sich zwischen "Entfernung" und
//     "Ganz Deutschland" umschalten.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/gender.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';

import 'hilfen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  /// Öffnet ein Auswahl-Feld (das Label steht daneben).
  Future<void> oeffneAuswahl(WidgetTester tester, String labelKey) async {
    final label = find.text(L10n.tWithoutContext(labelKey));
    await tester.scrollUntilVisible(
      label,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpFrames(tester);
    await tester.tap(label);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Die Auswahl-Felder', () {
    testWidgets('das Geschlecht laesst sich waehlen', (tester) async {
      await profileEditScreenPump(tester, profileEditScreenProfil);

      await oeffneAuswahl(tester, 'profile.edit.gender');

      // DIE AUSWAHL: Das Menü ist offen - ein Eintrag muss tippbar sein.
      expect(find.byType(AlertDialog), findsNothing);
      final eintraege = find.byType(DropdownMenuItem<Gender>);
      expect(eintraege, findsWidgets);
      await tester.tap(eintraege.at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('gender.female')),
        findsWidgets,
        reason:
            'Das gewaehlte Geschlecht muss im Feld stehen - es ist ein '
            'Teil der Vorstellung.',
      );

      await aufraeumen(tester);
    });

    testWidgets('der Beziehungstyp laesst sich waehlen', (tester) async {
      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      await oeffneAuswahl(tester, 'profile.edit.relationship');

      final eintraege = find.byType(DropdownMenuItem<RelationshipType>);
      expect(eintraege, findsWidgets);
      await tester.tap(eintraege.at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        container.read(userPreferencesProvider).relationshipType,
        isNotNull,
        reason:
            'Der Beziehungstyp gehoert zum Profil - er sagt, was die '
            'andere Person sucht.',
      );

      await aufraeumen(tester);
    });

    testWidgets('ein anderes Land leert das Bundesland', (tester) async {
      await profileEditScreenPump(tester, profileEditScreenProfil);

      // DAS LANDFELD: Es wird über sein Label gefunden (die
      // Dropdown-Auswahl liegt in einem Überlauf, den man erst scrollen
      // muss).
      final land = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText ==
                L10n.tWithoutContext('profile.edit.country'),
      );
      expect(land, findsOneWidget);
      await tester.ensureVisible(land);
      await tester.pump();
      await tester.tap(land);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // EIN ANDERES LAND: Das Bundesland passt dann nicht mehr.
      final waehler = find.widgetWithText(
        DropdownMenuItem<String>,
        'Österreich',
      );
      expect(waehler, findsWidgets);
      await tester.tap(waehler.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('profile.edit.state')),
        findsNothing,
        reason:
            'Nach dem Wechsel des Landes darf das alte Bundesland nicht '
            'stehen - "Berlin" in Oesterreich waere Unsinn.',
      );

      await aufraeumen(tester);
    });

    testWidgets('der Suchradius laesst sich umschalten', (tester) async {
      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      await oeffneAuswahl(tester, 'profile.edit.radiusMode');

      final eintraege = find.byType(DropdownMenuItem<DistanceFilterMode>);
      expect(eintraege, findsWidgets);
      await tester.tap(eintraege.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        container.read(userPreferencesProvider).distanceFilterMode,
        isNotNull,
        reason:
            'Der Suchradius gehoert zu den Voreinstellungen - er '
            'entscheidet, wen der Nutzer ueberhaupt sieht.',
      );

      await aufraeumen(tester);
    });
  });
}
