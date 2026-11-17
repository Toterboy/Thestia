// Widget-Tests fuer den Screen "Interessen" (Reiter der Startseite).
//
// ANLASS: Die Coverage-Messung (13.11.2026) zeigte fuer
// lib/screens/interests/interessen_screen.dart 835 offene Zeilen - der
// Screen war die groesste Luecke der App. Er ist die Antwort auf die
// Frage "was ist mit meinem Like passiert?" - und genau dort hat der
// Betreiber im November 2026 mehrere Befunde gemeldet (Funke
// verschwunden, Reiter springt, Leerzustand sah wie ein Fehler aus).
//
// WAS HIER GEPRUEFT WIRD:
//   * der Screen baut sich (kein Absturz, kein Render-Overflow),
//   * der Leerzustand steht da (nicht "nichts gefunden", sondern der
//     ausgeschriebene Leerzustand),
//   * die Funkenliste zeigt die Kachel mit Namen und Alter,
//   * "Aus Liste entfernen" blendet den Funken wirklich aus,
//   * ein fehlgeschlagener Abruf zeigt den Fehler MIT Wiederholen -
//     nicht die leere Liste (BEFUND 13.11.2026: "Außerdem ist mein
//     Funke verschwunden"),
//   * der Mehrfach-Auswahl-Modus blendet die gewaehlten Funken aus.
//
// OHNE SERVER: Der Find-your-Match-Service wird durch einen Hand-Fake
// ersetzt (siehe [_FakeFindYourMatchService]). Der Supabase-Client wird
// nur initialisiert, damit der Screen seinen Serverstand ueberhaupt
// abfragt - es geht KEINE Anfrage raus (alle Aufrufe landen im Fake).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/providers/pinned_matches_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/interests/interessen_screen.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/widgets/funke_overlay.dart';

import 'support/fake_supabase_server.dart';
import 'support/plugin_mocks.dart';

/// In-Memory-Speicher - der Screen schreibt Seen-Marker und
/// Fixierungen dorthin.
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

/// Hand-Fake des Find-your-Match-Service.
///
/// Der echte Service spricht mit der Datenbank. Der Fake beantwortet
/// alles aus dem RAM und zaehlt die Schreibaufrufe - so wird sichtbar,
/// ob die App wirklich "ausgeblendet" hat oder nur so tut.
class _FakeFindYourMatchService extends FindYourMatchService {
  _FakeFindYourMatchService(super.client);

  /// Der Ersatz-Server - der Fake liest daraus, was der Server bekommen
  /// hat.
  ///
  /// DER GRUND: Ein automatisch entstandener Funke wird ueber die RPC
  /// "resolve_dating_hour_auto_match" geloescht. Der Server ist die
  /// Wahrheit - also filtert der Fake den Funke weg, sobald die RPC mit
  /// "Person entfernen" angekommen ist. Sonst wuerde der Funke nach dem
  /// Neuladen wieder dastehen, obwohl er beim Server geloescht wurde.
  FakeSupabaseServer? server;

  /// Eigene (gesendete) Likes.
  List<ReceivedLike> eigeneLikes = const [];

  /// Erhaltene Likes.
  List<ReceivedLike> erhalteneLikes = const [];

  /// Die Funken (Matches).
  List<MatchWithState> funken = const [];

  /// Wenn gesetzt, wirft [listMatchesWithState] diesen Fehler.
  Object? ladeFehler;

  /// Die IDs der ausgeblendeten Funken.
  final List<int> ausgeblendet = [];

  /// Die IDs der gekuehlten Funken.
  final List<int> gekuehlt = [];

  /// Die beantworteten Likes (ID und ob angenommen).
  final List<({int likeId, bool accept})> beantwortet = [];

  /// Die ausgeblendeten Likes (nur ausgeblendet, nicht abgelehnt).
  final List<int> ausgeblendeteLikes = [];

  /// Die endgueltig beendeten Funken.
  final List<int> beendet = [];

  /// Die wieder entzuendeten Funken.
  final List<int> wiederEntzuend = [];

  /// Wenn gesetzt, wirft [coolMatch] diesen Fehler.
  Object? coolFehler;

  /// Wenn gesetzt, wirft [hideMatch] diesen Fehler.
  Object? hideFehler;

  /// Wenn gesetzt, wirft [ignoreLike] diesen Fehler.
  Object? ignoreFehler;

  /// Wenn gesetzt, wirft [respondToLike] diesen Fehler.
  Object? respondFehler;

  /// Wie oft wurden die Funken geladen?
  ///
  /// DER GRUND: Damit sieht ein Test, dass wirklich neu geladen wurde -
  /// am Bildschirm aendert sich beim Nachladen oft nichts.
  int matchesAufrufe = 0;

  /// Wie oft wurden die eigenen (gesendeten) Likes geladen?
  int eigeneLikesAufrufe = 0;

  @override
  Future<List<ReceivedLike>> listMyLikes() async {
    eigeneLikesAufrufe++;
    return eigeneLikes;
  }

  @override
  Future<List<ReceivedLike>> listReceivedLikes() async => erhalteneLikes;

