// Der Profil-Editor: das Zurueck und das Bundesland.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/profile/parts/profileditaufbau.dart 62 offene Zeilen -
// genau die Wege, die der Nutzer beim Verlassen des Editors geht.
//
// DER WEG: Der Bildschirm steht in einem Router (der Profil-Bildschirm
// ist das Ziel). Der Server ist der [FakeSupabaseServer].
//
// WAS HIER GEPRUEFT WIRD:
//   * "Zurueck" ohne Aenderungen geht sofort,
//   * "Zurueck" mit Aenderungen fragt nach - und "Verwerfen" geht
//     wirklich raus (der Nutzer darf nicht im Editor feststecken),
//   * der Weg "speichern und weiter" speichert und navigiert,
//   * das Bundesland wird uebernommen (es ist der Wert, nach dem der
//     Server filtert).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();

    server = FakeSupabaseServer(userId: 'ich');
    await mockPfadProvider();
    mockKeystore();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    server.schreibvorgaenge.clear();
    server.rpcAufrufe.clear();
    server.rpcAntworten.clear();
  });

  /// Tippt in das Namensfeld (das macht den Screen "veraendert").
  Future<void> nameAendern(WidgetTester tester) async {
    final feld = find.byType(TextFormField).first;
    await tester.ensureVisible(feld);
    await tester.pump();
    await tester.enterText(feld, 'Lena Marie');
    await pumpFrames(tester);
  }

  group('Das Zurueck', () {
    testWidgets('ohne Aenderungen geht es sofort', (tester) async {
      await profileEditScreenPump(tester, profileEditScreenProfil);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Mein Profil'),
        findsOneWidget,
        reason:
            'Ohne Aenderungen gibt es nichts zu fragen - der Nutzer will '
            'nur zurueck.',
      );

      await aufraeumen(tester);
    });

    testWidgets('mit Aenderungen fragt es nach', (tester) async {
      await profileEditScreenPump(tester, profileEditScreenProfil);
      await nameAendern(tester);

      // DER SYSTEM-ZURUECK: Der Geraete-Knopf oder die Geste. Der
      // Bildschirm blockiert das (sonst waeren die Aenderungen weg).
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason:
            'Der Nutzer muss gefragt werden - sonst verliert er seine '
            'Aenderungen ohne Warnung.',
      );
      expect(
        find.text(L10n.tWithoutContext('profile.edit.unsavedTitle')),
        findsOneWidget,
      );

      await aufraeumen(tester);
    });

    testWidgets('"Verwerfen" geht wirklich raus', (tester) async {
      await profileEditScreenPump(tester, profileEditScreenProfil);
      await nameAendern(tester);

      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      // VERWERFEN: Die Aenderungen weg, der Screen verlassen.
      await tester.tap(
        find.text(L10n.tWithoutContext('profile.edit.unsavedDiscard')),
      );
      await pumpFrames(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Mein Profil'),
        findsOneWidget,
        reason:
            'Nach dem Verwerfen muss der Nutzer raus - sonst sitzt er im '
            'Editor fest (das war ein gemeldeter Fehler).',
      );

      await aufraeumen(tester);
    });
  });

  group('Das Bundesland', () {
    testWidgets('der Wert des Profils steht im Feld', (tester) async {
      await profileEditScreenPump(
        tester,
        const UserProfile(
          id: 'ich',
          name: 'Lena',
          bio: 'Hallo',
          birthDate: null,
          country: 'Deutschland',
          state: 'Bayern',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('Bayern'),
        findsWidgets,
        reason:
            'Das Bundesland des Profils muss im Feld stehen - der Nutzer '
            'sieht sonst nicht, wonach der Server filtert.',
      );

      await aufraeumen(tester);
    });

    testWidgets('eine andere Auswahl wird uebernommen', (tester) async {
      await profileEditScreenPump(
        tester,
        const UserProfile(
          id: 'ich',
          name: 'Lena',
          bio: 'Hallo',
          birthDate: null,
          country: 'Deutschland',
          state: 'Bayern',
        ),
      );

      // DAS FELD: Das Bundesland-Feld des Profils (an seinem aktuellen
      // Wert erkannt - es gibt mehrere Auswahlfelder auf der Seite).
      final feld = find.ancestor(
        of: find.text('Bayern'),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      expect(feld, findsOneWidget, reason: 'Das Bundesland-Feld muss da sein.');
      await tester.scrollUntilVisible(
        feld,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 60,
      );
      await pumpFrames(tester);
      await tester.tap(feld);
      await pumpFrames(tester);

      // DIE AUSWAHL: Ein anderes Bundesland.
      expect(
        find.text('Berlin'),
        findsWidgets,
        reason: 'Berlin muss zur Wahl stehen.',
      );
      await tester.tap(find.text('Berlin').last);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Berlin'),
        findsWidgets,
        reason:
            'Die neue Auswahl muss im Feld stehen - sie ist der Wert, den '
            'der Server beim Speichern bekommt.',
      );

      await aufraeumen(tester);
    });
  });

  group('Der Weg "speichern und weiter"', () {
    testWidgets('der Bildschirm speichert und navigiert', (tester) async {
      final container = await profileEditScreenPump(
        tester,
        profileEditScreenProfil,
      );

      // DER WEG: Die Navigation setzt das Ziel - der Bildschirm
      // speichert und geht dann hin.
      container.read(profileEditNavigateAfterSaveProvider.notifier).state =
          AppRoutes.personalityTest;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text('Persönlichkeitstest'),
        findsOneWidget,
        reason:
            'Nach dem Speichern muss der Nutzer dort landen, wo er '
            'hingewollt hat - sonst verliert er den Weg.',
      );

      await aufraeumen(tester);
    });
  });
}
