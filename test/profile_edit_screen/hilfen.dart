// Die Helfer fuer die Tests des Bildschirms 'profile_edit_screen'.
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Helfer
// (Ersatz-Speicher, Aufbau, Bildschirm-Helfer) liegen hier -
// die Tests selbst sind nach Themen auf eigene Dateien verteilt.

// Widget-Tests fuer den Profil-Editor ("Profil bearbeiten").
//
// ANLASS: Die Coverage-Messung (13.11.2026) zeigte fuer
// lib/screens/profile/profile_edit_screen.dart 583 offene Zeilen. Der
// Screen ist die einzige Stelle, an der der Nutzer sein Profil
// aendert - und der Betreiber hat dort im November 2026 gemeldet:
// "Wenn man Buttons auswählt, z. B. in den Profileinstellungen, sollen
// sie sich nicht in die nächste Zeile durch auswählen verschieben."
//
// WAS HIER GEPRUEFT WIRD:
//   * der Screen zeigt die Werte des Profils,
//   * der Zurück-Knopf fragt nach ungespeicherten Änderungen
//     ("Speichern?"-Nachfrage) und bietet Speichern/Verwerfen/Abbrechen,
//   * "Speichern" meldet Erfolg, ein Serverfehler wird gemeldet,
//   * ein ungültiges Formular wird abgewiesen (mit Hinweis),
//   * die Chips (Interessen, Gesundheit, Musik) springen beim Auswählen
//     NICHT in die nächste Zeile (StableChip) - und die Auswahl wird
//     übernommen.
//
// OHNE SERVER: Der Supabase-Client bekommt einen [FakeSupabaseServer].
// Damit kann der Test den Erfolgsfall UND den Fehlerfall stellen,
// ohne Netz und ohne Wartezeit.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
// Das Plattform-Interface wird von permission_handler exportiert, aber
// nicht weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/user_preferences_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/location_check_service.dart';
import 'package:thestia/services/location_verification_service.dart';
import 'package:thestia/services/secure_storage.dart';
import 'package:thestia/services/supabase_service.dart';
import '../support/fake_supabase_server.dart';

class FakeLocalStorage implements LocalStorage {
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

class FakeSecurePrefs extends SecurePreferencesStorage {
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

class ProfileEditScreenBerechtigungen extends PermissionHandlerPlatform {
  /// Ist die Standort-Berechtigung erteilt?
  bool erteilt = false;
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      erteilt ? PermissionStatus.granted : PermissionStatus.denied;
  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    erteilt = true;
    return {for (final p in permissions) p: PermissionStatus.granted};
  }
}

class FakeOrtService extends LocationVerificationService {
  FakeOrtService({this.position});

  /// Die Position, die der Dienst meldet (null = kein Standort).
  final Position? position;

  /// Wie oft wurde der Standort abgefragt?
  int abfragen = 0;
  @override
  Future<Position?> getCurrentLocation() async {
    abfragen++;
    return position;
  }

  @override
  Future<bool> isLocationSuspicious(
    Position newPosition, {
    double thresholdMeters = 100,
  }) async => false;
}

class FakeStandortPruefung extends LocationCheckService {
  FakeStandortPruefung(super.client);