  @override
  Future<List<MatchWithState>> listMatchesWithState() async {
    matchesAufrufe++;
    final fehler = ladeFehler;
    if (fehler != null) throw fehler;
    // Der automatische Funke, der beim Server geloescht wurde, ist auch
    // hier weg (der Server ist die Wahrheit).
    final geloeschte = server?.rpcAufrufe
        .where(
          (c) =>
              c['funktion'] == 'resolve_dating_hour_auto_match' &&
              c['p_keep'] == false,
        )
        .map((c) => c['p_partner_id'])
        .toSet();
    if (geloeschte == null || geloeschte.isEmpty) return funken;
    return funken.where((m) => !geloeschte.contains(m.partner.id)).toList();
  }

  @override
  Future<void> hideMatch(int matchId) async {
    final fehler = hideFehler;
    if (fehler != null) throw fehler;
    ausgeblendet.add(matchId);
  }

  @override
  Future<void> coolMatch(int matchId) async {
    final fehler = coolFehler;
    if (fehler != null) throw fehler;
    gekuehlt.add(matchId);
  }

  @override
  Future<void> endMatch(int matchId) async => beendet.add(matchId);

  @override
  Future<void> resparkMatch(int matchId) async => wiederEntzuend.add(matchId);

  @override
  Future<void> respondToLike(int likeId, {required bool accept}) async {
    final fehler = respondFehler;
    if (fehler != null) throw fehler;
    beantwortet.add((likeId: likeId, accept: accept));
  }

  @override
  Future<void> ignoreLike(int likeId) async {
    final fehler = ignoreFehler;
    if (fehler != null) throw fehler;
    ausgeblendeteLikes.add(likeId);
  }
}

/// Die Partnerin als Profil.
UserProfile _person({String id = 'p1', String name = 'Mira', int? alter = 30}) {
  return UserProfile(
    id: id,
    name: name,
    bio: 'Liest gern',
    birthDate: alter == null
        ? null
        : DateTime(DateTime.now().year - alter, 5, 4),
  );
}

/// Ein Funke (Match) mit der Partnerin.
MatchWithState _funke({
  int id = 7,
  String name = 'Mira',
  int? alter = 30,
  String status = 'active',
  DateTime? erstellt,
  bool autoMatch = false,
}) {
  return MatchWithState(
    matchId: id,
    partner: _person(name: name, alter: alter),
    unlockLevel: 2,
    failedAttempts: 0,
    createdVia: 'swipe',
    status: status,
    // FRISCH: ein alter Funke wuerde von der Auto-Kuehlung (72 h) erfasst.
    createdAt: erstellt ?? DateTime.now(),
    // AUTOMATISCH: der Funke kam nach 10 Minuten Dating Hour zustande und
    // wurde NICHT von beiden Seiten bestaetigt (Migration 177).
    autoMatch: autoMatch,
  );
}

/// Der Router, den der Screen braucht (Profil- und Chat-Route).
GoRouter _router() {
  return GoRouter(
    initialLocation: _startRoute,
    routes: [
      GoRoute(
        path: _startRoute,
        builder: (context, state) => const InteressenScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/profile/:id',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Profil'))),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Chat'))),
      ),
    ],
  );
}

/// Die Route, auf der der Screen in diesem Test liegt.
const String _startRoute = '/interessen';

/// Baut den Screen mit dem Fake-Service.
///
/// [pumpAndSettle] waere hier falsch: der Ladeplatzhalter ([CalmLoading])
/// atmet endlos - pumpAndSettle wuerde nie fertig. Deshalb werden
/// feste Frames gepumpt.
///
/// [overrides] erlaubt zusaetzliche Provider zu ersetzen (z. B. die
/// Chatliste fuer die gespeicherten Profile).
Future<_FakeFindYourMatchService> _pump(
  WidgetTester tester, {
  required _FakeFindYourMatchService service,
  double scale = 1.0,
  List<Override> overrides = const <Override>[],
}) async {
  final router = _router();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        findYourMatchServiceProvider.overrideWithValue(service),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        routerConfig: router,
        // Die MediaQuery sitzt im `builder` - eine aeussere MediaQuery
        // wuerde vom MaterialApp ueberschrieben.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await _pumpFrames(tester);
  return service;
}

/// Pumpt eine feste Zahl von Frames - der Ladeindikator atmet endlos,
/// deshalb kann man nicht auf "alles ruhig" warten.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Laesst die ECHTE Ereignisschleife laufen, damit HTTP-Anfragen
/// durchgehen.
///
/// DER GRUND: Im Widget-Test laeuft alles in einer Fake-Zone - eine
/// echte Netz-Anfrage (z. B. die RPC zum Aufloesen des automatischen
/// Funken) kommt dort nie voran. `runAsync` schaltet kurz auf die
/// echte Schleife um.
///
/// [fertig]: Was erreicht sein muss - sobald das da ist, wird nicht
/// weiter gewartet.
Future<void> lassServerArbeiten(
  WidgetTester tester, {
  bool Function()? fertig,
}) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 60));
    if (fertig != null && fertig()) return;
  }
}

