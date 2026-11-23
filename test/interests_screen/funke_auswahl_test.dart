// Die Funken-Liste: Auswaehlen, ausblenden, leerer Zustand.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/interests/parts/matchestabstate.dart 88 offene Zeilen bei
// 81 % Abdeckung. Gerade der Auswahl-Modus (NUTZERWUNSCH "Verwalten")
// war ungetestet - und dort kann der Nutzer Funken ausblenden.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne Funke steht der Leerzustand da,
//   * der Auswahl-Modus laesst sich starten und abbrechen,
//   * ein ausgewaehlter Funke laesst sich ausblenden (der Server wird
//     gefragt, der Nutzer bekommt die Zahl),
//   * ein Fehler beim Ausblenden wird gemeldet (nicht verschluckt).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/screens/interests/interessen_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.pfade.clear();
    server.rpcAufrufe.clear();
    server.rpcFehler.clear();
  });

  /// Startet den Auswahl-Modus (der Stift in der Kopfzeile).
  Future<void> waehleAus(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await pumpFrames(tester);
  }

  group('Die Funken-Liste', () {
    testWidgets('ohne Funke steht der Leerzustand da', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = <MatchWithState>[];
      await interessenScreenPump(tester, service: service);

      expect(
        find.text(L10n.tWithoutContext('interests.emptySparksTitle')),
        findsOneWidget,
        reason:
            'Ohne Funke muss der Nutzer sehen, dass es keine gibt - eine '
            'leere Liste sieht wie ein Fehler aus.',
      );
    });

    testWidgets('der Auswahl-Modus laesst sich starten und abbrechen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      await waehleAus(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InteressenScreen)),
      );
      expect(
        container.read(matchSelectModeProvider),
        isTrue,
        reason: 'Der Auswahl-Modus muss angehen - sonst passiert nichts.',
      );
      expect(find.byType(CheckboxListTile), findsWidgets);

      // ABBRECHEN: Der Modus endet, die Auswahl ist leer.
      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await pumpFrames(tester);

      expect(container.read(matchSelectModeProvider), isFalse);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('auf einem schmalen Bildschirm wird nichts abgeschnitten', (
      tester,
    ) async {
      // BEFUND (23.11.2026): Die beiden Knöpfe des Auswahl-Modus passten
      // nebeneinander nicht in einen 390-px-Bildschirm - der
      // "Ausblenden"-Knopf wurde um 118 Pixel abgeschnitten (mit
      // gelb-schwarzen Streifen).
      await tester.binding.setSurfaceSize(const Size(360, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      await waehleAus(tester);
      await tester.tap(find.byType(CheckboxListTile));
      await pumpFrames(tester);

      // DER TEST: Ein Render-Overflow wird im Test als Ausnahme gemeldet.
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Auf einem schmalen Bildschirm darf kein Knopf abgeschnitten '
            'werden - der Nutzer kann den "Ausblenden"-Knopf sonst nicht '
            'vollstaendig treffen.',
      );
    });

    testWidgets('ein ausgewaehlter Funke laesst sich ausblenden', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [funke()];
      await interessenScreenPump(tester, service: service);

      await waehleAus(tester);

      // DEN FUNKEN ANWAEHLEN: Das Kästchen in der Zeile.
      await tester.tap(find.byType(CheckboxListTile));
      await pumpFrames(tester);

      // DER KNOPF: Er nennt die Anzahl und ist jetzt aktiv.
      final knopf = find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('interests.hideSelected').replaceAll('{n}', '1'),
      );
      expect(knopf, findsOneWidget);
      await tester.tap(knopf);
      await pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(tester.takeException(), isNull);
      expect(
        service.ausgeblendet,
        contains(7),
        reason:
            'Der Funke muss beim Server ausgeblendet werden - sonst steht er '
            'nach dem Neuladen wieder da.',
      );
      expect(
        find.textContaining('1'),
        findsWidgets,
        reason: 'Der Nutzer muss sehen, dass ein Funke ausgeblendet wurde.',
      );
    });

    testWidgets('ein Fehler beim Ausblenden wird gemeldet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [funke()];
      // DER SERVER LEHNT AB: Der Funke bleibt.
      service.hideFehler = StateError('Server kaputt');
      await interessenScreenPump(tester, service: service);

      await waehleAus(tester);
      await tester.tap(find.byType(CheckboxListTile));
      await pumpFrames(tester);

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('interests.hideSelected').replaceAll('{n}', '1'),
        ),
      );
      await pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(
        find.textContaining(
          L10n.tWithoutContext('interests.hideFailed').split('{').first,
        ),
        findsWidgets,
        reason:
            'Der Nutzer muss erfahren, dass der Funke NICHT ausgeblendet '
            'wurde - sonst glaubt er, er sei weg.',
      );
    });
  });
}
