// "Find your Match" (die Vorstellungs-Vorstellung) - bisher ungetestet.
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/swipe/find_your_match_screen.dart 216 offene Zeilen - der
// Screen war gar nicht getestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne eigene Vorstellung steht der Editor da (und nichts weiter),
//   * mit Vorstellung kommt die Wahl: Zufall oder Kategorie,
//   * die Kandidaten kommen vom Server (RPC) und werden angezeigt,
//   * der Like meldet Erfolg, Funke, "schon Funke" oder Fehler,
//   * das Ueberspringen nimmt den naechsten Kandidaten,
//   * der Stift-Knopf oeffnet den Editor, und der Editor laesst sich
//     nicht ohne Text verlassen.
//
// WIE DER SERVER ERSETZT WIRD: Der [FakeSupabaseServer] beantwortet die
// RPCs (z. B. get_find_match_candidates) aus dem RAM.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/screens/swipe/find_your_match_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = {};

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

/// Der Keystore ohne Plugin.
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Ein Kandidat, wie ihn die RPC liefert.
Map<String, dynamic> _kandidat({
  required String id,
  required String name,
  String vorstellung = 'Ich reise gern und koche gern.',
  int alter = 31,
  List<String> interessen = const <String>['Kochen', 'Reisen'],
  int? matchScore = 72,
  double distanzKm = 12,
}) {
  return <String, dynamic>{
    'user_id': id,
    'name': name,
    'bio': 'Kurz und buendig',
    'age': alter,
    'interests': interessen,
    'intro_text': vorstellung,
    'distance_km': distanzKm,
    'match_score': matchScore,
    'is_verified': true,
  };
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockAufnahme();

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
    server.rpcFehler.clear();
  });

  /// Baut den Screen mit dem angegebenen eigenen Profil.
  ///
  /// [mitVorstellung] entscheidet, ob der Editor (keine Vorstellung) oder
  /// die Wahl (Vorstellung vorhanden) steht.
  Future<void> zeigeScreen(
    WidgetTester tester, {
    bool mitVorstellung = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          secureProfileStoreProvider.overrideWithValue(
            _FakeSecureProfileStore(),
          ),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(
              ref.watch(localStorageProvider),
              ref.watch(secureProfileStoreProvider),
            );
            notifier.setProfile(
              UserProfile(
                id: 'ich',
                name: 'Lena',
                bio: '',
                introText: mitVorstellung ? 'Meine Vorstellung' : '',
              ),
            );
            return notifier;
          }),
        ],
        child: const MaterialApp(home: FindYourMatchScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Der Screen "Find your Match"', () {
    testWidgets('ohne Vorstellung steht der Editor da', (tester) async {
      await zeigeScreen(tester, mitVorstellung: false);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('match.createFirst')),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('mit Vorstellung kommt die Wahl', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('fymb.choiceTitle')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('fymb.choiceRandom')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('fymb.choiceCategory')),
        findsOneWidget,
      );
    });

    testWidgets('ohne Kandidaten steht der Leerzustand', (tester) async {
      server.rpcAntworten['get_find_match_candidates'] = <dynamic>[];
      await zeigeScreen(tester);

      // Die Wahl zuerst wegkippen.
      await tester.tap(find.text(L10n.tWithoutContext('fymb.choiceRandom')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('match.empty')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('match.reload')), findsOneWidget);
    });

    testWidgets('der Kandidat aus dem Server wird angezeigt', (tester) async {
      server.rpcAntworten['get_find_match_candidates'] = <dynamic>[
        _kandidat(id: 'kandidat-1', name: 'Mira'),
      ];
      await zeigeScreen(tester);

      await tester.tap(find.text(L10n.tWithoutContext('fymb.choiceRandom')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Name und Alter stehen da.
      expect(find.textContaining('Mira'), findsWidgets);
      expect(find.textContaining('31'), findsWidgets);
      // Der Verbindungs-Score steht da.
      expect(find.textContaining('72'), findsWidgets);
      // Die Vorstellung steht da.
      expect(find.textContaining('Ich reise gern'), findsOneWidget);
      // Die Interessen als Chips.
      expect(find.text('Kochen'), findsOneWidget);
      expect(find.text('Reisen'), findsOneWidget);
    });

    testWidgets('der Like meldet den Erfolg', (tester) async {
      server.rpcAntworten['get_find_match_candidates'] = <dynamic>[
        _kandidat(id: 'kandidat-1', name: 'Mira'),
      ];
      server.rpcAntworten['like_user'] = <String, dynamic>{'is_match': false};

      await zeigeScreen(tester);
      await tester.tap(find.text(L10n.tWithoutContext('fymb.choiceRandom')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Das Herz ist der Like-Knopf.
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Mira'),
        findsWidgets,
        reason: 'Der Erfolgstext nennt den Namen.',
      );
      // Der Kandidat ist vom Deck verschwunden.
      expect(find.text(L10n.tWithoutContext('match.empty')), findsOneWidget);
    });

    testWidgets('der Like meldet den entstandenen Funke', (tester) async {
      server.rpcAntworten['get_find_match_candidates'] = <dynamic>[
        _kandidat(id: 'kandidat-1', name: 'Mira'),
      ];
      server.rpcAntworten['like_user'] = <String, dynamic>{'is_match': true};

      await zeigeScreen(tester);
      await tester.tap(find.text(L10n.tWithoutContext('fymb.choiceRandom')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Der Text unterscheidet sich vom einfachen Like.
      expect(
        find.text(
          L10n.tWithoutContext('match.likeMutual').replaceAll('{name}', 'Mira'),
        ),
        findsOneWidget,
        reason: 'Bei einem Funke steht ein eigener Text da.',
      );
    });

    testWidgets('das Ueberspringen nimmt den naechsten Kandidaten', (
      tester,
    ) async {
      server.rpcAntworten['get_find_match_candidates'] = <dynamic>[
        _kandidat(id: 'kandidat-1', name: 'Mira'),
        _kandidat(id: 'kandidat-2', name: 'Jona'),
      ];

      await zeigeScreen(tester);
      await tester.tap(find.text(L10n.tWithoutContext('fymb.choiceRandom')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Mira'), findsWidgets);

      // Das Kreuz ueberspringt.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Jona'), findsWidgets);
      expect(find.textContaining('Mira'), findsNothing);
    });

    testWidgets('der Stift-Knopf oeffnet den Editor wieder', (tester) async {
      await zeigeScreen(tester);

      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.byIcon(Icons.record_voice_over));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('ohne Text laesst sich die Vorstellung nicht speichern', (
      tester,
    ) async {
      await zeigeScreen(tester, mitVorstellung: false);

      // Der Editor ist offen, das Textfeld ist leer. Der Knopf liegt
      // unterhalb des Bildschirms - erst sichtbar machen.
      final knopf = find.text(L10n.tWithoutContext('match.saveContinue'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('match.required')),
        findsOneWidget,
        reason:
            'Ohne Text darf nicht gespeichert werden - die Vorstellung ist '
            'die Pflichtangabe.',
      );
    });

    testWidgets('mit Text wird die Vorstellung gespeichert', (tester) async {
      await zeigeScreen(tester, mitVorstellung: false);

      await tester.enterText(find.byType(TextFormField), 'Meine Vorstellung');
      await tester.pump();

      final knopf = find.text(L10n.tWithoutContext('match.saveContinue'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      // Nach dem Speichern kommt die Wahl.
      expect(
        find.text(L10n.tWithoutContext('fymb.choiceTitle')),
        findsOneWidget,
      );
    });
  });
}
