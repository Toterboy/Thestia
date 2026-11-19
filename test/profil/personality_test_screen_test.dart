// Der Persoenlichkeitstest (letzter Schritt der Einrichtung) - bisher
// ungetestet (0,8 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/onboarding/personality_test_screen.dart 132 offene Zeilen
// bei 133 Zeilen gesamt.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Test stellt zehn Fragen mit je zwei Polen,
//   * erst wenn alle beantwortet sind, kann der Test abgeschlossen
//     werden (sonst waere das Ergebnis meaningless),
//   * das Ergebnis wird gespeichert (Profil UND Server - sonst waere der
//     Test nach der naechsten Neuinstallation wieder da),
//   * der Nutzer kann den Test auch ueberspringen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/onboarding/personality_test_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/widgets/buttons.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

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
  /// Der Ersatz-Server (die Setup-Flags gehen dorthin).
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
    server.schreibvorgaenge.clear();
    server.zeilen.clear();
  });

  /// Baut den Bildschirm.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/personality-test',
      routes: [
        GoRoute(
          path: '/personality-test',
          builder: (context, state) => const PersonalityTestScreen(),
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
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Beantwortet alle zehn Fragen (immer den ersten Pol).
  Future<void> beantworteAlle(WidgetTester tester) async {
    for (var i = 1; i <= 10; i++) {
      final antwort = find.text(L10n.tWithoutContext('pt.q${i}a'));
      await tester.scrollUntilVisible(
        antwort,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(antwort);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Wartet, bis der Server geantwortet hat.
  Future<void> warteAufServer(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Der Persoenlichkeitstest', () {
    testWidgets('die Fragen stehen da', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('pt.heading')), findsOneWidget);
      // Die Frage steht mit Nummer davor ("1. ...").
      expect(
        find.textContaining(L10n.tWithoutContext('pt.q1')),
        findsOneWidget,
      );
      expect(find.text(L10n.tWithoutContext('pt.q1a')), findsOneWidget);
      expect(find.byType(RadioListTile<int>), findsWidgets);
    });

    testWidgets('ohne Antworten kann man nicht abschliessen', (tester) async {
      await zeigeScreen(tester);

      final knopf = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(
        knopf.onPressed,
        isNull,
        reason:
            'Ein unvollstaendiger Test ergibt keinen Typ - der Knopf muss '
            'gesperrt sein.',
      );
    });

    testWidgets('nach zehn Antworten geht es weiter', (tester) async {
      await zeigeScreen(tester);
      await beantworteAlle(tester);

      final knopf = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(
        knopf.onPressed,
        isNotNull,
        reason: 'Sind alle Fragen beantwortet, darf der Test enden.',
      );
    });

    testWidgets('das Ergebnis wird gespeichert und gezeigt', (tester) async {
      await zeigeScreen(tester);
      await beantworteAlle(tester);

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      // Das Ergebnis steht im Dialog.
      expect(find.text(L10n.tWithoutContext('pt.doneTitle')), findsOneWidget);
      expect(
        find.textContaining('ESTP'),
        findsWidgets,
        reason:
            'Der ermittelte Typ muss dem Nutzer gezeigt werden - er sieht '
            'sonst nicht, was der Test ergab.',
      );
      // Und die Setup-Flags liegen beim Server (sonst erscheint der Test
      // nach der naechsten Neuinstallation wieder).
      expect(
        server.schreibvorgaenge.any((s) => s['tabelle'] == 'profiles'),
        isTrue,
        reason: 'Der Test-Stand muss beim Server gesichert werden.',
      );
    });

    testWidgets('ueberspringen geht auch', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.skip')),
      );
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      // Der Nutzer landet auf der Startseite.
      expect(find.text('Startseite'), findsOneWidget);
      // Und der Test gilt als erledigt.
      expect(
        server.schreibvorgaenge.any((s) => s['tabelle'] == 'profiles'),
        isTrue,
        reason:
            'Auch beim Ueberspringen muss der Stand beim Server gesichert '
            'werden - sonst erscheint der Test nach jedem Login wieder.',
      );
    });
  });
}
