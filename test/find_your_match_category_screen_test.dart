// "Find your Spark" nach Interessens-Kategorie - bisher ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/swipe/find_your_match_category_screen.dart 119 offene Zeilen
// bei 120 Zeilen gesamt - der Bildschirm, ueber den man jemanden nach
// einem Interesse kennenlernt, war komplett ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Kategorien kommen vom Server (mit ihren Zahlen),
//   * die Kandidaten der gewaehlten Kategorie werden gezeigt,
//   * der Like geht an den Server und der Nutzer bekommt eine Rueckmeldung,
//   * eine leere Kategorie ist keine Sackgasse (die App sagt, wo es
//     Menschen gibt).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/screens/swipe/find_your_match_category_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

/// Der Speicher im RAM.
class _Speicher implements LocalStorage {
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
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);

  @override
  Future<void> remove(String key) async => _daten.remove(key);
}

/// Der Keystore ohne Plugin.
class _Keystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {
    // Der Test speichert kein Profil im Keystore.
  }

  @override
  Future<void> delete() async {
    // Der Test loescht kein Profil im Keystore.
  }
}

void main() {
  /// Der Ersatz-Server (die Kategorien und Kandidaten kommen von dort).
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

  /// Baut den Bildschirm.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(_Speicher(), _Keystore());
            notifier.setProfile(
              const UserProfile(id: 'ich', name: 'Lena', bio: ''),
            );
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const FindYourMatchCategoryScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Wartet, bis der Server geantwortet hat.
  Future<void> warteAufServer(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Find your Spark nach Kategorie', () {
    testWidgets('die Kategorien kommen vom Server', (tester) async {
      server.rpcAntworten['get_find_match_categories'] = <dynamic>[
        <String, dynamic>{'category': 'Musik', 'cnt': 3},
        <String, dynamic>{'category': 'Gaming', 'cnt': 0},
      ];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Musik (3)'), findsOneWidget);
      expect(find.text('Gaming (0)'), findsOneWidget);
      // Die RPC ist mit der Altersspanne aufgerufen worden.
      final aufruf = server.rpcAufrufe.firstWhere(
        (c) => c['funktion'] == 'get_find_match_categories',
      );
      expect(aufruf['p_age_min'], isNotNull);
      expect(aufruf['p_age_max'], isNotNull);
    });

    testWidgets('die Kandidaten werden gezeigt', (tester) async {
      server.rpcAntworten['get_find_match_categories'] = <dynamic>[
        <String, dynamic>{'category': 'Musik', 'cnt': 1},
      ];
      server.rpcAntworten['get_find_match_by_category'] = <dynamic>[
        <String, dynamic>{
          'user_id': 'partner-1',
          'name': 'Mira',
          'age': 28,
          'intro_text': 'Liest gern',
          'interests': <String>['wandern'],
        },
      ];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Mira'), findsWidgets);
      expect(find.text('Liest gern'), findsOneWidget);
      expect(find.text('wandern'), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('fymb.like')), findsOneWidget);
    });

    testWidgets('der Like geht an den Server', (tester) async {
      server.rpcAntworten['get_find_match_categories'] = <dynamic>[
        <String, dynamic>{'category': 'Musik', 'cnt': 1},
      ];
      server.rpcAntworten['get_find_match_by_category'] = <dynamic>[
        <String, dynamic>{
          'user_id': 'partner-1',
          'name': 'Mira',
          'age': 28,
          'intro_text': 'Liest gern',
        },
      ];
      server.rpcAntworten['like_user'] = <String, dynamic>{'is_match': true};

      await zeigeScreen(tester);
      await warteAufServer(tester);

      await tester.tap(find.text(L10n.tWithoutContext('fymb.like')));
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        server.rpcAufrufe.any((c) => c['funktion'] == 'like_user'),
        isTrue,
        reason:
            'Der Like muss beim Server ankommen - sonst entsteht kein '
            'Funke.',
      );
      // Und der Nutzer bekommt eine Rueckmeldung.
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('eine leere Kategorie nennt die anderen', (tester) async {
      server.rpcAntworten['get_find_match_categories'] = <dynamic>[
        <String, dynamic>{'category': 'Musik', 'cnt': 0},
        <String, dynamic>{'category': 'Gaming', 'cnt': 4},
      ];
      server.rpcAntworten['get_find_match_by_category'] = <dynamic>[];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      // Der Nutzer steht nicht vor einer Sackgasse - die App sagt, wo es
      // Menschen gibt.
      expect(
        find.textContaining('Gaming (4)'),
        findsWidgets,
        reason:
            'In einer leeren Kategorie muss die App sagen, in welcher '
            'anderen es Menschen gibt.',
      );
    });

    testWidgets('ohne Menschen wird das ehrlich gesagt', (tester) async {
      server.rpcAntworten['get_find_match_categories'] = <dynamic>[
        <String, dynamic>{'category': 'Musik', 'cnt': 0},
      ];
      server.rpcAntworten['get_find_match_by_category'] = <dynamic>[];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('fymb.emptyNoOne')),
        findsOneWidget,
      );
    });

    testWidgets('ohne Kategorien steht das da', (tester) async {
      server.rpcAntworten['get_find_match_categories'] = <dynamic>[];

      await zeigeScreen(tester);
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('fymb.noCategories')),
        findsOneWidget,
      );
    });
  });
}