  /// Die Koordinaten, die zur Pruefung gemeldet wurden.
  final List<Map<String, dynamic>> aufrufe = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> processLocationCheck({
    required String userId,
    required double newLatitude,
    required double newLongitude,
  }) async {
    aufrufe.add(<String, dynamic>{
      'userId': userId,
      'newLatitude': newLatitude,
      'newLongitude': newLongitude,
    });
    return <String, dynamic>{'ok': true};
  }
}

Position profileEditScreenPosition() => Position(
  latitude: 53.5511,
  longitude: 9.9937,
  timestamp: DateTime(2026, 11, 16),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

final UserProfile profileEditScreenProfil = UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: 'Hallo aus Hamburg',
  birthDate: DateTime(1998, 6, 15),
  interests: <String>['Musik'],
);
final UserProfile profilMitBildern = UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: 'Hallo aus Hamburg',
  birthDate: DateTime(1998, 6, 15),
  interests: <String>['Musik'],
  photos: <String>['ich/avatar.jpg', 'ich/photos/2.jpg', 'ich/photos/3.jpg'],
);
GoRouter profileEditScreenRouter() {
  return GoRouter(
    initialLocation: AppRoutes.profileEdit,
    routes: [
      GoRoute(
        path: AppRoutes.profileEdit,
        builder: (context, state) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Mein Profil'))),
      ),
      GoRoute(
        path: AppRoutes.personalityTest,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Persönlichkeitstest'))),
      ),
    ],
  );
}

Finder imDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));
Future<ProviderContainer> profileEditScreenPump(
  WidgetTester tester,
  UserProfile profil, {
  FakeOrtService? ortService,
  Map<String, dynamic> gespeicherteEinstellungen = const {},
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  // Der IntroEditor erzeugt im initState einen AudioRecorder -> Kanal
  // mocken, sonst sucht das Plugin einen Plattform-Implementierer.
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    recordChannel,
    (call) async => null,
  );
  final storage = FakeLocalStorage();
  // DIE GESPEICHERTEN EINSTELLUNGEN: Der Screen korrigiert Werte, die der
  // Altersregel widersprechen (z. B. ein zu grosser Suchradius bei
  // Minderjaehrigen).
  if (gespeicherteEinstellungen.isNotEmpty) {
    await storage.saveString(
      'user_preferences',
      jsonEncode(gespeicherteEinstellungen),
    );
  }
  final secure = FakeSecureProfileStore();
  final container = ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      secureProfileStoreProvider.overrideWithValue(secure),
      // Der sichere Speicher der Einstellungen (Audit M-16) - ohne ihn
      // haengt jedes Schreiben in den Keystore (siehe FakeSecurePrefs).
      securePrefsProvider.overrideWithValue(FakeSecurePrefs()),
      sharedPrefsProvider.overrideWithValue(prefs),
      // Der Ort-Dienst: im Test gibt es kein GPS.
      if (ortService != null)
        locationVerificationServiceProvider.overrideWithValue(ortService),
      // Die Standort-Pruefung (Edge Function) - der Ersatz merkt sich
      // die Aufrufe (siehe FakeStandortPruefung).
      locationCheckServiceProvider.overrideWith(
        (ref) => FakeStandortPruefung(SupabaseService.client),
      ),
      profileProvider.overrideWith((ref) {
        final notifier = ProfileNotifier(storage, secure);
        // setProfile ist async, setzt den State aber sofort.
        unawaited(notifier.setProfile(profil));
        return notifier;
      }),
    ],
  );
  addTearDown(container.dispose);
  final router = profileEditScreenRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        routerConfig: router,
      ),
    ),
  );
  await pumpFrames(tester);
  return container;
}

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<bool> warteAuf(
  WidgetTester tester,
  Finder ziel, {
  int hoechstSchritte = 40,
}) async {
  for (var i = 0; i < hoechstSchritte; i++) {
    if (ziel.evaluate().isNotEmpty) return true;
    await tester.pump(const Duration(milliseconds: 250));
  }
  return ziel.evaluate().isNotEmpty;
}

Future<void> aufraeumen(WidgetTester tester) async {
  // Zehn Sekunden (in Sekunden-Schritten, damit die Timer dazwischen
  // feuern): der entprellte Sync der Einstellungen (1,5 s) UND die
  // Wiederholungsversuche des Server-Syncs (1 s + 2 s Wartezeit je
  // Versuch) muessen alle abgelaufen sein, sonst steht am Ende ein
  // Timer uebrig und der Test scheitert an "A Timer is still pending".
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> scrolleZumSpeichern(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Speichern').last,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await pumpFrames(tester);
}

late FakeSupabaseServer server;
