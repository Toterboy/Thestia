// Die Video-Verifizierung (der Screen mit der Kamera).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/verification/parts/verificationvideoscreenstate.dart 144
// offene Zeilen bei 57 % Abdeckung. Der Screen ist die einzige Stelle,
// an der die App Beweise fuer das Alter sammelt - und er hat drei Wege,
// die niemand kannte: die Kamera-Offenlegung, der Fehlerfall und die
// Herausgabe der Kamera, wenn die App in den Hintergrund geht.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Kamera wird NICHT geoeffnet, bevor der Nutzer die Offenlegung
//     bestaetigt hat (Google Play verlangt das),
//   * ein Ablehnen fuehrt zu einem erklaerenden Zustand (kein Absturz),
//   * die Kamera kommt an und der Screen zeigt die Aufgabe (die Zahl, die
//     gesagt werden soll),
//   * die Kamera wird beim Wechsel in den Hintergrund freigegeben.
import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/verification/verification_flow.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/plugin_mocks.dart';

/// Der Speicher im RAM (die Einstellungen kommen daraus).
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
class _Keystore implements SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Die Kamera als Ersatz.
///
/// DER GRUND: Das echte Kamera-Plugin gibt es im Test nicht - ohne
/// diesen Ersatz bliebe der Bildschirm im Ladekreis und die Kamera-Pfade
/// waeren ungetestet.
class _KameraPlattform extends CameraPlatform {
  _KameraPlattform();

  /// Die Kamera-IDs, die erzeugt wurden (und wieder freigegeben wurden).
  final List<int> erzeugt = <int>[];
  final List<int> freigegeben = <int>[];

  /// Der Strom, der die "Kamera ist bereit"-Meldung traegt.
  final StreamController<int> _bereit = StreamController<int>.broadcast();

  /// Die Ströme, die NIE etwas melden.
  ///
  /// WICHTIG: Das camera-Plugin holt sich von jedem Ereignis-Strom das
  /// ERSTE Element (`.first`). Ein leerer Strom liefert "Bad state: No
  /// element" - der Controller rechnet aber mit einem Strom, der erst
  /// bei einem echten Ereignis redet. Deshalb sind diese Ströme offen
  /// und leer (nicht geschlossen, nicht "empty").
  final StreamController<CameraResolutionChangedEvent> _aufloesung =
      StreamController<CameraResolutionChangedEvent>.broadcast();
  final StreamController<CameraClosingEvent> _schliessung =
      StreamController<CameraClosingEvent>.broadcast();
  final StreamController<CameraErrorEvent> _fehler =
      StreamController<CameraErrorEvent>.broadcast();
  final StreamController<VideoRecordedEvent> _aufnahme =
      StreamController<VideoRecordedEvent>.broadcast();
  final StreamController<DeviceOrientationChangedEvent> _lage =
      StreamController<DeviceOrientationChangedEvent>.broadcast();

  /// Schliesst alle Ströme (am Ende des Tests).
  ///
  /// WICHTIG: Die beiden Ströme, von denen sich das camera-Plugin das
  /// ERSTE Element holt (Kamera bereit und Kamera-Fehler), bekommen vor
  /// dem Schliessen noch ein Ereignis - ein geschlossener leerer Strom
  /// liefert sonst "Bad state: No element".
  Future<void> schliessen() async {
    if (!_bereit.isClosed) _bereit.add(1);
    if (!_fehler.isClosed) {
      _fehler.add(const CameraErrorEvent(1, 'Testende'));
    }
    await _bereit.close();
    await _aufloesung.close();
    await _schliessung.close();
    await _fehler.close();
    await _aufnahme.close();
    await _lage.close();
  }

