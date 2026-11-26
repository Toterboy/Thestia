// Der Scan-Weg des QR-Scanners (Kamera statt Code eingeben).
//
// ANLASS (20.11.2026): Die Coverage-Messung zeigte für
// lib/screens/qr/qr_scan_screen.dart 106 offene Zeilen. Der manuelle Weg
// (Code eingeben) war getestet - der Weg über die Kamera nicht.
//
// DER WEG: `mobile_scanner` hat eine austauschbare Plattform-Schnittstelle.
// Der Test schiebt selbst einen erkannten Barcode hinein, so wie es die
// Kamera tun würde - ohne echte Kamera und ohne Änderung am Produkt.
//
// DER GRUND: Ein QR-Code kommt von einem FREMDEN Gerät. Die App muss
//   * fremde Formate abweisen (und das sagen),
//   * die Peer-ID als UUID prüfen (Audit M1 - sonst wäre eine
//     Pfad-/Filter-Injection möglich),
//   * eine gültige ID zum Server schicken (der Funke entsteht).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/screens/qr/qr_scan_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Scanner-Ersatz: liefert einen Barcode-Stream, in den der Test
/// schieben kann.
class FakeScanner extends MobileScannerPlatform {
  FakeScanner();

  final StreamController<BarcodeCapture?> _barcodes =
      StreamController<BarcodeCapture?>.broadcast();

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream<TorchState>.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream<double>.empty();

  @override
  Widget buildCameraView() => const SizedBox.shrink();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  /// Schiebt einen erkannten Barcode hinein (wie die Kamera).
  void erkenne(String wert) {
    _barcodes.add(BarcodeCapture(barcodes: <Barcode>[Barcode(rawValue: wert)]));
  }

  Future<void> schliessen() => _barcodes.close();
}

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
  late MobileScannerPlatform original;

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
    original = MobileScannerPlatform.instance;
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
  });

  tearDown(() {
    MobileScannerPlatform.instance = original;
  });

  /// Baut den Screen und schaltet auf die Kamera um.
  Future<FakeScanner> zeigeKamera(WidgetTester tester) async {
    final scanner = FakeScanner();
    MobileScannerPlatform.instance = scanner;
    addTearDown(() => scanner.schliessen());

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/qr',
      routes: [
        GoRoute(path: '/qr', builder: (context, state) => const QrScanScreen()),
        GoRoute(
          path: '/interessen',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Funken'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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

    await tester.tap(find.text(L10n.tWithoutContext('qr.scanTitle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return scanner;
  }

  group('Der Scan-Weg', () {
    testWidgets('ein fremdes Format wird abgewiesen', (tester) async {
      final scanner = await zeigeKamera(tester);
      scanner.erkenne('https://example.com/kein-thestia-code');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('qr.invalidCode')),
        findsOneWidget,
        reason:
            'Ein fremder QR-Code muss erkannt und gemeldet werden - der '
            'Nutzer soll nicht glauben, er habe jemanden gescannt.',
      );
      expect(
        server.rpcAufrufe.any((c) => c['funktion'] == 'like_user'),
        isFalse,
      );
    });

    testWidgets('eine gueltige ID wird zum Server geschickt', (tester) async {
      server.rpcAntworten['find_user_by_code'] = <dynamic>[];
      final scanner = await zeigeKamera(tester);
      scanner.erkenne('thestia://user/11111111-2222-3333-4444-555555555555');
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      // DER WEG: Die ID steht schon im QR-Code - der Scan ruft direkt
      // `like_user` (ohne vorherige Codesuche wie beim manuellen Weg).
      expect(
        server.rpcAufrufe.any((c) => c['funktion'] == 'like_user'),
        isTrue,
        reason:
            'Der gescannte Nutzer muss beim Server gesucht werden - '
            'sonst entsteht kein Funke.',
      );
    });
  });
}
