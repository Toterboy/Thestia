// Die Helfer für die Tests des Bildschirms 'transit_radar_screen'.
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Helfer
// (Ersatz-Speicher, Aufbau, Bildschirm-Helfer) liegen hier -
// die Tests selbst sind nach Themen auf eigene Dateien verteilt.

// Der Transit-Radar (Transit Spark) - bisher ungetestet.
//
// ANLASS (13.11.2026): Die Coverage-Messung zeigte für
// lib/screens/swipe/transit_radar_screen.dart 936 offene Zeilen. Der
// Bildschirm ist der Kern von Transit Spark ("Blicke getauscht, dich
// nicht getraut?") - und er wurde nie gerendert.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * die Alterssperre ist fail-closed (ohne Geburtsdatum gesperrt),
//   * beim ersten Öffnen fragt die App, ob der Name sichtbar sein soll,
//   * der Start fragt zuerst nach der eigenen Beschreibung,
//   * "Blicke getauscht" öffnet die Merkmalsauswahl und sendet die Tags,
//   * die Kandidatenliste erscheint und der Zuwink meldet Erfolg/Fehlschlag,
//   * der Ort wird übernommen (frei gewählt - KEIN Standort),
//   * der Name-Schalter speichert die Entscheidung.
//
// OHNE FUNK, OHNE SERVER: Das BLE-Starten und der Server werden durch
// einen Fake-Notifier ersetzt (kein Bluetooth, kein Netz). Die
// Merkmalsauswahl selbst ist das ECHTE Widget der App - sie wird nicht
// nachgebaut, sonst würde der Test nur Flutter prüfen und nicht die
// App.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:thestia/models/transit/transit_models.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/providers/transit/transit_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/swipe/transit_radar_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/utils/common/constants.dart';
import '../support/fake_supabase_server.dart';

class FakeLocalStorage implements LocalStorage {
  final Map<String, String> _data = {};
  @override
  Future<void> saveString(String key, String value) async => _data[key] = value;
  @override
  Future<String?> getString(String key) async => _data[key];
  @override
  Future<void> saveBool(String key, bool value) async =>
      _data[key] = value.toString();
  @override
  Future<bool?> getBool(String key) async =>
      _data[key] == null ? null : _data[key] == 'true';
  @override
  Future<void> remove(String key) async => _data.remove(key);
  @override
  Future<void> saveInt(String key, int value) async =>
      _data[key] = value.toString();
  @override
  Future<int?> getInt(String key) async =>
      _data[key] == null ? null : int.tryParse(_data[key]!);
}

class FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

class FakeTransit extends TransitNotifier {
  FakeTransit() : super();

  /// Das Ergebnis des nächsten "Blicke getauscht" (null = kein Match).
  ///
  /// DER STANDARD: Das Signal wird gesendet, aber es gibt noch keinen
  /// Match. Mit `null` wäre der Bildschirm nach dem Senden fertig - es
  /// gäbe keine Kandidatenliste und keinen Zuwink.
  TransitSparkResult? sparkErgebnis = const TransitSparkResult(matched: false);

  /// Der Fehlergrund des letzten Sendens (für die Snackbar-Diagnose).
  String? sendFehler;

  /// Die Kandidaten, die der Server liefern würde.
  List<TransitCandidate> kandidaten = const [];

  /// Antwort auf das Zuwinken.
  bool zuwinkKlappt = true;

  /// Die Tags, die zuletzt gesendet wurden.
  List<String> gesendeteTags = const [];

  /// Wie oft wurde zugewinkt?
  int zuwinke = 0;

  /// Wie oft wurde gestartet bzw. gestoppt?
  int starts = 0;
  int stops = 0;

  /// Wenn gesetzt: das Starten schlägt fehl (mit diesem Grund).
  String? startFehler;

  /// Die gesehenen Geräte (die Begegnungsliste).
  List<TransitEncounter> begegnungen = const [];

  /// Die gesendeten Grüße (Text und eigene Zeile).
  final List<({String messageKey, String? customLine})> gruesse = [];

  /// Setzt die Anzahl der gesehenen Geräte (ohne den Radar zu starten).
  ///
  /// DER GRUND: Nach dem Radar bleibt die Liste über "in Ruhe finden"
  /// erreichbar - dafür muss der Zähler in der App stimmen.
  void setzeBegegnungszahl(int anzahl) {
    state = state.copyWith(encounterCount: anzahl);
  }