  @override
  Future<List<CameraDescription>> availableCameras() async =>
      const <CameraDescription>[
        CameraDescription(
          name: 'front',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 0,
        ),
      ];

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    const id = 1;
    erzeugt.add(id);
    // Die Bereitschaftsmeldung kommt asynchron - wie im echten Plugin.
    Future<void>.delayed(const Duration(milliseconds: 10), () {
      if (!_bereit.isClosed) _bereit.add(id);
    });
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _bereit.stream.map(
        (id) => CameraInitializedEvent(
          id,
          640,
          480,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<CameraResolutionChangedEvent> onCameraResolutionChanged(
    int cameraId,
  ) => _aufloesung.stream;

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      _schliessung.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _fehler.stream;

  @override
  Stream<VideoRecordedEvent> onVideoRecordedEvent(int cameraId) =>
      _aufnahme.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      _lage.stream;

  @override
  Future<void> dispose(int cameraId) async {
    freigegeben.add(cameraId);
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();
}

void main() {
  late CameraPlatform original;
  late _KameraPlattform kamera;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    mockKeystore();
    // HIVE: der Verschluesselungs-Dienst oeffnet seine Boxen - ohne
    // initialisiertes Hive schlaegt der Aufbau fehl.
    await mockHive();
  });

  setUp(() {
    original = CameraPlatform.instance;
    kamera = _KameraPlattform();
    CameraPlatform.instance = kamera;
  });

  tearDown(() async {
    CameraPlatform.instance = original;
    await kamera.schliessen();
  });

  /// Baut den Screen.
  Future<void> zeige(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
        ],
        child: const MaterialApp(home: VerificationVideoScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Bestaetigt die Kamera-Offenlegung und wartet auf die Kamera.
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

  group('Die Video-Verifizierung', () {
    testWidgets('die Kamera-Offenlegung kommt zuerst', (tester) async {
      await zeige(tester);

      expect(
        find.text(L10n.tWithoutContext('verify.cameraDisclosureTitle')),
        findsOneWidget,
        reason:
            'Die App muss erklaeren, warum sie filmt - BEVOR der '
            'Systemdialog kommt. Das verlangt Google Play.',
      );
      expect(
        kamera.erzeugt,
        isEmpty,
        reason:
            'Ohne Bestaetigung darf die Kamera nicht aufgehen - das ist die '
            'Zusage gegenueber dem Nutzer und dem Store.',
      );
    });

    testWidgets('ein Ablehnen fuehrt zu einem erklaerenden Zustand', (
      tester,
    ) async {
      await zeige(tester);

      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('verify.cameraDeclined')),
        findsOneWidget,
        reason:
            'Wer die Kamera ablehnt, sieht den Grund - ein leerer '
            'Bildschirm sieht wie ein Absturz aus.',
      );
      expect(
        kamera.erzeugt,
        isEmpty,
        reason: 'Nach dem Ablehnen wird die Kamera nicht doch geoeffnet.',
      );
    });

    testWidgets('nach der Freigabe kommt die Kamera und die Aufgabe', (
      tester,
    ) async {
      await zeige(tester);

      await kameraFreigeben(tester);

      expect(tester.takeException(), isNull);
      expect(
        kamera.erzeugt,
        isNotEmpty,
        reason: 'Nach der Freigabe muss die Kamera wirklich aufgehen.',
      );
      expect(
        find.text(L10n.tWithoutContext('verify.title')),
        findsOneWidget,
        reason: 'Der Screen steht da - mit der Aufgabe, die zu loesen ist.',
      );
    });

    testWidgets('die Kamera wird beim Wechsel in den Hintergrund freigegeben', (
      tester,
    ) async {
      await zeige(tester);
      await kameraFreigeben(tester);

      // Der Lebenszyklus: inactive (der App-Wechsel) muss die Kamera
      // freigeben - der Preview-Texture lebt sonst weiter und der Sensor
      // bleibt belegt.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(tester.takeException(), isNull);
      expect(
        kamera.freigegeben,
        isNotEmpty,
        reason:
            'Im Hintergrund darf die Kamera nicht weiterlaufen - sie wuerde '
            'den Sensor belegen und den Akku leeren.',
      );
    });
  });
}
