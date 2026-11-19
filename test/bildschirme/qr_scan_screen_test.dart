// Der QR-Scanner (Kurzcode eingeben oder scannen) - bisher ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/qr/qr_scan_screen.dart 211 offene Zeilen bei 212 Zeilen
// gesamt - der Bildschirm, ueber den man jemanden per Kurzcode
// kennenlernt, war komplett ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * das Menue zeigt alle Wege (eigener Code, Kontaktkarte, scannen,
//     Code eingeben),
//   * ein zu kurzer Code wird abgewiesen (der Nutzer erfaehrt, wie lang
//     der Code sein muss),
//   * ein unbekannter Code wird gemeldet,
//   * der eigene Code wird abgewiesen (man kann sich nicht selbst
//     liken),
//   * ein gueltiger Code wird aufgeloest und gelikt.
//
// OHNE KAMERA: Der Scan-Weg braucht die Kamera - getestet wird der
// manuelle Weg (der Code eingeben).
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
import 'package:thestia/screens/qr/qr_scan_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

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
  /// Der Ersatz-Server (die Aufloesung kommt von dort).
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tippt auf "Code eingeben" und gibt [code] ein.
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
    // Die Anfrage geht an den Server - das braucht die echte Schleife.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Der QR-Scanner', () {
    testWidgets('das Menue zeigt alle Wege', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('qr.showMine')), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('contactShare.qrCardTitle')),
        findsOneWidget,
      );
      expect(find.text(L10n.tWithoutContext('qr.scanTitle')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('qr.enterCode')), findsOneWidget);
    });

    testWidgets('ein zu kurzer Code wird abgewiesen', (tester) async {
      await zeigeScreen(tester);
      await codeEingeben(tester, 'KURZ');

      expect(tester.takeException(), isNull);
      // Der Nutzer erfaehrt, dass der Code zu kurz ist.
      expect(
        find.text(L10n.tWithoutContext('qr.enterFullCode')),
        findsOneWidget,
      );
      // Und es wurde niemand gesucht.
      expect(
        server.rpcAufrufe.any((c) => c['funktion'] == 'find_user_by_code'),
        isFalse,
      );
    });

    testWidgets('ein unbekannter Code wird gemeldet', (tester) async {
      // Der Server kennt den Code nicht.
      server.rpcAntworten['find_user_by_code'] = <dynamic>[];

      await zeigeScreen(tester);
      await codeEingeben(tester, 'ABCDEFGH');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('qr.noUserFound')),
        findsOneWidget,
        reason:
            'Ein unbekannter Code muss gemeldet werden - sonst glaubt der '
            'Nutzer, der Code sei falsch eingegeben.',
      );
    });

    testWidgets('der eigene Code wird abgewiesen', (tester) async {
      // Der Code gehoert mir selbst.
      server.rpcAntworten['find_user_by_code'] = <dynamic>[
        <String, dynamic>{'user_id': 'ich'},
      ];

      await zeigeScreen(tester);
      await codeEingeben(tester, 'ABCDEFGH');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('qr.ownCode')),
        findsOneWidget,
        reason:
            'Man kann sich nicht selbst liken - der Nutzer muss das wissen.',
      );
      // Und es wurde kein Like gesetzt.
      expect(
        server.rpcAufrufe.any((c) => c['funktion'] == 'like_user'),
        isFalse,
      );
    });

    testWidgets('ein gueltiger Code wird aufgeloest und gelikt', (
      tester,
    ) async {
      // Der Code gehoert jemand anderem.
      server.rpcAntworten['find_user_by_code'] = <dynamic>[
        <String, dynamic>{'user_id': '11111111-2222-3333-4444-555555555555'},
      ];

      await zeigeScreen(tester);
      await codeEingeben(tester, 'ABCDEFGH');

      expect(tester.takeException(), isNull);
      // Der Like ist beim Server angekommen - sonst passiert gar nichts.
      expect(
        server.rpcAufrufe.any((c) => c['funktion'] == 'like_user'),
        isTrue,
        reason:
            'Der Like muss beim Server ankommen - der Funke entsteht '
            'sonst nicht.',
      );
      // Der Nutzer bekommt die Bestaetigung.
      expect(find.text(L10n.tWithoutContext('qr.likeSent')), findsOneWidget);
    });
  });
}
