// Die Helfer fuer die Tests des Bildschirms 'interessen_screen'.
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Helfer
// (Ersatz-Speicher, Aufbau, Bildschirm-Helfer) liegen hier -
// die Tests selbst sind nach Themen auf eigene Dateien verteilt.

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
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:thestia/models/find_match_models.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/interests/interessen_screen.dart';
import 'package:thestia/services/find_your_match_service.dart';
import 'package:thestia/services/local_storage.dart';
import '../support/fake_supabase_server.dart';

class FakeLocalStorage implements LocalStorage {
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

class FakeFindYourMatchService extends FindYourMatchService {
  FakeFindYourMatchService(super.client);

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

UserProfile person({String id = 'p1', String name = 'Mira', int? alter = 30}) {
  return UserProfile(
    id: id,
    name: name,
    bio: 'Liest gern',
    birthDate: alter == null
        ? null
        : DateTime(DateTime.now().year - alter, 5, 4),
  );
}

MatchWithState funke({
  int id = 7,
  String name = 'Mira',
  int? alter = 30,
  String status = 'active',
  DateTime? erstellt,
  bool autoMatch = false,
}) {
  return MatchWithState(
    matchId: id,
    partner: person(name: name, alter: alter),
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

GoRouter interessenScreenRouter() {
  return GoRouter(
    initialLocation: startRoute,
    routes: [
      GoRoute(
        path: startRoute,
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

const String startRoute = '/interessen';
Future<FakeFindYourMatchService> interessenScreenPump(
  WidgetTester tester, {
  required FakeFindYourMatchService service,
  double scale = 1.0,
  List<Override> overrides = const <Override>[],
}) async {
  final router = interessenScreenRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(FakeLocalStorage()),
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
  await pumpFrames(tester);
  return service;
}

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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

late FakeSupabaseServer server;