void main() {
  /// Der Ersatz-Server (Antworten aus dem RAM).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Der Client wird nur initialisiert, damit
    // [SupabaseService.isInitialized] true ist und der Screen den
    // Serverstand ueberhaupt abfragt. Es geht keine Anfrage raus - der
    // Service ist ein Fake.
    //
    // autoRefreshToken: false - sonst laeuft ein periodischer Timer,
    // an dem der Test am Ende scheitern wuerde.
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DIE ECHTE SCHRIFT: Ohne sie benutzt der Test die Test-Schrift,
    // bei der jedes Zeichen so breit ist wie die Schrift gross - jede
    // Zeile laeuft dann ueber den Rand. Der Test meldet damit Fehler,
    // die es in der App gar nicht gibt.
    await ladeEchteSchrift();
    // DER KEYSTORE: dasselbe Spiel - auf dem Linux-Runner
    // gibt es keine libsecret-Sitzung.
    mockKeystore();
    // HIVE: Die gespeicherten Profile (QR-Kontakte) liegen in einer
    // Hive-Box - ohne initialisiertes Hive wirft der Chat-Dienst
    // ("You need to initialize Hive").
    await mockHive();
    // DER SERVER: das Zuruecknehmen eines Likes geht ueber die
    // REST-Schnittstelle (DELETE auf 'likes') - ohne den Ersatz-Server
    // gaengt der Aufruf ins Leere.
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
    // ANGEMELDET: ohne Sitzung weiss der Bildschirm nicht, wessen Like
    // das ist - das Zuruecknehmen ginge dann gar nicht.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Der Server merkt sich die Anfragen - fuer jeden Test beginnt er
    // neu. Sonst wuerde ein Test den Aufruf eines anderen sehen (und
    // der "schweigt"-Test wuerde alle folgenden stoeren).
    server.pfade.clear();
    server.rpcAufrufe.clear();
    server.rpcFehler.clear();
  });

  group('Interessen-Screen', () {
    testWidgets('baut sich mit Reitern und Funken-Kopf', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      await _pump(tester, service: service);

      expect(tester.takeException(), isNull);
      expect(find.text('Interessen'), findsOneWidget);
      // Die beiden aufgeklappbaren Reiter.
      expect(find.text('Gesendet'), findsOneWidget);
      expect(find.text('Erhalten'), findsOneWidget);
      // Der Funken-Kopf steht immer da - die Funken sind kein Reiter
      // mehr, sondern stehen immer unter den beiden Reitern.
      expect(find.text('Funken'), findsOneWidget);
    });

    testWidgets('ohne Funken steht der Leerzustand da', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      await _pump(tester, service: service);

      expect(tester.takeException(), isNull);
      expect(find.text('Noch keine Funken'), findsOneWidget);
      expect(find.textContaining('Bestätige erhaltene Likes'), findsOneWidget);
      // Ohne Funken gibt es auch nichts zu verwalten - der Stift im
      // App-Bereich waere ein Knopf ohne Wirkung.
      expect(find.byTooltip('Verwalten'), findsNothing);
    });

    testWidgets('die Reiter oeffnen die Listen mit ihrem Leerzustand', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      await _pump(tester, service: service);

      // "Gesendet" aufklappen.
      await tester.tap(find.text('Gesendet'));
      await _pumpFrames(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Du hast noch niemanden geliked'), findsOneWidget);

      // "Erhalten" aufklappen - die Liste wechselt.
      await tester.tap(find.text('Erhalten'));
      await _pumpFrames(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Noch keine erhaltenen Likes'), findsOneWidget);
    });

    testWidgets('ein gesendeter Like steht mit seinem Datum da', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.eigeneLikes = [
        ReceivedLike(
          likeId: 1,
          profile: _person(name: 'Jonas'),
          createdAt: DateTime.now(),
        ),
      ];
      await _pump(tester, service: service);

      await tester.tap(find.text('Gesendet'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Jonas'), findsOneWidget);
      // "Heute gesendet" - der Nutzer will wissen, WANN der Like rausging.
      expect(find.textContaining('Heute gesendet'), findsOneWidget);
    });

    testWidgets('die Funkenliste zeigt die Kachel mit Namen und Alter', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      expect(tester.takeException(), isNull);
      expect(find.text('Mira, 30'), findsOneWidget);
      // Der Stift erscheint, weil es etwas zu verwalten gibt.
      expect(find.byTooltip('Verwalten'), findsOneWidget);
    });

    testWidgets('"Aus Liste entfernen" blendet den Funken aus', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      // Das Drei-Punkte-Menue der Kachel oeffnen.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      expect(find.text('Aus Liste entfernen'), findsOneWidget);

      await tester.tap(find.text('Aus Liste entfernen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Server wurde wirklich informiert ...
      expect(service.ausgeblendet, contains(7));
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text('Mira aus der Liste entfernt.'), findsOneWidget);
    });

    testWidgets('der Verwalten-Modus blendet die gewaehlten Funken aus', (
      tester,
    ) async {
      // BREITES Fenster: im Flutter-Test ist jeder Buchstabe ein Quadrat
      // und damit rund doppelt so breit wie auf dem Geraet. Die Knopfzeile
      // des Auswahl-Modus passt bei dieser Breite sonst ueber - das ist
      // ein Artefakt des Test-Fonts, nicht des Screens (siehe Bericht).
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      // Der Stift schaltet den Auswahl-Modus frei.
      await tester.tap(find.byTooltip('Verwalten'));
      await _pumpFrames(tester);

      // Jetzt ist die Kachel eine Checkbox.
      await tester.tap(find.text('Mira, 30'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Ausblenden (1)'), findsOneWidget);

      await tester.tap(find.text('Ausblenden (1)'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(service.ausgeblendet, contains(7));
      expect(find.text('1 Chat(s) aus der Liste entfernt.'), findsOneWidget);
    });

    testWidgets('ein Ladefehler zeigt den Hinweis mit Wiederholen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.ladeFehler = StateError('Server nicht erreichbar');
      await _pump(tester, service: service);

      expect(tester.takeException(), isNull);
      // BEFUND (13.11.2026): Ein fehlgeschlagener Abruf sah aus wie
      // "du hast keine Funken". Jetzt steht der Fehler da.
      expect(
        find.textContaining('Die Funken konnten nicht geladen werden'),
        findsOneWidget,
      );
      // Und es gibt einen Weg zurueck.
      expect(find.text('Erneut versuchen'), findsOneWidget);
    });

    testWidgets('"Erneut versuchen" laedt die Funken nach', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.ladeFehler = StateError('Server nicht erreichbar');
      await _pump(tester, service: service);
      expect(find.text('Erneut versuchen'), findsOneWidget);

      // Der Server antwortet jetzt.
      service.ladeFehler = null;
      service.funken = [_funke()];

      await tester.tap(find.text('Erneut versuchen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Mira, 30'), findsOneWidget);
    });

    testWidgets('rendert ohne Overflow bei grosser Schrift', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service, scale: 3.2);

      expect(tester.takeException(), isNull);
    });

    testWidgets('ein Like annehmen wird dem Server gemeldet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.erhalteneLikes = [
        ReceivedLike(
          likeId: 3,
          profile: _person(name: 'Jonas', alter: 31),
          createdAt: DateTime.now(),
        ),
      ];
      await _pump(tester, service: service);

      // "Erhalten" aufklappen.
      await tester.tap(find.text('Erhalten'));
      await _pumpFrames(tester);

      await tester.tap(find.text('Funke bestätigen'));
      await _pumpFrames(tester);

      // Der Server wurde wirklich informiert ...
      expect(service.beantwortet, hasLength(1));
      expect(service.beantwortet.first.likeId, 3);
      expect(
        service.beantwortet.first.accept,
        isTrue,
        reason: 'Der Knopf heisst "Funke bestätigen" - das ist ein Annehmen.',
      );

      // ... und die Gegenseite sieht die Funke-Animation.
      expect(find.byType(FunkeOverlay), findsOneWidget);

      // Die Animation laeuft von selbst ab (1,1 s) - danach kommt die
      // Bestaetigung.
      await tester.pump(const Duration(milliseconds: 1500));
      await _pumpFrames(tester);
      expect(find.byType(FunkeOverlay), findsNothing);

      // Und der Nutzer bekommt die Bestaetigung.
      expect(find.textContaining('Jonas'), findsWidgets);
    });

    testWidgets('ein Like ausblenden lehnt es nicht ab', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.erhalteneLikes = [
        ReceivedLike(
          likeId: 4,
          profile: _person(name: 'Jonas', alter: 31),
          createdAt: DateTime.now(),
        ),
      ];
      await _pump(tester, service: service);

      await tester.tap(find.text('Erhalten'));
      await _pumpFrames(tester);

      // Das Auge mit dem Strich heisst "ausblenden" - die Gegenseite
      // darf davon NICHTS sehen (BEFUND 07.11.2026).
      await tester.tap(find.byTooltip('Ignorieren'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(service.ausgeblendeteLikes, contains(4));
      expect(
        service.beantwortet,
        isEmpty,
        reason:
            'Ausblenden ist kein Ablehnen - die Gegenseite darf nichts '
            'davon sehen.',
      );
      expect(find.text('Jonas ist ausgeblendet.'), findsOneWidget);
    });

    testWidgets('ein gesendeter Like laesst sich zuruecknehmen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.eigeneLikes = [
        ReceivedLike(
          likeId: 11,
          profile: _person(name: 'Jonas', alter: 31),
          createdAt: DateTime.now(),
        ),
      ];
      await _pump(tester, service: service);

      // Der Reiter "Gesendet" mit den eigenen Likes.
      await tester.tap(find.text('Gesendet'));
      await _pumpFrames(tester);

      expect(find.text('Jonas'), findsWidgets);

      // Das Menue der Person -> "Like zurueckziehen".
      await tester.tap(find.byIcon(Icons.more_vert).last);
      await _pumpFrames(tester);
      await tester.tap(find.text('Like zurückziehen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Server hat die Loeschung bekommen ...
      expect(
        server.schreibvorgaenge.any((v) => v['tabelle'] == 'likes'),
        isTrue,
        reason: 'Das Zuruecknehmen muss auf dem Server ankommen.',
      );
      // ... und die Like ist aus der Liste verschwunden.
      expect(find.text('Jonas'), findsNothing);
      expect(find.text('Like zurückgezogen.'), findsOneWidget);
    });

    // Das Datum des gesendeten Likes (NUTZERWUNSCH 28.10.2026: "kann
    // auch sehen, an welchem Tag man den Like gesendet hat").
    group('Das Datum des gesendeten Likes', () {
      /// Baut den Screen mit einem Like, der [vorher] gesendet wurde.
      Future<void> zeigeLike(
        WidgetTester tester, {
        required Duration vorher,
      }) async {
        final service = _FakeFindYourMatchService(
          supabase.Supabase.instance.client,
        );
        service.eigeneLikes = [
          ReceivedLike(
            likeId: 21,
            profile: _person(name: 'Jonas'),
            createdAt: DateTime.now().subtract(vorher),
          ),
        ];
        await _pump(tester, service: service);

        // "Gesendet" aufklappen (wie der Test, der schon gruen ist).
        await tester.tap(find.text('Gesendet'));
        await _pumpFrames(tester);
      }

      testWidgets('ein heute gesendeter Like steht als "Heute" da', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await zeigeLike(tester, vorher: const Duration(hours: 2));

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining(L10n.tWithoutContext('interests.likeToday')),
          findsWidgets,
          reason:
              'Der Nutzer soll sehen, WANN der Like rausging - das steht '
              'in der Zeile unter dem Namen.',
        );
      });

      testWidgets('ein gestern gesendeter Like steht als "Gestern" da', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await zeigeLike(tester, vorher: const Duration(days: 1, hours: 2));

        expect(tester.takeException(), isNull);
        expect(
          find.textContaining(L10n.tWithoutContext('interests.likeYesterday')),
          findsWidgets,
        );
      });

      testWidgets('ein aelterer Like steht mit seinem Datum da', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await zeigeLike(tester, vorher: const Duration(days: 20));

        expect(tester.takeException(), isNull);
        // Nach einer Woche steht das konkrete Datum da (kein "vor X
        // Tagen" mehr - das waere beim Scrollen unlesbar).
        // Das Kalenderdatum des Likes (20 Tage zurueck).
        final damals = DateTime.now().subtract(const Duration(days: 20));
        expect(
          find.textContaining('${damals.day}.${damals.month}.${damals.year}'),
          findsWidgets,
          reason: 'Ein alterer Like muss sein Kalenderdatum zeigen.',
        );
      });
    });

    testWidgets('das Blockieren fragt erst nach', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.erhalteneLikes = [
        ReceivedLike(
          likeId: 9,
          profile: _person(name: 'Jonas', alter: 31),
          createdAt: DateTime.now(),
        ),
      ];
      await _pump(tester, service: service);

      await tester.tap(find.text('Erhalten'));
      await _pumpFrames(tester);

      // Das Menue der Like-Kachel.
      await tester.tap(find.byIcon(Icons.more_vert).last);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Blockieren'));
      await _pumpFrames(tester);

      // Es fragt nach - blockiert wird nicht ohne Rueckfrage.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('Jonas'),
        findsWidgets,
        reason: 'Der Dialog nennt die Person, die blockiert werden soll.',
      );
    });

    testWidgets('das Funken-Menue bietet alle Wege', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      // Das Drei-Punkte-Menue der Funke-Kachel oeffnen.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Archivieren, Loeschen, Ausblenden ...
      expect(find.text('Archivieren'), findsOneWidget);
      expect(find.text('Funke löschen'), findsOneWidget);
      expect(find.text('Aus Liste entfernen'), findsOneWidget);
      // ... und die Sicherheitswege (BEFUND 01.11.2026).
      expect(find.text('Nutzer melden'), findsOneWidget);
      expect(find.text('Blockieren'), findsOneWidget);
    });

    testWidgets('"Archivieren" fragt nach und meldet es dem Server', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Archivieren'));
      await _pumpFrames(tester);

      // Der ehrliche Dialog kommt - es gibt zwei Wege (ruhig oder mit
      // einem Absage-Text).
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Ruhig enden lassen'), findsOneWidget);

      // "Ruhig enden" - ohne Nachricht.
      await tester.tap(find.text('Funke kühlen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Server wurde wirklich informiert ...
      expect(service.gekuehlt, contains(7));
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.textContaining('Mira'), findsWidgets);
    });

    testWidgets('"Funke loeschen" fragt nach und beendet ihn', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Funke löschen'));
      await _pumpFrames(tester);

      // Die Rueckfrage kommt (zwei Knöpfe: abbrechen und loeschen).
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Funke löschen?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Funke löschen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Server wurde wirklich informiert ...
      expect(service.beendet, contains(7));
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text('Funke gelöscht.'), findsOneWidget);
    });

    testWidgets('"Aus Liste entfernen" meldet es dem Server', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Aus Liste entfernen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(service.ausgeblendet, contains(7));
      expect(find.textContaining('Mira'), findsWidgets);
    });

    testWidgets('"Re-Funke ohne Druck" entzuendet einen gekuehlten Funke', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      // Ein gekuehlter (archivierter) Funke.
      service.funken = [_funke(status: 'cooled')];
      await _pump(tester, service: service);

      // Der Abschnitt "Archivierte Funken" steht da.
      expect(find.text('Archivierte Funken'), findsOneWidget);

      // Der Re-Funke-Knopf (er liegt unterhalb des Bildschirms - erst
      // sichtbar machen).
      final knopf = find.widgetWithText(FilledButton, 'Re-Funke');
      expect(knopf, findsOneWidget);
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(service.wiederEntzuend, contains(7));
      expect(find.textContaining('Mira'), findsWidgets);
    });

    testWidgets('ein Funke ohne Aktivitaet wird automatisch gekuehlt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      // Acht Tage alt und ohne Nachricht: nach 72 Stunden ohne
      // Aktivitaet wird er gekuehlt (der Nutzer soll nicht wochenlang
      // einen Funken sehen, der niemanden bewegt).
      service.funken = [
        _funke(erstellt: DateTime.now().subtract(const Duration(days: 8))),
      ];
      await _pump(tester, service: service);

      expect(tester.takeException(), isNull);
      expect(
        service.gekuehlt,
        contains(7),
        reason:
            'Ein Funke ohne Aktivitaet wird nach 72 Stunden gekuehlt - '
            'das muss der Server erfahren.',
      );
    });

    testWidgets('ein frischer Funke wird NICHT gekuehlt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      expect(tester.takeException(), isNull);
      expect(
        service.gekuehlt,
        isEmpty,
        reason:
            'Ein frischer Funke darf nicht gekuehlt werden - der Nutzer '
            'hat ihn gerade erst bekommen.',
      );
    });
  });

  // Der automatische Funke (Migration 177): nach 10 Minuten Dating Hour
  // entsteht ein Funke, den BEIDE Seiten nicht bestaetigt haben. Der
  // Nutzer soll deshalb EINMAL entscheiden: behalten oder Person
  // entfernen. Ohne diese Nachfrage steht ein Funke da, den niemand
  // wollte - der Betreiber hat das im November 2026 so gemeldet.
  group('Der automatische Funke (Migration 177)', () {
    /// Die RPC, die den automatischen Funke aufloest.
    const String rpc = 'resolve_dating_hour_auto_match';

    /// Baut den Screen mit einem automatischen Funken.
    Future<_FakeFindYourMatchService> mitAutoFunke(WidgetTester tester) async {
      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.server = server;
      service.funken = [_funke(autoMatch: true)];
      await _pump(tester, service: service);
      return service;
    }

    /// Tippt auf den Funken und beantwortet die Nachfrage.
    ///
    /// [behalten]: true = "Behalten", false = "Person entfernen".
    Future<void> frageBeantworten(
      WidgetTester tester, {
      required bool behalten,
    }) async {
      await tester.tap(find.text('Mira, 30'));
      await _pumpFrames(tester);
      // Der Dialog braucht einen ruhigen Frame - sonst geht der Klick
      // ins Leere.
      await tester.pump(const Duration(milliseconds: 400));
      if (behalten) {
        await tester.tap(find.widgetWithText(FilledButton, 'Behalten'));
      } else {
        await tester.tap(find.widgetWithText(TextButton, 'Person entfernen'));
      }
      await _pumpFrames(tester);
    }

    testWidgets('der automatische Funke fragt erst nach', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await mitAutoFunke(tester);

      expect(tester.takeException(), isNull);
      // Das Sternchen weist auf den automatischen Funke hin.
      expect(find.byTooltip('Automatisch'), findsOneWidget);

      // Der Tap auf die Kachel fragt nach - der Chat geht NICHT sofort auf.
      await tester.tap(find.text('Mira, 30'));
      await _pumpFrames(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Automatischer Funke'), findsOneWidget);
      expect(find.text('Behalten'), findsOneWidget);
      expect(find.text('Person entfernen'), findsOneWidget);
      // Und es ist noch nichts beim Server passiert.
      expect(
        server.rpcAufrufe.where((c) => c['funktion'] == rpc),
        isEmpty,
        reason:
            'Vor der Antwort des Nutzers darf nichts beim Server passieren '
            '- die Nachfrage ist eine echte Entscheidung.',
      );
    });

    testWidgets('"Behalten" loest den Funke auf und oeffnet den Chat', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await mitAutoFunke(tester);
      await frageBeantworten(tester, behalten: true);

      // Die RPC braucht die echte Ereignisschleife.
      await lassServerArbeiten(
        tester,
        fertig: () => server.rpcAufrufe.any((c) => c['funktion'] == rpc),
      );
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Die RPC bekommt die Adresse der ANDEREN Person (nicht die eigene)
      // und den Entschluss "behalten".
      final aufruf = server.rpcAufrufe.firstWhere((c) => c['funktion'] == rpc);
      expect(aufruf['p_partner_id'], 'p1');
      expect(
        aufruf['p_keep'],
        isTrue,
        reason: '"Behalten" heisst p_keep = true.',
      );
      // Der Hinweis verschwindet ...
      expect(find.text('Alles klar, der Hinweis ist weg.'), findsOneWidget);
      // ... und der Chat geht auf (die Frage soll nicht blockieren).
      expect(find.text('Chat'), findsOneWidget);
    });

    testWidgets('"Person entfernen" loescht den Funke', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await mitAutoFunke(tester);
      await frageBeantworten(tester, behalten: false);

      await lassServerArbeiten(
        tester,
        fertig: () => server.rpcAufrufe.any((c) => c['funktion'] == rpc),
      );
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      final aufruf = server.rpcAufrufe.firstWhere((c) => c['funktion'] == rpc);
      expect(aufruf['p_partner_id'], 'p1');
      expect(
        aufruf['p_keep'],
        isFalse,
        reason: '"Person entfernen" heisst p_keep = false.',
      );
      // Der Funke ist weg - und kommt beim naechsten Laden nicht wieder.
      expect(
        find.text('Mira, 30'),
        findsNothing,
        reason:
            'Ein entfernter Funke darf nicht wiederkommen - der Server '
            'hat ihn geloescht.',
      );
    });

    testWidgets('ein abgebrochener Dialog aendert nichts', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await mitAutoFunke(tester);

      await tester.tap(find.text('Mira, 30'));
      await _pumpFrames(tester);
      expect(find.byType(AlertDialog), findsOneWidget);

      // Der Dialog wird weggetippt (der Rahmen neben dem Dialog).
      await tester.tapAt(const Offset(10, 10));
      await _pumpFrames(tester);
      await lassServerArbeiten(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      // Nichts passiert beim Server ...
      expect(server.rpcAufrufe.where((c) => c['funktion'] == rpc), isEmpty);
      // ... und der Funke steht noch da.
      expect(find.text('Mira, 30'), findsOneWidget);
    });

    testWidgets('der Server schweigt: der Nutzer sieht es', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Der Server schweigt bei genau dieser RPC.
      server.rpcFehler.add(rpc);

      await mitAutoFunke(tester);
      await frageBeantworten(tester, behalten: true);

      await lassServerArbeiten(
        tester,
        fertig: () => server.rpcAufrufe.any((c) => c['funktion'] == rpc),
      );
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Nutzer wird NICHT im Glauben gelassen, es hat geklappt.
      expect(
        find.text('Der Hinweis konnte nicht entfernt werden.'),
        findsOneWidget,
        reason:
            'Ein fehlgeschlagener Aufruf muss sichtbar sein - sonst '
            'glaubt der Nutzer, der Hinweis sei weg.',
      );
      // Der Sternchen-Hinweis steht noch da (die Datenbank hat ihn nicht
      // angenommen).
      //
      // DER HINWEIS: skipOffstage - der Chat liegt jetzt ueber dem
      // Bildschirm, der Bildschirm selbst ist also "offstage". Der
      // Hinweis muss aber trotzdem noch dastehen.
      expect(
        find.byTooltip('Automatisch', skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  group('Fixieren', () {
    testWidgets('"Fixieren" stellt den Funke in den eigenen Abschnitt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      // Das Menue der Kachel oeffnen.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Fixieren'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Die Fixierung ist gesetzt ...
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InteressenScreen)),
      );
      expect(container.read(pinnedMatchesProvider), contains(7));
      // ... der eigene Abschnitt steht da ...
      expect(find.text('Fixiert'), findsOneWidget);
      // ... die Nadel ist zu sehen ...
      expect(find.byIcon(Icons.push_pin), findsWidgets);
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text('Funke fixiert'), findsOneWidget);
    });

    testWidgets('"Fixieren" laesst sich wieder aufheben', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      // Erste Mal fixieren.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Fixieren'));
      await _pumpFrames(tester);
      expect(find.text('Fixiert'), findsOneWidget);

      // Die erste Meldung muss erst verschwinden - sonst wartet die
      // zweite in der Schlange hinter ihr (SnackBars stehen hinter-
      // einander an).
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));

      // Zweites Mal: die Fixierung geht wieder weg.
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Fixieren'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InteressenScreen)),
      );
      expect(container.read(pinnedMatchesProvider), isEmpty);
      expect(find.text('Fixiert'), findsNothing);
      expect(find.text('Fixierung aufgehoben'), findsOneWidget);
    });
  });

  group('Das Ziehen nach unten', () {
    testWidgets('laedt die Funken neu', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      final vorher = service.matchesAufrufe;

      // Nach unten ziehen (Pull-to-Refresh).
      await tester.drag(find.byType(ListView).first, const Offset(0, 300));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        service.matchesAufrufe,
        greaterThan(vorher),
        reason:
            'Das Ziehen nach unten muss die Funken neu laden - der Nutzer '
            'wartet sonst auf einen Stand, der gar nicht neu ist.',
      );
    });
  });

  group('Das gespeicherte Profil (QR-Kontakt)', () {
    testWidgets('"Entfernen" loescht den gespeicherten Kontakt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Der Chat-Dienst mit einem gespeicherten Profil.
      final chatService = ChatService();
      chatService.createQrContact(_person());

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      await _pump(
        tester,
        service: service,
        overrides: [
          chatProvider.overrideWith((ref) => ChatNotifier(chatService)),
        ],
      );

      expect(tester.takeException(), isNull);
      // Der Abschnitt "Gespeicherte Profile" steht da.
      expect(find.text('Gespeicherte Profile'), findsOneWidget);
      expect(find.text('Mira, 30'), findsOneWidget);

      // Der Mülleimer fragt erst nach (der Chat-Verlauf geht mit).
      // Der Knoepfchen liegt weit unten (unter den Reitern) - erst
      // dorthin scrollen, sonst trifft der Tap ins Leere.
      final loeschen = find.byTooltip('Gespeichertes Profil entfernen');
      await tester.ensureVisible(loeschen);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(loeschen);
      await _pumpFrames(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Gespeichertes Profil entfernen?'), findsOneWidget);

      // "Behalten" loescht nichts.
      await tester.tap(find.widgetWithText(TextButton, 'Behalten'));
      await _pumpFrames(tester);
      expect(find.text('Mira, 30'), findsOneWidget);

      // Und jetzt "Entfernen".
      await tester.ensureVisible(loeschen);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(loeschen);
      await _pumpFrames(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(FilledButton, 'Entfernen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Kontakt ist weg ...
      expect(find.text('Mira, 30'), findsNothing);
      expect(find.text('Gespeicherte Profile'), findsNothing);
      // ... und der Nutzer bekommt die Bestaetigung.
      expect(find.text('Mira wurde entfernt.'), findsOneWidget);
    });
  });

  // Die Fehlerwege: der Nutzer muss erfahren, wenn etwas NICHT
  // funktioniert hat. Ein stilles Scheitern waere das Schlimmste -
  // der Nutzer glaubt dann, es sei passiert.
  group('Die Fehlerwege', () {
    testWidgets('das Kuehlen meldet dem Nutzer den Fehler', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.coolFehler = StateError('Der Server hat nicht geantwortet.');
      service.funken = [_funke()];
      await _pump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Archivieren'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Funke kühlen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason:
            'Ein fehlgeschlagenes Kuehlen muss der Nutzer erfahren - '
            'sonst glaubt er, der Funke sei ruhig gestellt.',
      );
    });

    testWidgets('ein bereits gekuehlter Funke gilt als Erfolg', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      // Der Server meldet "bereits gekuehlt" (z. B. beim Doppel-Tap).
      service.coolFehler = Exception(
        'Funke nicht gefunden oder bereits gekuehlt/endet.',
      );
      service.funken = [_funke()];
      await _pump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Archivieren'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Funke kühlen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsNothing,
        reason:
            '"Bereits gekuehlt" ist kein Fehler - der Wunsch ist ja '
            'erfuellt. Der Nutzer darf keinen Fehler sehen.',
      );
      expect(find.textContaining('Mira'), findsWidgets);
    });

    testWidgets('das Ausblenden eines Funken meldet den Fehler', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.hideFehler = StateError('Der Server hat nicht geantwortet.');
      service.funken = [_funke()];
      await _pump(tester, service: service);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await _pumpFrames(tester);
      await tester.tap(find.text('Aus Liste entfernen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason:
            'Der Funke ist noch da - der Nutzer muss das wissen, sonst '
            'wartet er vergeblich auf das Verschwinden.',
      );
    });

    testWidgets('das Annehmen eines Likes meldet den Fehler', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.respondFehler = StateError('Der Server hat nicht geantwortet.');
      service.erhalteneLikes = [
        ReceivedLike(
          likeId: 3,
          profile: _person(name: 'Jonas', alter: 31),
          createdAt: DateTime.now(),
        ),
      ];
      await _pump(tester, service: service);

      await tester.tap(find.text('Erhalten'));
      await _pumpFrames(tester);
      await tester.tap(find.text('Funke bestätigen'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason: 'Der Like ist nicht bestaetigt - der Nutzer muss das wissen.',
      );
    });

    testWidgets('das Ausblenden eines Likes meldet den Fehler', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = _FakeFindYourMatchService(
        supabase.Supabase.instance.client,
      );
      service.ignoreFehler = StateError('Der Server hat nicht geantwortet.');
      service.erhalteneLikes = [
        ReceivedLike(
          likeId: 4,
          profile: _person(name: 'Jonas', alter: 31),
          createdAt: DateTime.now(),
        ),
      ];
      await _pump(tester, service: service);

      await tester.tap(find.text('Erhalten'));
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('Ignorieren'));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Fehler:'),
        findsOneWidget,
        reason: 'Der Like ist nicht ausgeblendet - der Nutzer muss das wissen.',
      );
    });
  });
}
