// Der Zufallschat: die Suche und der Zustand (bisher wenig getestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/swipe/random_chat_screen.dart 383 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * die Suche laeuft und der Zustand wird angezeigt,
//   * ohne Gegenstelle kommt der Hinweis (kein endloses Warten).
//
// OHNE SERVER: Der Zufallschat-Dienst ist ein Hand-Fake.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/random_chat_session.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/swipe/random_chat_screen.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/random_chat_service.dart';

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

/// Hand-Fake des Zufallschat-Dienstes.
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
  Future<RandomChatSession?> getSession(String sessionId) async =>
      befragteSession;

  @override
  Future<RandomChatSession?> getMyActiveSession() async => null;

  @override
  Future<void> leave(String sessionId) async {}
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
  });

  /// Baut den Zufallschat.
  Future<_FakeRandomChatService> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeRandomChatService(
      supabase.SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const supabase.AuthClientOptions(autoRefreshToken: false),
      ),
    );

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
          randomChatServiceProvider.overrideWithValue(service),
          chatProvider.overrideWith((ref) => ChatNotifier(ChatService())),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    // 12 Frames: der Dienst wird zweimal versucht (mit 1,5 s Pause
    // dazwischen). Der zweite Versuch muss abgelaufen sein, sonst
    // meldet der Test am Ende "Timer is still pending".
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    return service;
  }

  group('Der Zufallschat', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(RandomChatScreen), findsOneWidget);
    });

    testWidgets('die App sucht einen Partner', (tester) async {
      final service = await zeigeScreen(tester);

      // Der Dienst wurde wirklich gefragt - der Screen sucht von
      // allein, ohne dass der Nutzer etwas tun muss.
      expect(service.joinAufrufe, greaterThan(0));
    });

    testWidgets('ohne Gegenstelle steht ein Hinweis da', (tester) async {
      // Der Dienst liefert nichts - der Nutzer darf nicht endlos auf
      // einen Bildschirm starren: nach dem zweiten Versuch sagt die App
      // Bescheid.
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.errorNoPartner')),
        findsOneWidget,
        reason:
            'Ohne Partner muss der Zustand erkennbar sein - der Nutzer '
            'soll wissen, dass die App nichts gefunden hat.',
      );
    });
  });
}

/// Die Route, auf der der Screen in diesem Test liegt.
const String _startRoute = '/zufallschat';
