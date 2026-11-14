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

import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/interests/interessen_screen.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/local_storage.dart';

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

  @override
  Future<List<ReceivedLike>> listMyLikes() async => eigeneLikes;

  @override
  Future<List<ReceivedLike>> listReceivedLikes() async => erhalteneLikes;

  @override
  Future<List<MatchWithState>> listMatchesWithState() async {
    final fehler = ladeFehler;
    if (fehler != null) throw fehler;
    return funken;
  }

  @override
  Future<void> hideMatch(int matchId) async => ausgeblendet.add(matchId);

  @override
  Future<void> coolMatch(int matchId) async => gekuehlt.add(matchId);
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
}) {
  return MatchWithState(
    matchId: id,
    partner: _person(name: name, alter: alter),
    unlockLevel: 2,
    failedAttempts: 0,
    createdVia: 'swipe',
    status: status,
    // FRISCH: ein alter Funke wuerde von der Auto-Kuehlung (72 h) erfasst.
    createdAt: DateTime.now(),
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
Future<_FakeFindYourMatchService> _pump(
  WidgetTester tester, {
  required _FakeFindYourMatchService service,
  double scale = 1.0,
}) async {
  final router = _router();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        findYourMatchServiceProvider.overrideWithValue(service),
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

void main() {
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
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
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
  });
}
