// Die Kamera-Aufnahme fuer die Verifikation.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/verification/parts/verificationvideoscreenstate.dart 263
// offene Zeilen bei 334 gesamt - der Screen, auf dem der Nutzer sein
// Alter nachweisen muss, war ungetestet.
//
// DER WEG: Die Kamera spricht ueber `CameraPlatform.instance` - der
// Test zieht eine Attrappe ein (test/support/fake_camera.dart). Es
// braucht KEINE Aenderung am Produktionscode.
//
// DER GRUND: Dieser Screen ist der Nachweis fuer die Altersgrenze. Er
// muss
//   * die Kamera erst nach der ausdruecklichen Offenlegung oeffnen
//     (Play-Richtlinie CAMERA - die Kamera darf nicht ungefragt laufen),
//   * die Aufgabe klar zeigen (was der Nutzer tun soll),
//   * die Aufnahme starten und den Zustand anzeigen,
//   * und bei einem Kamera-Fehler einen erklärenden Zustand zeigen
//     (sonst sieht der Nutzer einen schwarzen Bildschirm).
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/verification/verification_flow.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_camera.dart';
import '../support/plugin_mocks.dart';

/// Minimaler Speicher im Arbeitsspeicher.
class _FakeLocalStorage implements LocalStorage {
  final map = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async => map[key] = value;

  @override
  Future<String?> getString(String key) async => map[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      map[key] = value ? 'true' : 'false';

  @override
  Future<bool?> getBool(String key) async => map[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async => map[key] = '$value';

  @override
  Future<int?> getInt(String key) async =>
      map[key] == null ? null : int.tryParse(map[key]!);

  @override
  Future<void> remove(String key) async => map.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCameraPlatform camera;
  late CameraPlatform original;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    original = CameraPlatform.instance;
    camera = FakeCameraPlatform();
    CameraPlatform.instance = camera;
  });

  tearDown(() {
    CameraPlatform.instance = original;
    // DER KANAL BLEIBT OFFEN: Das Schliessen wuerde das noch wartende
    // `.first` des Kamera-Controllers mit "No element" beenden - und der
    // Test wuerde an diesem Fehler scheitern, nicht an seinem eigent-
    // lichen Zweck.
  });

  Widget harness() => ProviderScope(
    overrides: [
      // localStorageProvider wirft UnimplementedError, wenn es nicht
      // gesetzt ist - die echte Einstellungskette laeuft darueber.
      localStorageProvider.overrideWithValue(_FakeLocalStorage()),
    ],
    child: const MaterialApp(home: VerificationVideoScreen()),
  );

  /// Bestaetigt die Kamera-Offenlegung (wenn sie erscheint).
  Future<void> bestaetigeOffenlegung(WidgetTester tester) async {
    final knopf = find.text(
      L10n.tWithoutContext('verify.cameraDisclosureAccept'),
    );
    if (knopf.evaluate().isEmpty) return;
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('Die Verifikationsaufnahme', () {
    testWidgets('nach der Offenlegung steht die Aufgabe da', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      await bestaetigeOffenlegung(tester);

      expect(tester.takeException(), isNull);
      expect(
        camera.anfragen,
        1,
        reason: 'Nach der Bestaetigung wird genau einmal gefragt.',
      );
      // Die Aufgabe steht da - der Nutzer muss wissen, was er tun soll.
      expect(
        find.text(L10n.tWithoutContext('verify.taskTitle')),
        findsOneWidget,
        reason:
            'Der Nutzer muss die Aufgabe sehen - ein schwarzer Bildschirm '
            'mit einem Knopf ist keine Anleitung.',
      );
      // Und der Aufnahme-Knopf ist da.
      expect(find.byIcon(Icons.videocam), findsOneWidget);
    });

    testWidgets('die Aufnahme startet und der Zustand wird angezeigt', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pump();
      await bestaetigeOffenlegung(tester);

      await tester.tap(find.byIcon(Icons.videocam));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(
        camera.aufnahmen,
        1,
        reason:
            'Der Aufnahme-Knopf muss die Kamera wirklich starten - sonst '
            'glaubt der Nutzer, er wuerde aufgenommen, und es passiert '
            'nichts.',
      );
      // Der Zustand wird angezeigt (mit der laufenden Uhr).
      expect(
        find.textContaining(
          L10n.tWithoutContext('verify.recording').split('{').first.trim(),
        ),
        findsWidgets,
        reason:
            'Der Nutzer muss sehen, dass gerade aufgenommen wird - und wie '
            'lange schon.',
      );
    });

    testWidgets('ohne Kamera gibt es einen erklärenden Zustand', (
      tester,
    ) async {
      // DER FALL: Das Geraet hat keine Kamera (oder der Nutzer hat sie
      // nicht erlaubt). Der Screen muss das erklaeren - und einen Weg
      // weiter anbieten.
      CameraPlatform.instance = FakeCameraPlatform(hatKamera: false);

      await tester.pumpWidget(harness());
      await tester.pump();
      await bestaetigeOffenlegung(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('verify.errorTitle')),
        findsOneWidget,
        reason:
            'Ohne Kamera muss der Nutzer einen Grund sehen - nicht nur eine '
            'leere Seite.',
      );
      // Und es gibt einen Weg weiter (neu versuchen).
      expect(
        find.text(L10n.tWithoutContext('admin.retry')),
        findsOneWidget,
        reason:
            'Der Nutzer muss es nochmal versuchen koennen - sonst ist die '
            'Verifikation fuer ihn tot.',
      );
    });
  });
}
