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
import 'package:thestia/models/chat/random_chat_session.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/swipe/random_chat_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/dating_hour/random_chat_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

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

/// Der P2P-Service ohne WebRTC (siehe der Chat-Test).
class _FakeP2PChatService extends P2PChatService {
  _FakeP2PChatService(super.webrtc, super.prekey);

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {}

  @override
  Future<void> dispose() async {}
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

  /// Wie oft [leave] aufgerufen wurde.
  int leaveAufrufe = 0;

  @override
  Future<void> leave(String sessionId) async {
    leaveAufrufe++;
  }
}

void main() {
  /// Der Client, den der Fake braucht.
  ///
  /// WICHTIG: `autoRefreshToken: false` - sonst laeuft ein periodischer
  /// Timer (alle 10 s), an dem der Test am Ende scheitern wuerde
  /// ("A Timer is still pending").
  late supabase.SupabaseClient client;

  /// Der Ersatz-Server (Antworten aus dem RAM).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // DER KEYSTORE und HIVE: der Chat holt sich den Verlauf und die
    // Schluessel aus dem Speicher - ohne diese Ersatzwaerter bleibt
    // der Aufbau haengen.
    mockKeystore();
    await mockHive();
    // DER CLIENT: der Bildschirm liest `Supabase.instance` (den
    // globalen Client) - ein eigener Client waere dort nicht sichtbar
    // (und die Edge-Funktionen brauchen eine Sitzung).
    // DER SERVER: die Anmeldung geht ueber den Client - ohne den
    // Ersatz-Server antwortet der Test-Client mit 400.
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
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
    client = supabase.Supabase.instance.client;
  });

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Der Container des zuletzt gebauten Bildschirms.
  ///
  /// EIGENER Container (nicht das ProviderScope): der Container lebt
  /// weiter, wenn der Bildschirm abgebaut wird - so kann der Test
  /// danach noch sehen, ob die "aktiver Chat"-Markierung wirklich
  /// geloescht wurde (beim Wegwerfen des Containers wuerde sie
  /// automatisch auf null zurueckspringen - das waere ein
  /// Scheintest).
  ProviderContainer? screenContainer;

  /// Baut den Zufallschat.
  ///
  /// [dienst] ist null, wenn es keinen Dienst gibt (offline).
  Future<void> zeigeScreen(
    WidgetTester tester, {
    RandomChatService? dienst,
    bool ohneDienst = false,
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

    final container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        if (dienst != null)
          randomChatServiceProvider.overrideWithValue(dienst)
        else if (ohneDienst)
          randomChatServiceProvider.overrideWithValue(null),
        // DER P2P-Fake: die echte Direktverbindung braucht das
        // WebRTC-Plugin - ohne sie bleibt `connect()` haengen und der
        // Bildschirm kommt ueber die Markierung nie hinaus.
        p2pChatServiceProvider.overrideWith((ref) {
          final dienst = _FakeP2PChatService(
            ref.watch(webRTCServiceProvider),
            ref.watch(preKeyServiceProvider),
          );
          ref.onDispose(dienst.dispose);
          return dienst;
        }),
      ],
    );
    screenContainer = container;
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
      await zeigeScreen(tester, ohneDienst: true);

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

    testWidgets('der Partner kommt waehrend der Suche dazu', (tester) async {
      final dienst = _FakeRandomChatService(client);
      // Zuerst wartet die Sitzung (noch kein Partner).
      dienst.session = const RandomChatSession(sessionId: 's-1');
      await zeigeScreen(tester, dienst: dienst);

      expect(
        find.text(L10n.tWithoutContext('random.searching')),
        findsOneWidget,
      );

      // Jetzt kommt der Partner: der Poll holt die gematchte Sitzung.
      dienst.befragteSession = const RandomChatSession(
        sessionId: 's-1',
        partnerId: 'partner-1',
        status: RandomChatStatus.active,
      );
      await tester.pump(const Duration(seconds: 2));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Suchhinweis ist weg - der Chat steht.
      expect(
        find.text(L10n.tWithoutContext('random.searching')),
        findsNothing,
        reason: 'Mit dem Partner muss der Suchhinweis verschwinden.',
      );
    });

    /// Bringt den Screen in den Chat-Zustand (Partner da).
    Future<_FakeRandomChatService> imChat(
      WidgetTester tester, {
      RandomChatSession? session,
    }) async {
      final dienst = _FakeRandomChatService(client);
      dienst.session =
          session ??
          const RandomChatSession(
            sessionId: 's-1',
            partnerId: 'partner-1',
            status: RandomChatStatus.active,
          );
      await zeigeScreen(tester, dienst: dienst);
      await pumpFrames(tester);
      // Der Partner-Aufruf geht ueber den Server - also warten, bis der
      // Chat steht.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byIcon(Icons.favorite).evaluate().isNotEmpty) break;
      }
      return dienst;
    }

    testWidgets('das Like an die Person geht an den Server', (tester) async {
      await imChat(tester);

      expect(tester.takeException(), isNull);
      // Der Like-Knopf (das Herz) steht da.
      final knopf = find.byIcon(Icons.favorite);
      expect(knopf, findsOneWidget);
      await tester.tap(knopf);
      await pumpFrames(tester);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      // Der Server hat den Like bekommen - sonst weiss die Person nicht,
      // dass jemand interestant ist.
      expect(
        server.rpcAufrufe.any((c) => c['funktion'] == 'like_user'),
        isTrue,
        reason: 'Der Like muss beim Server ankommen.',
      );
      // Und der Nutzer bekommt die Bestaetigung.
      expect(
        find.textContaining(
          L10n.tWithoutContext('random.likeSentWaiting').split(' ').first,
        ),
        findsWidgets,
      );
    });

    testWidgets('das Beenden fragt erst nach', (tester) async {
      final dienst = await imChat(tester);

      // Der Block-Knopf (das Beenden).
      await tester.tap(find.byIcon(Icons.block));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Ohne Rueckfrage waere der Chat weg - und der Nutzer weiss nicht,
      // ob das Beenden durchging.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('random.leaveTitle')),
        findsOneWidget,
      );
      // Und es ist noch nichts passiert.
      expect(dienst.leaveAufrufe, 0);
    });

    testWidgets('das Beenden geht an den Dienst', (tester) async {
      final dienst = await imChat(tester);

      await tester.tap(find.byIcon(Icons.block));
      await pumpFrames(tester);
      // Bestaetigen.
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('random.leaveConfirm'),
        ),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        dienst.leaveAufrufe,
        greaterThan(0),
        reason: 'Der Dienst muss wissen, dass die Sitzung vorbei ist.',
      );
    });

    testWidgets('der Partner ist gegangen: die App sagt es', (tester) async {
      final dienst = _FakeRandomChatService(client);
      dienst.session = const RandomChatSession(
        sessionId: 's-1',
        partnerId: 'partner-1',
        status: RandomChatStatus.active,
      );
      await zeigeScreen(tester, dienst: dienst);
      await pumpFrames(tester);

      // Der Partner ist weg: die Sitzung ist beendet.
      dienst.befragteSession = const RandomChatSession(
        sessionId: 's-1',
        partnerId: 'partner-1',
        status: RandomChatStatus.ended,
      );

      // Der Status-Poll tickt alle fuenf Sekunden.
      await tester.pump(const Duration(seconds: 6));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.partnerLeft')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass der Partner weg ist - sonst '
            'schreibt er ins Leere.',
      );
    });

    testWidgets('der aktive Chat wird beim Verlassen wieder freigegeben', (
      tester,
    ) async {
      final dienst = _FakeRandomChatService(client);
      dienst.session = const RandomChatSession(
        sessionId: 's-1',
        partnerId: 'partner-1',
        status: RandomChatStatus.active,
      );
      await zeigeScreen(tester, dienst: dienst);
      await pumpFrames(tester);

      final container = screenContainer!;

      // Das Match braucht echte Zeit (der Partner-Aufruf geht ueber den
      // Server) - also warten, bis die Markierung steht.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump(const Duration(milliseconds: 100));
        if (container.read(activeChatIdProvider) != null) break;
      }
      expect(
        container.read(activeChatIdProvider),
        isNotNull,
        reason:
            'Waehrend des Chats muss der aktive Chat markiert sein - sonst '
            'kommen die Meldungen des Partners als Push an.',
      );

      // Beim Verlassen des Bildschirms muss die Markierung wieder weg.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        container.read(activeChatIdProvider),
        isNull,
        reason:
            'Nach dem Verlassen darf die Markierung nicht stehen bleiben - '
            'sonst kommen die Meldungen des Partners bis zum App-Ende '
            'nicht an.',
      );
    });
  });
}

/// Die Route, auf der der Screen in diesem Test liegt.
const String _startRoute = '/zufallschat';
