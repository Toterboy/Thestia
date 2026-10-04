import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thestia/screens/verification/verification_flow.dart';
import 'package:thestia/services/local_storage.dart';

/// Zaehlt, wie oft die Kamera tatsaechlich angefragt wurde.
///
/// Entscheidend ist nicht, WAS zurueckkommt, sondern OB ueberhaupt
/// gefragt wird - genau das war der Fehler: die App holte die
/// Kamerabiliste in initState, also lange bevor der Nutzer gelesen
/// hatte, warum sie gebraucht wird. Eine leere Liste reicht hier
/// voellig: danach schlaegt der Aufruf in einen Fehlerzustand, was
/// fuer diese Tests unerheblich ist.
class _CountingCamera extends CameraPlatform {
  int calls = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    calls++;
    return const <CameraDescription>[];
  }

  @override
  Future<Object?> dispose(int cameraId) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingCamera camera;

  setUp(() {
    // Leere Einstellungen: die Offenlegung wurde noch nicht bestaetigt.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    camera = _CountingCamera();
    CameraPlatform.instance = camera;
  });

Widget harness() => ProviderScope(
        overrides: [
          // localStorageProvider wirft UnimplementedError, wenn es nicht
          // gesetzt ist - die echte Einstellungskette laeuft darueber.
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        ],
        child: const MaterialApp(home: VerificationVideoScreen()),
      );

  testWidgets('Kamera wird vor der Offenlegung nicht angefragt',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(
      find.text('Kamera und Mikrofon fuer die Alterspruefung'),
      findsOneWidget,
      reason: 'Die Offenlegung muss VOR der Berechtigungsanfrage stehen.',
    );
    expect(
      camera.calls,
      0,
      reason: 'Die Kamera wird angefragt, bevor der Nutzer gelesen hat, '
          'warum sie gebraucht wird. Das verletzt die Play-Richtlinie '
          'fuer CAMERA.',
    );
  });

  testWidgets('Ablehnen fuehrt in einen erklaerbaren Zustand', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(camera.calls, 0, reason: 'Ablehnen darf die Kamera nicht oeffnen.');
    expect(
      find.textContaining('Ohne Kamera'),
      findsOneWidget,
      reason: 'Ohne Kamera ist die Alterspruefung nicht moeglich. Der '
          'Nutzer braucht einen Grund und einen Weg weiter, nicht nur '
          'eine leere Seite.',
    );
  });

  testWidgets('Bestaetigen oeffnet die Kamera genau einmal',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Kamera freigeben'));
    await tester.pump();
    await tester.pump();

    expect(
      camera.calls,
      1,
      reason: 'Nach der Bestaetigung wird genau einmal angefragt.',
    );
  });
}

/// Minimaler Speicher im Arbeitsspeicher. `localStorageProvider` wirft
/// absichtlich UnimplementedError, wenn er nicht gesetzt wird - ohne
/// diesen Attrapp laeuft die Einstellungskette nicht.
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