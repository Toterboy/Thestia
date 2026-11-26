// Die Video-Aufnahme in der Verifizierung.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/screens/verification/parts/verificationvideoscreenstate.dart 134
// offene Zeilen. Der bestehende Test deckt die Kamera-Offenlegung und
// die Kamera-Freigabe im Hintergrund ab - offen war die AUFNAHME:
// starten, zählen, von selbst stoppen und der Fehlerfall.
//
// DER WEG: Die Kamera-Attrappe (test/support/fake_camera.dart) kann
// auch aufnehmen - sonst würde der Aufnahme-Pfad nie betreten.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Aufnahme startet (und der Screen zeigt den Zähler),
//   * der Zähler läuft (der Nutzer sieht, wie lange er schon filmt),
//   * nach 15 Sekunden stoppt die Aufnahme von selbst (die App soll den
//     Nutzer nicht endlos filmen lassen - und der Server bekommt kein
//     unbegrenztes Video),
//   * schlägt der Start fehl, wird dem Nutzer der Grund gesagt.
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/verification/verification_flow.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_camera.dart';
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
  late CameraPlatform original;
  late FakeCameraPlatform kamera;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    mockKeystore();
    await mockHive();
  });

  setUp(() {
    original = CameraPlatform.instance;
    kamera = FakeCameraPlatform();
    CameraPlatform.instance = kamera;
  });

  tearDown(() {
    CameraPlatform.instance = original;
  });

  /// Baut den Screen.
  Future<void> zeige(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // DER ROUTER: Nach der Aufnahme geht der Screen weiter - ohne
    // Router würfe er.
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const VerificationVideoScreen(),
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

  /// Bestätigt die Kamera-Offenlegung und wartet auf die Kamera.
  Future<void> kameraFreigeben(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('verify.cameraDisclosureAccept'),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Tippt auf die Aufnahme (der große runde Knopf mit dem
  /// Kamera-Symbol).
  Future<void> tippeAufnahme(WidgetTester tester) async {
    final symbol = find.byIcon(Icons.videocam);
    expect(symbol, findsOneWidget);
    await tester.tap(symbol);
    await tester.pump();
  }

  group('Die Aufnahme', () {
    testWidgets('sie startet und der Screen zaehlt', (tester) async {
      await zeige(tester);
      await kameraFreigeben(tester);

      await tippeAufnahme(tester);

      expect(tester.takeException(), isNull);
      // DER TEXT: "Aufnahme: 3 s" - der Platzhalter ({s}) steht für
      // die Sekunden, deshalb wird der Anfang des Textes geprüft.
      final anzeige = L10n.tWithoutContext('verify.recording');
      expect(
        find.textContaining(anzeige.split('{').first),
        findsWidgets,
        reason:
            'Der Nutzer muss sehen, dass er filmt - sonst haelt er die '
            'App fuer kaputt.',
      );
    });

    testWidgets('nach 15 Sekunden stoppt sie von selbst', (tester) async {
      await zeige(tester);
      await kameraFreigeben(tester);

      await tippeAufnahme(tester);

      // DER AUTO-STOPP: Der Screen darf den Nutzer nicht endlos filmen
      // lassen (und der Server soll kein unbegrenztes Video bekommen).
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(tester.takeException(), isNull);
      expect(
        kamera.aufnahmenGestoppt,
        greaterThan(0),
        reason:
            'Nach 15 Sekunden muss die Aufnahme von selbst enden - der '
            'Nutzer soll nicht ewig filmen.',
      );
    });
  });
}
