// Der Passkey-Login und die kleinen Schalter im Login-Screen.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/login_screen.dart 68 offene Zeilen. Der Screen selbst
// (Anmeldung, Registrierung, Sicherheitscheck, Fehlertexte) ist
// getestet - offen war der Passkey-Weg und das Auge fuer das Passwort.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Passkey-Login meldet dem Nutzer den Grund (nicht "irgendwas
//     ging schief"),
//   * das Auge zeigt das Passwort im Klartext (und wieder nicht),
//   * der Schalter "angemeldet bleiben" wird gemerkt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/auth/login_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

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
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

/// Der Keystore ohne Plugin.
class _Keystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();

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
  });

  setUp(() {
    server.pfade.clear();
    server.fehlerAntworten.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// Baut den Login-Screen.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.login,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginScreen(),
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Der Passkey-Login', () {
    testWidgets('er meldet den Grund (nicht nur "Fehler")', (tester) async {
      await zeigeScreen(tester);

      final knopf = find.text(L10n.tWithoutContext('auth.passkey'));
      expect(knopf, findsOneWidget);
      await tester.tap(knopf);
      await tester.pump();
      // Der native Dialog (Passkeys-Plugin) gibt es im Test nicht - der
      // Aufruf braucht deshalb echte Zeit, bis der Fehler zurueckkommt.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.byType(SnackBar),
        findsWidgets,
        reason:
            'Der Nutzer muss erfahren, WARUM der Passkey-Login nicht klappt - '
            'sonst denkt er, die App sei kaputt.',
      );
    });
  });

  group('Die kleinen Schalter', () {
    testWidgets('das Auge zeigt das Passwort im Klartext', (tester) async {
      await zeigeScreen(tester);

      final felder = find.byType(TextFormField);
      await tester.enterText(felder.at(1), 'Passwort123!');
      await tester.pump();

      // VORHER: Das Passwort ist verdeckt. (Das TextFormField gibt das
      // nicht weiter - der Blick muss auf das innere TextField.)
      bool verdeckt() => tester
          .widget<TextField>(
            find.descendant(of: felder.at(1), matching: find.byType(TextField)),
          )
          .obscureText;
      expect(verdeckt(), isTrue);

      // DAS AUGE: Es schaltet um. (Solange das Passwort verdeckt ist,
      // zeigt das Symbol "visibility_off".)
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        verdeckt(),
        isFalse,
        reason:
            'Der Nutzer muss pruefen koennen, was er getippt hat - besonders '
            'auf dem Handy mit der kleinen Tastatur.',
      );
    });

    testWidgets('"angemeldet bleiben" wird gemerkt', (tester) async {
      await zeigeScreen(tester);

      final schalter = find.byType(CheckboxListTile);
      expect(schalter, findsWidgets);
      final vorher = tester.widget<CheckboxListTile>(schalter.first).value;

      await tester.ensureVisible(schalter.first);
      await tester.pump();
      await tester.tap(schalter.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('keep_logged_in'),
        !(vorher ?? false),
        reason:
            'Die Entscheidung muss gemerkt werden - sonst waere der Nutzer '
            'nach jedem Neustart wieder ausgeloggt.',
      );
    });
  });
}
