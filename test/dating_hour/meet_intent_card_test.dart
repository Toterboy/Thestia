// Die Treffen-Vorschlags-Karte im Chat - bisher kaum getestet (9,2 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/profile/meet_intent_card.dart 89 offene Zeilen bei 98 Zeilen
// gesamt. Die Karte ist das, was aus einem Funke ein echtes Treffen
// machen soll - und sie hat fünf Zustände.
//
// WAS HIER GEPRÜFT WIRD:
//   * ein zu frischer Funke zeigt gar nichts (das stört nur),
//   * noch niemand will -> der sanfte Vorschlag,
//   * der Partner will -> die Zustimmungs-Frage,
//   * ich will, der Partner noch nicht -> der Warte-Hinweis,
//   * beide wollen -> die Planungskarte mit den Date-Ideen,
//   * "Später" blendet die Karte aus (nur für diese Sitzung).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/widgets/profile/meet_intent_card.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM (die Karte liest die Einstellungen daraus).
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

void main() {
  /// Der Ersatz-Server (der Stand kommt von dort).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();

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
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
  });

  /// Baut die Karte.
  Future<void> zeigeKarte(
    WidgetTester tester, {
    String matchId = '7',
    Map<String, dynamic>? stand,
  }) async {
    // DER TESTRAHMEN: 600 px breit. Die Testschrift (Ahem) ist rund
    // 1,7-mal breiter als Roboto - die beiden Knopfe der Karte laufen
    // sonst über den Rand. Mit der echten Schrift passt es (der
    // Bildschirm wird in der App nie breiter als ~420 px).
    await tester.binding.setSurfaceSize(const Size(600, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    if (stand != null) {
      server.rpcAntworten['get_meet_intent'] = stand;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // DER SPEICHER: Die Karte liest die Einstellungen (der
          // Ruhemodus nach dem Treffen).
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: MeetIntentCard(matchId: matchId, partnerName: 'Mira'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Die Treffen-Karte', () {
    testWidgets('ein zu frischer Funke zeigt gar nichts', (tester) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': false,
          'myWants': false,
          'partnerWants': false,
          'metConfirmed': false,
        },
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(MeetIntentCard), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('meet.suggestTitle')),
        findsNothing,
        reason:
            'Ein zu frischer Funke darf den Nutzer nicht stoeren - die '
            'Karte kommt erst nach 14 Tagen.',
      );
    });

    testWidgets('ein lokaler Kontakt zeigt gar nichts', (tester) async {
      // Lokale Kontakte (QR) haben keine DB-Match-ID.
      await zeigeKarte(tester, matchId: 'lokal-1');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('meet.suggestTitle')),
        findsNothing,
      );
    });

    testWidgets('noch niemand will -> der sanfte Vorschlag', (tester) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': true,
          'myWants': false,
          'partnerWants': false,
          'metConfirmed': false,
        },
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('meet.suggestTitle')),
        findsOneWidget,
      );
      expect(find.text(L10n.tWithoutContext('meet.yesWant')), findsOneWidget);
    });

    testWidgets('"Spaeter" blendet die Karte aus', (tester) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': true,
          'myWants': false,
          'partnerWants': false,
          'metConfirmed': false,
        },
      );

      await tester.tap(find.text(L10n.tWithoutContext('meet.later')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('meet.suggestTitle')),
        findsNothing,
        reason: '"Spaeter" soll die Karte nur fuer diese Sitzung ausblenden.',
      );
    });

    testWidgets('der Partner will -> die Zustimmungs-Frage', (tester) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': true,
          'myWants': false,
          'partnerWants': true,
          'metConfirmed': false,
        },
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Mira'),
        findsWidgets,
        reason: 'Die Frage nennt den Namen des Partners.',
      );
      expect(find.text(L10n.tWithoutContext('meet.yesGlad')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('meet.noThanks')), findsOneWidget);
    });

    testWidgets('ich will, der Partner noch nicht -> der Warte-Hinweis', (
      tester,
    ) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': true,
          'myWants': true,
          'partnerWants': false,
          'metConfirmed': false,
        },
      );

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('meet.youWant')), findsOneWidget);
    });

    testWidgets('beide wollen -> die Planungskarte', (tester) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': true,
          'myWants': true,
          'partnerWants': true,
          'metConfirmed': false,
        },
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('meet.planningTitle')),
        findsOneWidget,
      );
      // Die Date-Ideen stehen zur Auswahl.
      expect(find.text(L10n.tWithoutContext('meet.idea.1')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('meet.idea.5')), findsOneWidget);
      // Und der Treffen-Bestätigungsknopf.
      expect(find.text(L10n.tWithoutContext('meet.metBtn')), findsOneWidget);
    });

    testWidgets('das Treffen bestaetigt -> die Erfolgsmeldung', (tester) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': true,
          'myWants': true,
          'partnerWants': true,
          'metConfirmed': true,
        },
      );

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('meet.metTitle')), findsOneWidget);
    });

    // DER RUHEMODUS (Plan 0.11.0, "Begegnung statt Bildschirm"): Nach
    // dem Treffen kann der Nutzer die App bis zum Morgen stumm schalten.
    testWidgets('nach dem Treffen kann die App stumm schalten', (tester) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': true,
          'myWants': true,
          'partnerWants': true,
          'metConfirmed': true,
        },
      );

      expect(tester.takeException(), isNull);
      final knopf = find.text(L10n.tWithoutContext('meet.ruheBtn'));
      expect(
        knopf,
        findsOneWidget,
        reason:
            'Nach dem bestaetigten Treffen muss der Knopf kommen - '
            '"Geniesst die Zeit, Thestia schweigt bis morgen".',
      );

      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Ruhemodus ist an - der Knopf bietet jetzt das Beenden an.
      expect(
        find.text(L10n.tWithoutContext('meet.ruheEndBtn')),
        findsOneWidget,
      );
    });

    testWidgets('der Ruhemodus laesst sich wieder beenden', (tester) async {
      await zeigeKarte(
        tester,
        stand: <String, dynamic>{
          'matchId': 7,
          'eligible': true,
          'myWants': true,
          'partnerWants': true,
          'metConfirmed': true,
        },
      );

      await tester.tap(find.text(L10n.tWithoutContext('meet.ruheBtn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text(L10n.tWithoutContext('meet.ruheEndBtn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('meet.ruheBtn')),
        findsOneWidget,
        reason: 'Nach dem Beenden kommt der Knopf zum Einschalten zurueck.',
      );
    });
  });
}
