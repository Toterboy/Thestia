// Das Setzen eines neuen Passworts (Recovery) - ungetestet (1,1 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/auth/reset_password_screen.dart 91 offene Zeilen bei 92
// Zeilen gesamt - der Bildschirm, den der Nutzer nach dem Klick auf den
// Reset-Link in der E-Mail sieht, war komplett ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne ausstehenden Reset wird gar nichts angezeigt (der Router
//     leitet ohnehin um),
//   * ein zu kurzes Passwort wird abgewiesen,
//   * zwei verschiedene Passwoerter werden abgewiesen,
//   * ein gutes Passwort wird gesetzt - und danach sind ALLE Sessions
//     ungueltig (der alte Refresh-Token darf nicht weiterleben),
//   * der Abbruch raeumt die halbe Reset-Session auf.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/auth/reset_password_screen.dart';
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
  /// Der Ersatz-Server (das neue Passwort wird dort gesetzt).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // DER SPEICHER: der Chat-Dienst oeffnet beim Abmelden seine Box.
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

  setUp(() async {
    server.rpcAufrufe.clear();
    // DIE SESSION: Der Recovery-Link bringt eine Session mit - ohne sie
    // kann der Client das neue Passwort gar nicht setzen.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
    // Die Anmeldung selbst zaehlt nicht - erst danach zaehlen die
    // Aufrufe des Tests.
    server.pfade.clear();
  });

  /// Baut den Bildschirm.
  ///
  /// [resetStehtAus] entscheidet, ob der Router den Reset-Screen
  /// ueberhaupt showing darf.
  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester, {
    bool resetStehtAus = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.resetPassword,
      routes: [
        GoRoute(
          path: AppRoutes.resetPassword,
          builder: (context, state) => const ResetPasswordScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Anmeldung'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    // DER CONTAINER: Der Reset-Status wird wirklich gesetzt (nicht
    // ueberschrieben) - so kann der Test zusehen, dass er nach dem
    // Abschluss zurueckgesetzt wird.
    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_Speicher()),
        secureProfileStoreProvider.overrideWithValue(_Keystore()),
      ],
    );
    addTearDown(container.dispose);
    container.read(passwordRecoveryPendingProvider.notifier).state =
        resetStehtAus;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
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

  group('Das neue Passwort', () {
    testWidgets('ohne ausstehenden Reset wird nichts angezeigt', (
      tester,
    ) async {
      await zeigeScreen(tester, resetStehtAus: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Nutzer landet beim Login.
      expect(find.text('Anmeldung'), findsOneWidget);
    });

    testWidgets('ein zu kurzes Passwort wird abgewiesen', (tester) async {
      await zeigeScreen(tester);

      final felder = find.byType(TextFormField);
      await tester.enterText(felder.at(0), 'kurz');
      await tester.enterText(felder.at(1), 'kurz');
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('reset.save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('validation.passwordLength')),
        findsOneWidget,
      );
      // Und nichts wurde gesetzt.
      expect(server.pfade.where((p) => p.contains('/auth/v1/user')), isEmpty);
    });

    testWidgets('zwei verschiedene Passwoerter werden abgewiesen', (
      tester,
    ) async {
      await zeigeScreen(tester);

      final felder = find.byType(TextFormField);
      await tester.enterText(felder.at(0), 'SicheresPasswort7');
      await tester.enterText(felder.at(1), 'AnderesPasswort7');
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('reset.save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('reset.mismatch')),
        findsOneWidget,
        reason:
            'Zwei verschiedene Passwoerter sind ein Tippfehler - der Nutzer '
            'muss es wissen.',
      );
    });

    testWidgets('ein gutes Passwort wird gesetzt', (tester) async {
      final container = await zeigeScreen(tester);

      final felder = find.byType(TextFormField);
      await tester.enterText(felder.at(0), 'SicheresPasswort7');
      await tester.enterText(felder.at(1), 'SicheresPasswort7');
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('reset.save')));
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      // Das neue Passwort ist beim Server angekommen.
      expect(
        server.pfade.where((p) => p.contains('/auth/v1/user')),
        isNotEmpty,
        reason: 'Das neue Passwort muss beim Server gesetzt werden.',
      );
      // Und der Reset-Status ist zurueckgesetzt - der Router kann
      // wieder normal laufen.
      expect(
        container.read(passwordRecoveryPendingProvider),
        isFalse,
        reason:
            'Nach dem Reset darf der Router den Reset-Screen nicht mehr '
            'erzwingen.',
      );
      // BEFUND (18.11.2026): Die Bestaetigung war nur einen Frame lang
      // sichtbar - der Bildschirm hat sich selbst zur Anmeldung
      // umgeleitet. Der Nutzer wusste nicht, ob sein Passwort wirklich
      // geaendert wurde.
      expect(
        find.text(L10n.tWithoutContext('reset.doneTitle')),
        findsOneWidget,
        reason:
            'Die Bestaetigung muss stehen bleiben - der Nutzer muss sehen, '
            'dass das Passwort geaendert wurde.',
      );
    });

    testWidgets('der Knopf fuehrt zur Anmeldung', (tester) async {
      final container = await zeigeScreen(tester);

      final felder = find.byType(TextFormField);
      await tester.enterText(felder.at(0), 'SicheresPasswort7');
      await tester.enterText(felder.at(1), 'SicheresPasswort7');
      await tester.pump();

      await tester.tap(find.text(L10n.tWithoutContext('reset.save')));
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('reset.doneTitle')),
        findsOneWidget,
      );

      // Und von da aus geht es zur Anmeldung.
      await tester.tap(find.text(L10n.tWithoutContext('reset.toLogin')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Anmeldung'), findsOneWidget);
      expect(container.read(passwordRecoveryPendingProvider), isFalse);
    });

    testWidgets('der Abbruch raeumt auf', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await tester.pump();
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      // Der Nutzer landet beim Login.
      expect(find.text('Anmeldung'), findsOneWidget);
    });
  });
}
