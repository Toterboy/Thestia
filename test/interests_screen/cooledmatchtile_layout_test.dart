// Die Kachel der „Erschlossenen Funken" (mit dem Re-Funke-Knopf).
//
// ANLASS (27.11.2026): Der Betreiber meldete: "Beim Interessen Screen
// noch immer der Bug mit, wenn Profil und daneben Button mit Re-Funke:
// Die Schrift links vom Button ist einzeln jeder Buchstabe untereinander."
//
// DIE URSACHE: Alle drei Aktionen standen in der `trailing`-Leiste einer
// ListTile. Die Leiste braucht rund 250 Pixel - auf einem kleinen
// Telefon blieb für den Text nur eine Zeichenbreite übrig, und Flutter
// brach ihn deshalb Buchstabe für Buchstabe um.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Text bekommt eine lesbare Breite (kein Buchstabenstapel),
//   * der Text bricht über zwei oder drei Zeilen um, nicht über zehn,
//   * alle Aktionen stehen noch da (Profil, Re-Funke, Löschen),
//   * der Re-Funke-Knopf ruft weiterhin die RPC.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/find_match_models.dart';
import 'package:thestia/models/profile/user_profile.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

/// Der lange Text der Kachel (der Umbruch muss greifen).
const String kBio =
    'Ich gehe gern wandern, lese viel und koche am liebsten mit '
    'Freunden. Am Wochenende bin ich meistens unterwegs.';

/// Ein gekühlter Funke mit einem langen Text (der Umbruch muss greifen).
MatchWithState funkeMitLangemText() {
  return MatchWithState(
    matchId: 42,
    partner: UserProfile(
      id: 'p9',
      name: 'Mara',
      bio: kBio,
      birthDate: DateTime(DateTime.now().year - 30, 5, 4),
    ),
    unlockLevel: 2,
    failedAttempts: 0,
    createdVia: 'swipe',
    status: 'cooled',
    createdAt: DateTime.now(),
  );
}

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
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.pfade.clear();
    server.rpcAufrufe.clear();
  });

  /// Der Screen auf einem kleinen Telefon (der Fall aus der Meldung).
  Future<FakeFindYourMatchService> baue(
    WidgetTester tester, {
    List<MatchWithState> funken = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = FakeFindYourMatchService(supabase.Supabase.instance.client)
      ..funken = funken;
    await interessenScreenPump(tester, service: service);
    return service;
  }

  group('Der Text neben dem Re-Funke-Knopf', () {
    testWidgets('bekommt eine lesbare Breite', (tester) async {
      await baue(tester, funken: [funkeMitLangemText()]);

      final text = find.textContaining('Ich gehe gern wandern');
      expect(text, findsOneWidget, reason: 'Der Text muss stehen.');

      final breite = tester.getSize(text).width;
      expect(
        breite,
        greaterThan(100),
        reason:
            'Der Text hat nur $breite Pixel - bei so wenig Platz bricht '
            'Flutter ihn Buchstabe für Buchstabe um (der Fehler vom '
            '27.11.2026).',
      );
    });

    testWidgets('bricht nicht Buchstabe für Buchstabe um', (tester) async {
      // Der kurze Text der Kachel: "Liest gern". Bei der alten Anordnung
      // (33 Pixel breit) stand jedes Wort in einer eigenen Zeile.
      await baue(tester, funken: [funke(status: 'cooled')]);

      final text = find.text('Liest gern');
      expect(text, findsOneWidget, reason: 'Der Text muss stehen.');

      final breite = tester.getSize(text).width;
      final stil = tester.widget<Text>(text).style;

      final maler = TextPainter(
        text: TextSpan(text: 'Liest gern', style: stil),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: breite);
      final zeilen = maler.computeLineMetrics().length;

      expect(
        zeilen,
        1,
        reason:
            'Der Text braucht $zeilen Zeilen bei $breite Pixeln Breite - '
            'er gehört in eine Zeile (sonst bricht ihn Flutter Buchstabe '
            'für Buchstabe um).',
      );
    });

    testWidgets('der Name und das Alter stehen da', (tester) async {
      await baue(tester, funken: [funkeMitLangemText()]);

      expect(find.text('Mara'), findsOneWidget);
      final context = tester.element(find.text('Mara'));
      final jahre = L10n.t(context, 'common.years');
      expect(
        find.textContaining(jahre),
        findsOneWidget,
        reason: 'Das Alter gehört zur Kachel.',
      );
    });
  });

  group('Die Aktionen', () {
    testWidgets('stehen alle da', (tester) async {
      await baue(tester, funken: [funkeMitLangemText()]);

      final context = tester.element(find.text('Mara'));
      final label = L10n.t(context, 'interests.resparkBtn');
      expect(
        find.text(label),
        findsOneWidget,
        reason: 'Der Re-Funke-Knopf ist der Zweck dieser Kachel.',
      );
      expect(find.byIcon(Icons.person_outline), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('der Re-Funke-Knopf ruft die RPC', (tester) async {
      final service = await baue(tester, funken: [funkeMitLangemText()]);
      final context = tester.element(find.text('Mara'));
      final label = L10n.t(context, 'interests.resparkBtn');

      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        service.wiederEntzuend,
        contains(42),
        reason: 'Der Re-Funke muss den Funke wieder entzünden.',
      );
    });
  });
}
