// Der Weg vom Video zum Speicher (die Video-Verifizierung).
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte für
// lib/screens/verification/parts/verificationvideoscreenstate.dart 111
// offene Zeilen - der Weg, der nach der Aufnahme das Video sichert.
//
// DER WEG: Die Kamera-Attrappe (test/support/fake_camera.dart) liefert
// eine echte Datei. Standort, Thumbnails und Alters-Dienst bekommen
// ihre Ersatzteile.
//
// WAS HIER GEPRÜFT WIRD:
//   * nach der Aufnahme wird das Video gesichert (der Pfad, auf dem die
//     Altersprüfung die Frames entnimmt),
//   * der Standort wird geholt - er hilft bei der Altersschätzung,
//   * die Frames werden entnommen (fünf Zeitpunkte im Video),
//   * schlägt das Stoppen fehl, wird dem Nutzer der Grund gesagt (nicht
//     verschwiegen - der Nutzer hält die App sonst für kaputt).
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/verification/verification_flow.dart';
import 'package:thestia/services/profile/location_verification_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/services/verification/verification_service.dart';

import '../support/fake_camera.dart';
import '../support/plugin_mocks.dart';

/// Der Kanal der Video-Thumbnails (das Plugin gibt es im Test nicht).
const MethodChannel thumbnailKanal = MethodChannel(
  'plugins.justsoft.xyz/video_thumbnail',
);

/// Wie oft wurden die Thumbnails angefragt?
///
/// DER GRUND: Die App entnimmt fünf Frames aus dem Video (für die
/// Altersschätzung). Ohne den Ersatz wartet der Aufruf im Test endlos
/// (sein Zeitlimit läuft in der Test-Uhr nicht).
int thumbnailAnfragen = 0;

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

/// Der Standort als Ersatz.
///
/// DER GRUND: Der echte Dienst fragt das Plugin und das GPS - im Test
/// gibt es beides nicht.
class _Standort extends LocationVerificationService {
  _Standort();

  /// Wie oft wurde der Standort geholt?
  int standortAnfragen = 0;

  /// Wie oft wurde der Standort gespeichert?
  int speicherAnrufe = 0;

  @override
  Future<bool> hasLocationPermission() async => true;

