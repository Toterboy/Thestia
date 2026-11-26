// Der Kinderschutz-Stand in den Einstellungen (bisher ungetestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte für
// lib/screens/settings/settings_screen.dart 351 offene Zeilen.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Einwilligung steht das drin (nicht "nichts"),
//   * mit Einwilligung steht der aktive Stand,
//   * ein Lesefehler wird als Fehler gemeldet - nicht als "keine
//     Aufsicht" (das wäre eine falsche Aussage über die Aufsicht),
//   * der Eintrag fährt in den Elternbereich.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/verification/guardian_status.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

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

/// Der Keystore ohne Plugin.
class _FakeSecureProfileStore extends SecureProfileStore {
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
    // DIE ZEITZONE: Der Dienst meldet sie dem Server (die elterliche
    // Nutzungszeit läuft in der lokalen Zeit) - ohne den Mock bleibt
    // der Abruf hängen und der Stand kommt nie an.
    mockZeitzone();

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

    // HIVE: die verschlüsselten Schlüssel (Signal-Protokoll) liegen in
    // Hive-Boxen - ohne initialisierten Hive schlägt der Aufbau fehl.
    final tempDir = await Directory.systemTemp.createTemp('thesia_guardian');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
    server.rpcAntworten.clear();
    server.antwortetMitFehler = false;
  });

  /// Baut die Einstellungen mit dem angegebenen Kinderschutz-Stand.
  ///
  /// Der Stand kommt vom Server (RPC `get_my_guardian_status`) - so wird
  /// der ganze Weg geprüft, nicht nur die Anzeige.
  Future<void> zeigeEinstellungen(
    WidgetTester tester,
    GuardianStatus status,
  ) async {
    server.rpcAntworten['get_my_guardian_status'] = <String, dynamic>{
      'consentState': status.consentState,
      'status': status.status,
      'supervised': status.supervised,
    };
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.guardianSettings,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Elternbereich'))),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final storage = _FakeLocalStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(
            _FakeSecureProfileStore(),
          ),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(
              ref.watch(localStorageProvider),
              ref.watch(secureProfileStoreProvider),
            );
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
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Scrollt zu einem Text (der Bildschirm ist eine lange Liste).
  ///
  /// FEINE Schritte: der Kinderschutz-Eintrag steht knapp unter dem
  /// Datenschutz-Block. Mit großen Schritten springt man darüber
  /// hinweg - und der Eintrag wird dann nicht mehr gebaut.
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    if (ziel.evaluate().isNotEmpty) return;
    for (var i = 0; i < 60 && ziel.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      // Zwischen den Schritten dem Status Zeit geben (er kommt vom
      // Server) - sonst scrollt man an ihm vorbei.
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('Der Kinderschutz-Stand', () {
    testWidgets('ohne Einwilligung steht das drin', (tester) async {
      await zeigeEinstellungen(
        tester,
        const GuardianStatus(consentState: 'none', loaded: true),
      );

      await scrolleZu(tester, L10n.tWithoutContext('guardian.noConsentTitle'));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.noConsentTitle')),
        findsOneWidget,
      );
    });

    testWidgets('mit Einwilligung steht der aktive Stand', (tester) async {
      await zeigeEinstellungen(
        tester,
        const GuardianStatus(
          consentState: 'granted',
          status: 'active',
          loaded: true,
        ),
      );

      await scrolleZu(tester, L10n.tWithoutContext('guardian.activeTitle'));

      expect(
        find.text(L10n.tWithoutContext('guardian.activeTitle')),
        findsOneWidget,
      );
    });

    testWidgets('ein Lesefehler wird als Fehler gemeldet', (tester) async {
      // Der Server schweigt - die App darf daraus NICHT "keine Aufsicht"
      // machen (das wäre eine falsche Aussage über die Aufsicht).
      server.antwortetMitFehler = true;
      await zeigeEinstellungen(
        tester,
        const GuardianStatus(consentState: 'none', loaded: true),
      );

      await scrolleZu(tester, L10n.tWithoutContext('guardian.loadErrorTitle'));

      expect(
        find.text(L10n.tWithoutContext('guardian.loadErrorTitle')),
        findsOneWidget,
        reason:
            'Ein Fehler beim Lesen darf nicht wie "keine Aufsicht" '
            'aussehen - das waere eine falsche Aussage.',
      );
    });

    testWidgets('der Eintrag fuehrt in den Elternbereich', (tester) async {
      await zeigeEinstellungen(
        tester,
        const GuardianStatus(consentState: 'none', loaded: true),
      );

      await scrolleZu(tester, L10n.tWithoutContext('guardian.pinTitle'));
      await tester.tap(find.text(L10n.tWithoutContext('guardian.pinTitle')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(tester.takeException(), isNull);
      expect(find.text('Elternbereich'), findsOneWidget);
    });
  });
}
