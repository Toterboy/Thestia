// Der Zufallschat (bisher kaum getestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/swipe/random_chat_screen.dart 399 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * ohne Server kommt die Meldung "nicht verfügbar" - nicht ein
//     endloses Warten,
//   * der Suchzustand steht da ("Suche nach einer Person"),
//   * gibt es keinen Partner, steht das da - der Nutzer soll nicht
//     ewig auf einen Bildschirm starren.
//
// OHNE SERVER: Der Zufallschat-Dienst ist ein Hand-Fake. Es geht KEINE
// Anfrage raus.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/random_chat_session.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/swipe/random_chat_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/random_chat_service.dart';

import 'support/plugin_mocks.dart';

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

/// Hand-Fake des Zufallschat-Dienstes.
///
/// Der echte Dienst spricht mit der Datenbank (RPCs). Der Fake antwortet
/// aus dem RAM und zaehlt die Aufrufe - so wird sichtbar, ob die App
/// wirklich sucht oder nur so tut.
class _FakeRandomChatService extends RandomChatService {
  _FakeRandomChatService(super.client);

  /// Die Session, die [join] liefert (null = kein Partner).
  RandomChatSession? session;

  /// Wie oft [join] aufgerufen wurde.
  int joinAufrufe = 0;

  /// Die Session, die [getSession] liefert.
  RandomChatSession? befragteSession;

  @override
  Future<RandomChatSession?> join() async {
    joinAufrufe++;
    return session;
  }

  @override
  Future<RandomChatSession?> getSession(String sessionId) async {
    return befragteSession;
  }

  @override
  Future<void> leave(String sessionId) async {}
}

void main() {
  /// Der Client, den der Fake braucht.
  ///
  /// WICHTIG: `autoRefreshToken: false` - sonst laeuft ein periodischer
  /// Timer (alle 10 s), an dem der Test am Ende scheitern wuerde
  /// ("A Timer is still pending").
  late supabase.SupabaseClient client;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
    client = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const supabase.AuthClientOptions(autoRefreshToken: false),
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Baut den Zufallschat.
  ///
  /// [dienst] ist null, wenn es keinen Dienst gibt (offline).
  Future<void> zeigeScreen(
    WidgetTester tester, {
    RandomChatService? dienst,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: _startRoute,
      routes: [
        GoRoute(
          path: _startRoute,
          builder: (context, state) => const RandomChatScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          if (dienst != null)
            randomChatServiceProvider.overrideWithValue(dienst),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  group('Der Zufallschat', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      final dienst = _FakeRandomChatService(client);
      dienst.session = const RandomChatSession(sessionId: 's-1');
      await zeigeScreen(tester, dienst: dienst);

      expect(tester.takeException(), isNull);
      expect(find.byType(RandomChatScreen), findsOneWidget);
    });

    testWidgets('ohne Dienst kommt der Hinweis statt Warten', (tester) async {
      // Kein Dienst (die App ist offline) - der Screen sagt das.
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.errorOffline')),
        findsOneWidget,
        reason:
            'Ohne Dienst darf der Nutzer nicht endlos auf einen Partner '
            'warten - er muss wissen, dass es gerade nicht geht.',
      );
    });

    testWidgets('der Suchzustand steht da', (tester) async {
      final dienst = _FakeRandomChatService(client);
      // Eine wartende Session: der Partner ist noch nicht da.
      dienst.session = const RandomChatSession(sessionId: 's-1');
      await zeigeScreen(tester, dienst: dienst);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.searching')),
        findsOneWidget,
      );
      // Und der Dienst wurde wirklich gefragt.
      expect(dienst.joinAufrufe, greaterThan(0));
    });

    testWidgets('gibt es keinen Partner, steht das da', (tester) async {
      final dienst = _FakeRandomChatService(client);
      // Der Dienst liefert nichts - auch beim zweiten Versuch nicht.
      dienst.session = null;
      await zeigeScreen(tester, dienst: dienst);

      // Die App versucht es zweimal (mit 1,5 s Pause dazwischen).
      await tester.pump(const Duration(milliseconds: 2000));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(dienst.joinAufrufe, 2);
      expect(
        find.text(L10n.tWithoutContext('random.errorNoPartner')),
        findsOneWidget,
      );
    });
  });
}

/// Die Route, auf der der Screen in diesem Test liegt.
const String _startRoute = '/zufallschat';