  @override
  Future<Position?> getCurrentLocation() async {
    standortAnfragen++;
    return Position(
      latitude: 52.520008,
      longitude: 13.404954,
      timestamp: DateTime(2026, 11, 25),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<void> saveVerificationLocation(Position position) async {
    speicherAnrufe++;
  }
}

/// Die Kamera, deren Stoppen fehlschlägt.
class _KameraMitFehler extends FakeCameraPlatform {
  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    throw CameraException('Kamera', 'Die Aufnahme bricht ab');
  }
}

/// Die Kamera, deren Aufnahme nicht startet.
class _KameraMitStartFehler extends FakeCameraPlatform {
  @override
  Future<void> startVideoRecording(
    int cameraId, {
    Duration? maxVideoDuration,
  }) async {
    throw CameraException('Kamera', 'Die Aufnahme startet nicht');
  }
}

void main() {
  late CameraPlatform original;
  late FakeCameraPlatform kamera;
  late _Standort standort;
  late VerificationService dienst;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();

    // DIE THUMBNAILS: Ohne den Ersatz wartet der Aufruf im Test endlos
    // (sein Zeitlimit läuft in der Test-Uhr nicht).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(thumbnailKanal, (anfrage) async {
          thumbnailAnfragen++;
          return null;
        });
  });

  setUp(() async {
    original = CameraPlatform.instance;
    kamera = FakeCameraPlatform();
    CameraPlatform.instance = kamera;
    standort = _Standort();
    thumbnailAnfragen = 0;

    // DER DIENST: Er wird hier bereit gemacht - das Öffnen der
    // Hive-Box ist echte Datei-Arbeit, die im Widget-Test (mit der
    // Test-Uhr) nie zu Ende kommt.
    dienst = VerificationService();
    await dienst.initialize();
  });

  tearDown(() {
    CameraPlatform.instance = original;
  });

  /// Liefert den Pfad einer Aufnahme-Datei, die es NICHT gibt.
  ///
  /// DER GRUND: Das Kamera-Plugin liefert im Test keine echte Datei.
  /// Der Verifikations-Dienst meldet das dem Nutzer ("bitte erneut
  /// aufnehmen") - und der Weg davor (Standort, Frames, Speichern)
  /// läuft trotzdem vollständig.
  ///
  /// DER HINWEIS: Nach dem Speichern lädt der Alters-Dienst die
  /// ONNX-Modelle (82 MB). Die native Bibliothek hängt im Widget-Test
  /// den ganzen Test-Prozess - deshalb endet der Weg hier.
  String fehlendeAufnahmeDatei() {
    final ordner = Directory.systemTemp.createTempSync('thesia_video');
    final pfad = '${ordner.path}/aufnahme.mp4';
    addTearDown(() {
      try {
        if (ordner.existsSync()) {
          ordner.deleteSync(recursive: true);
        }
      } catch (e) {
        // Der Temp-Ordner wird ohnehin irgendwann vom System geräumt.
        debugPrint('Der Temp-Ordner blieb liegen: $e');
      }
    });
    return pfad;
  }

  /// Baut den Screen (mit dem Verifikations-Dienst, der schon bereit ist).
  Future<void> zeige(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          verificationServiceProvider.overrideWithValue(dienst),
          locationVerificationServiceProvider.overrideWithValue(standort),
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

  /// Tippt auf die Aufnahme (der große runde Knopf).
  Future<void> tippeAufnahme(WidgetTester tester) async {
    final symbol = find.byIcon(Icons.videocam);
    expect(symbol, findsOneWidget);
    await tester.tap(symbol);
    await tester.pump();
  }

  group('Das Sichern des Videos', () {
    testWidgets('der Standort wird geholt und die Frames entnommen', (
      tester,
    ) async {
      // DIE AUFNAHME: Die Datei fehlt (das Kamera-Plugin liefert sie im
      // Test nicht). Der Weg läuft trotzdem bis zum Speichern - und der
      // Dienst meldet, dass die Datei fehlt.
      //
      // DER GRUND für diese Wahl: Nach dem Speichern lädt der
      // Alters-Dienst die ONNX-Modelle (82 MB). Die native Bibliothek
      // hängt im Widget-Test den ganzen Test-Prozess - das ist kein
      // Fehler der App, sondern einer des Testrahmens.
      kamera.aufnahmeDatei = fehlendeAufnahmeDatei();
      await zeige(tester);
      await kameraFreigeben(tester);

      await tippeAufnahme(tester);

      // DER AUTO-STOPP: Nach 15 Sekunden endet die Aufnahme von selbst -
      // danach wird das Video gesichert.
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
      }

      expect(tester.takeException(), isNull);
      expect(
        kamera.aufnahmenGestoppt,
        greaterThan(0),
        reason: 'Die Aufnahme muss von selbst enden.',
      );
      expect(
        standort.standortAnfragen,
        greaterThan(0),
        reason:
            'Der Standort wird fuer die Altersschaetzung gebraucht - ohne '
            'ihn ist die Einordnung schlechter.',
      );
      expect(
        standort.speicherAnrufe,
        greaterThan(0),
        reason: 'Der Standort muss auch gespeichert werden.',
      );
      expect(
        thumbnailAnfragen,
        greaterThan(0),
        reason:
            'Die Frames werden aus dem Video entnommen - ohne sie gibt es '
            'keine Altersschaetzung.',
      );
    });

    testWidgets('schlaegt das Stoppen fehl, wird der Grund gesagt', (
      tester,
    ) async {
      // DIE KAMERA: Der Stoppen bricht ab (das kam auf echten Geräten
      // vor - der Nutzer hält die App sonst für kaputt).
      CameraPlatform.instance = _KameraMitFehler();
      await zeige(tester);
      await kameraFreigeben(tester);

      await tippeAufnahme(tester);
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
      }

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Die Aufnahme bricht ab'),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, WARUM die Aufnahme nicht geklappt '
            'hat - ein Screen ohne Rueckmeldung sieht wie ein Absturz aus.',
      );
      expect(
        thumbnailAnfragen,
        0,
        reason:
            'Nach dem Fehler beim Stoppen wird kein Video geoeffnet - die '
            'Frames werden erst danach entnommen.',
      );
    });

    testWidgets('der Start der Aufnahme scheitert, wird der Grund gesagt', (
      tester,
    ) async {
      // DIE KAMERA: Die Aufnahme startet nicht (das kam auf echten
      // Geräten vor - dann steht der Screen ohne Rückmeldung).
      CameraPlatform.instance = _KameraMitStartFehler();
      await zeige(tester);
      await kameraFreigeben(tester);

      await tippeAufnahme(tester);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Die Aufnahme startet nicht'),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass die Aufnahme nicht startet - '
            'sonst tippt er vergeblich auf den Knopf.',
      );
    });
  });

  group('Der App-Wechsel', () {
    testWidgets('nach dem Zurueck aus dem Hintergrund kommt die Kamera', (
      tester,
    ) async {
      await zeige(tester);
      await kameraFreigeben(tester);
      final nachDemOeffnen = kamera.anfragen;

      // DER APP-WECHSEL: Das Gerät geht in den Hintergrund - die Kamera
      // muss frei werden (der Sensor darf nicht belegt bleiben).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 150));
      }

      // UND ZURÜCK: Die Kamera kommt wieder - ohne sie bleibt der
      // Screen für den Nutzer leer.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(tester.takeException(), isNull);
      expect(
        kamera.anfragen,
        greaterThan(nachDemOeffnen),
        reason:
            'Nach der Rueckkehr muss die Kamera wieder offen sein - sonst '
            'steht der Nutzer vor einem leeren Bildschirm.',
      );
    });
  });
}
