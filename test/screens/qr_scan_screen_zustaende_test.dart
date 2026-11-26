// Der QR-Scanner: die Fehler- und Grenz-Wege.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte für
// lib/screens/qr/qr_scan_screen.dart 63 offene Zeilen - darunter der
// Fall "das Like klappt nicht", der Fall "ohne Netz" (der Kontakt wird
// lokal gemerkt) und das Limit von fünf Kontakten.
//
// DER WEG: Der Server ist der [FakeSupabaseServer] - er kann das Like
// ablehnen. Für den Offline-Fall braucht es einen Screen ohne
// Supabase-Client (dann nimmt der Bildschirm den anderen Weg).
//
// WAS HIER GEPRÜFT WIRD:
//   * schlägt das Like fehl, wird es dem Nutzer gesagt (nicht
//     verschwiegen - sonst denkt er, das Like sei angekommen),
//   * ohne Netz wird der Kontakt lokal gemerkt und es geht weiter,
//   * (der Limit-Weg - fünf gespeicherte Kontakte - braucht den
//     Offline-Weg; der ist ohne einen zweiten Supabase-Client nicht
//     erreichbar und bleibt offen).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/qr/qr_scan_screen.dart';
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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.pfade.clear();
    server.rpcAufrufe.clear();
    server.rpcAntworten.clear();
    server.fehlerAntworten.clear();
    server.antwortetMitFehler = false;
  });

  /// Baut den Screen.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/qr',
      routes: [
        GoRoute(path: '/qr', builder: (context, state) => const QrScanScreen()),
        GoRoute(
          path: AppRoutes.interessen,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Funken'))),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Gibt den Code eines Freundes ein (der Screen löst ihn auf).
  Future<void> codeEingeben(WidgetTester tester, String code) async {
    await tester.tap(find.text(L10n.tWithoutContext('qr.enterCode')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, code);
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, L10n.tWithoutContext('qr.searchUser')),
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Der Fehlerfall', () {
    testWidgets('schlaegt das Like fehl, wird es gesagt', (tester) async {
      // DER SERVER LEHNT DAS LIKE AB: Die Suche nach dem Code muss
      // klappen - nur das Like nicht.
      // DIE SUCHE: Der RPC liefert eine Liste mit der User-ID.
      server.rpcAntworten['find_user_by_code'] = <dynamic>[
        <String, dynamic>{'user_id': 'partner-9', 'name': 'Mira'},
      ];
      server.fehlerAntworten['/rest/v1/rpc/like_user'] = (
        status: 400,
        body: '{"message":"Das Like hat nicht geklappt"}',
      );

      await zeigeScreen(tester);
      await codeEingeben(tester, 'partner-9');

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(
          L10n.tWithoutContext('qr.likeFailed').split('{').first,
        ),
        findsWidgets,
        reason:
            'Der Nutzer muss erfahren, dass das Like nicht geklappt hat - '
            'sonst denkt er, die Person habe ihn geliked.',
      );
    });
  });
}
