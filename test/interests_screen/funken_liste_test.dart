// Die Funken-Liste: der Ladefehler, die Kachel-Aktionen und die
// gekühlten Funken.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/screens/interests/parts/matchestabstate.dart 79 offene Zeilen.
// Betroffen sind genau die Wege, die dem Betreiber im November 2026
// auffielen: der Server antwortet nicht (der Funke schien verschwunden)
// und die Aktionen an der Kachel.
//
// WAS HIER GEPRÜFT WIRD:
//   * ein fehlgeschlagener Abruf bleibt sichtbar (mit Wiederholen) -
//     der Inhalt der Liste bleibt dabei stehen (BEFUND 13.11.2026:
//     "Außerdem ist mein Funke verschwunden"),
//   * der Profil-Knopf der Kachel öffnet wirklich das Profil,
//   * ein gekühlter Funke lässt sich wieder entzüenden ("Re-Funke
//     ohne Druck") und endgültig löschen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/find_match_models.dart';

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
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.pfade.clear();
    server.rpcAufrufe.clear();
  });

  /// Der Screen auf einem Telefon.
  Future<FakeFindYourMatchService> baue(
    WidgetTester tester, {
    List<MatchWithState> funken = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = FakeFindYourMatchService(supabase.Supabase.instance.client)
      ..funken = funken;
    await interessenScreenPump(tester, service: service);
    return service;
  }

  group('Der Ladefehler', () {
    testWidgets('er bleibt sichtbar und laesst sich wiederholen', (
      tester,
    ) async {
      final service = await baue(tester, funken: [funke()]);

      expect(
        find.text('Mira, 30'),
        findsWidgets,
        reason: 'Der Funke steht da.',
      );

      // DER SERVER ANTWORJETT NICHT MEHR: Der Nutzer zieht die Liste
      // nach unten, um neu zu laden.
      service.ladeFehler = StateError('Server nicht erreichbar');
      await tester.drag(find.byType(ListView).first, const Offset(0, 300));
      await pumpFrames(tester);

      expect(
        find.text(L10n.tWithoutContext('interests.sparksLoadFailed')),
        findsOneWidget,
        reason:
            'Der Fehler muss sichtbar bleiben - sonst sieht der Nutzer eine '
            'leere Liste und glaubt, sein Funke sei weg.',
      );
      expect(
        find.text('Mira, 30'),
        findsWidgets,
        reason:
            'Die Liste bleibt stehen - der Inhalt wird nicht weggeraeumt, '
            'weil das Abrufen fehlgeschlagen ist.',
      );

      // JETZT GEHT ES WIEDER: Der Knopf "Wiederholen" lädt neu.
      service.ladeFehler = null;
      await tester.tap(find.text(L10n.tWithoutContext('common.retry')));
      await pumpFrames(tester);

      expect(
        find.text(L10n.tWithoutContext('interests.sparksLoadFailed')),
        findsNothing,
        reason:
            'Nach dem Wiederholen ist der Fehler weg - der Server antwortet '
            'wieder.',
      );
    });
  });

  group('Die Kachel', () {
    testWidgets('der Profil-Knopf oeffnet das Profil', (tester) async {
      await baue(tester, funken: [funke()]);

      await tester.tap(
        find.byTooltip(L10n.tWithoutContext('profile.detail.aboutMe')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Profil'),
        findsOneWidget,
        reason:
            'Der Knopf an der Kachel muss das Profil oeffnen - er ist der '
            'Weg zu allem, was man ueber die Person wissen will.',
      );
    });
  });

  group('Die gekuehlten Funken', () {
    testWidgets('"Re-Funke" zündet sie wieder', (tester) async {
      final service = await baue(tester, funken: [funke(status: 'cooled')]);

      // DER KNOPF LIEGT UNTEN: Die gekühlten Funken stehen am Ende der
      // Liste - ohne Heranschieben tappt der Test ins Leere.
      final knopf = find.text(L10n.tWithoutContext('interests.resparkBtn'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await pumpFrames(tester);

      expect(
        service.wiederEntzuend,
        contains(7),
        reason:
            'Der Re-Funke muss den Funke beim Server wieder entzuenden - '
            'sonst passiert auf dem Handy gar nichts.',
      );
      expect(
        find.textContaining('wieder aktiv'),
        findsOneWidget,
        reason: 'Der Nutzer muss sehen, dass es geklappt hat.',
      );
    });

    testWidgets('"Loeschen" beendet den Funken endgueltig', (tester) async {
      final service = await baue(tester, funken: [funke(status: 'cooled')]);

      final muell = find.byTooltip(
        L10n.tWithoutContext('interests.deleteSpark'),
      );
      await tester.ensureVisible(muell);
      await tester.pump();
      await tester.tap(muell);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // DIE RÜCKFRAGE: Ohne sie wäre das Löschen ein Unfall.
      expect(
        find.text(L10n.tWithoutContext('interests.deleteSparkTitle')),
        findsOneWidget,
        reason: 'Das Loeschen muss gefragt werden.',
      );

      await tester.tap(
        find.text(L10n.tWithoutContext('interests.deleteSpark')),
      );
      await pumpFrames(tester);

      expect(
        service.beendet,
        contains(7),
        reason: 'Der Funke muss beim Server beendet werden.',
      );
    });

    testWidgets('der Profil-Knopf geht auch beim gekuehlten Funke', (
      tester,
    ) async {
      await baue(tester, funken: [funke(status: 'cooled')]);

      // DER KNOPF: Die gekühlte Kachel hat ZWEI Personensymbole (das
      // Bild links und der Knopf rechts) - der Knopf ist das letzte.
      final knopf = find.byIcon(Icons.person_outline).last;
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Profil'),
        findsOneWidget,
        reason:
            'Auch bei einem gekuehlten Funke muss das Profil erreichbar '
            'sein - die Verbindung ist kalt, die Person nicht.',
      );
    });
  });
}