  @override
  Future<bool> activate() async {
    starts++;
    if (startFehler != null) {
      state = state.copyWith(active: false, endsAt: null, busy: false);
      return false;
    }
    state = state.copyWith(
      active: true,
      endsAt: DateTime.now().add(const Duration(minutes: 45)),
    );
    return true;
  }

  @override
  Future<void> deactivate() async {
    stops++;
    state = state.copyWith(active: false, endsAt: null, busy: false);
  }

  @override
  Future<TransitSparkResult?> sendSpark(List<String> tags) async {
    gesendeteTags = List<String>.of(tags);
    state = state.copyWith(
      busy: false,
      lastResult: sparkErgebnis,
      lastError: sendFehler,
    );
    return sparkErgebnis;
  }

  @override
  Future<List<TransitCandidate>> listCandidates({
    required List<String> tags,
    List<String> selfTags = const [],
  }) async => kandidaten;
  @override
  Future<bool> sendSoftPing({
    required String token,
    required String messageKey,
    String? customLine,
    String? recipientId,
    String? placeKind,
    String? placeText,
    List<String> tags = const [],
    List<String> selfTags = const [],
  }) async {
    zuwinke++;
    gruesse.add((messageKey: messageKey, customLine: customLine));
    return zuwinkKlappt;
  }

  @override
  List<TransitEncounter> softEncounters() => begegnungen;
  @override
  DateTime? softUntil() => null;
}

UserProfile volljaehrig() => UserProfile(
  id: 'ich',
  name: 'Lena',
  bio: '',
  birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
);
UserProfile ohneGeburtsdatum() =>
    const UserProfile(id: 'ich', name: 'Lena', bio: '');
ProviderContainer transitRadarScreenContainer({
  FakeTransit? transit,
  UserProfile? profil,
  bool namensfrageErledigt = true,
}) {
  final storage = FakeLocalStorage();
  if (namensfrageErledigt) {
    storage.saveString(
      AppConstants.prefsSettingsKey,
      // DER SCHLÜSSEL: Lokal werden die Einstellungen mit CAMELCASE
      // gespeichert (siehe AppSettings.fromJson) - nur die Server-Spalten
      // heißen snake_case.
      jsonEncode(<String, dynamic>{'transitShowNameSet': true}),
    );
  }
  final profilNotifier = ProfileNotifier(storage, FakeSecureProfileStore());
  profilNotifier.setProfile(profil ?? volljaehrig());
  return ProviderContainer(
    overrides: [
      localStorageProvider.overrideWithValue(storage),
      secureProfileStoreProvider.overrideWithValue(FakeSecureProfileStore()),
      profileProvider.overrideWith((ref) => profilNotifier),
      if (transit != null) transitProvider.overrideWith((ref) => transit),
    ],
  );
}

GoRouter transitRadarScreenRouter() {
  return GoRouter(
    initialLocation: '/radar',
    routes: [
      GoRoute(path: '/radar', builder: (_, _) => const TransitRadarScreen()),
      GoRoute(
        path: AppRoutes.interessen,
        builder: (_, _) => const Scaffold(body: Text('Funken-Liste')),
      ),
    ],
  );
}

Future<void> aufbauen(
  WidgetTester tester,
  ProviderContainer container,
  GoRouter router,
) async {
  await container.read(settingsProvider.notifier).whenLoaded();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> merkmaleWaehlen(
  WidgetTester tester,
  List<String> bezeichnungen,
) async {
  for (final bezeichnung in bezeichnungen) {
    final chip = find.text(bezeichnung);
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
  }
}

Future<void> sendenTippen(WidgetTester tester) async {
  final knopf = find.widgetWithText(FilledButton, 'Funken');
  await tester.ensureVisible(knopf);
  await tester.pump();
  await tester.tap(knopf);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> warteAufText(WidgetTester tester, String text) async {
  for (var i = 0; i < 40; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> knopfTippen(WidgetTester tester, String text) async {
  final knopf = find.text(text);
  await tester.ensureVisible(knopf);
  await tester.pump();
  await tester.tap(knopf);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> startTippen(WidgetTester tester) async {
  final knopf = find.text('Radar aktivieren');
  await tester.ensureVisible(knopf);
  await tester.pump();
  await tester.tap(knopf);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> serverAntwortAbwarten(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> radarStarten(WidgetTester tester) async {
  await startTippen(tester);
  await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
  await sendenTippen(tester);
}

late FakeSupabaseServer server;
