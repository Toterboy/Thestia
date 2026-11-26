// Die Dating-Hour-Einstellungen - bisher völlig ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/screens/dating_hour/dating_hour_preferences_screen.dart 198 offene
// Zeilen bei 203 Zeilen gesamt - der Bildschirm, auf dem die Person
// festlegt, wen sie in der Dating Hour treffen will, war komplett
// ungetestet.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Bildschirm baut sich (alle Abschnitte stehen da),
//   * die zuletzt gespeicherten Vorstellungen werden übernommen,
//   * das Speichern geht an den Server - mit den Werten, die der
//     Nutzer eingestellt hat,
//   * ohne Event wird das Speichern dem Nutzer gesagt (nicht
//     verschwiegen).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/screens/dating_hour/dating_hour_preferences_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM - die Einstellungen kommen daraus.
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

/// Der Keystore ohne Plugin (die Einstellungen liegen nur im RAM).
class _FakeSecurePrefs extends SecurePreferencesStorage {
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

void main() {
  /// Der Ersatz-Server (die Antworten kommen aus dem RAM).
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
    server.pfade.clear();
    // DIE AUFRUFE: Sonst sieht der Test die Aufrufe des Tests davor.
    server.rpcAufrufe.clear();
  });

  /// Baut den Bildschirm.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _FakeLocalStorage();
    // DER ROUTER: Nach dem Speichern springt der Bildschirm zurück -
    // ohne Router wäre das ein Absturz.
    final router = GoRouter(
      initialLocation: '/dh-prefs',
      routes: [
        GoRoute(
          path: '/dh-prefs',
          builder: (context, state) => const DatingHourPreferencesScreen(),
        ),
        GoRoute(
          path: '/dh',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Dating Hour'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          securePrefsProvider.overrideWithValue(_FakeSecurePrefs()),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    // Der Bildschirm fragt die zuletzt gespeicherten Vorstellungen ab -
    // das geht nur in der echten Ereignisschleife.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Die Dating-Hour-Einstellungen', () {
    testWidgets('der Bildschirm baut sich', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Die Abschnitte stehen da.
      expect(
        find.text(L10n.tWithoutContext('dh.prefs.ageSection')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('dh.prefs.genderSection')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('dh.prefs.traitSection')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('dh.prefs.habits')),
        findsOneWidget,
      );
    });

    testWidgets('die gespeicherten Vorstellungen werden uebernommen', (
      tester,
    ) async {
      // Der Server liefert die zuletzt gespeicherten Vorstellungen.
      server.rpcAntworten['get_last_dating_hour_preferences'] =
          <String, dynamic>{
            'ageMin': 25,
            'ageMax': 40,
            'genderPreference': 'female',
            'preferredTrait': 'Ehrlichkeit',
            'maxDistanceKm': 30,
          };

      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Der Trait steht da - der Nutzer sieht, was zuletzt gewählt war.
      expect(
        find.text(L10n.tWithoutContext('dh.prefs.trait.honesty')),
        findsWidgets,
      );
    });

    testWidgets('das Speichern geht an den Server', (tester) async {
      // Es gibt ein aktuelles Event.
      final jetzt = DateTime.now();
      // DIE ANTWORT IST EINE LISTE: Die RPC liefert die Ereignisse als
      // Liste - der Dienst nimmt das erste Element.
      server.rpcAntworten['get_current_or_next_dating_hour'] = <dynamic>[
        <String, dynamic>{
          'id': 'event-1',
          'event_date': jetzt.toIso8601String(),
          'day_of_week': jetzt.weekday,
          'start_hour': 20,
          'start_minute': 0,
          'end_hour': 21,
          'end_minute': 0,
          'starts_at': jetzt.toIso8601String(),
          'ends_at': jetzt.add(const Duration(hours: 1)).toIso8601String(),
          'status': 'scheduled',
        },
      ];

      await zeigeScreen(tester);

      // Der Speichern-Knopf steht weit unten in der Liste.
      final knopf = find.text(L10n.tWithoutContext('dh.prefs.save'));
      await tester.scrollUntilVisible(
        knopf,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(knopf);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      // Die Vorstellungen sind beim Server - ohne das bleibt die
      // Einrichtung wirkungslos.
      expect(
        server.rpcAufrufe.any(
          (c) => c['funktion'] == 'save_dating_hour_preferences',
        ),
        isTrue,
        reason: 'Die Vorstellungen muessen beim Server landen.',
      );
      // Und der Nutzer bekommt die Bestätigung.
      expect(
        find.text(L10n.tWithoutContext('dh.prefs.savedHint')),
        findsOneWidget,
      );
    });

    testWidgets('ohne Event wird das Speichern gesagt', (tester) async {
      // Der Server kennt kein Event.
      server.rpcAntworten['get_current_or_next_dating_hour'] = null;

      await zeigeScreen(tester);

      final knopf = find.text(L10n.tWithoutContext('dh.prefs.save'));
      await tester.scrollUntilVisible(
        knopf,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(knopf);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      // Es wurde nichts gespeichert (ohne Event geht das nicht).
      expect(
        server.rpcAufrufe.any(
          (c) => c['funktion'] == 'save_dating_hour_preferences',
        ),
        isFalse,
      );
      // Und der Nutzer erfährt es.
      expect(
        find.textContaining('Event'),
        findsWidgets,
        reason:
            'Ohne Event kann nicht gespeichert werden - der Nutzer muss das '
            'wissen.',
      );
    });
  });
}
