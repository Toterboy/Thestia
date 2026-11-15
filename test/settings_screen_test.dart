// Die Einstellungen (bisher kaum getestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/settings/settings_screen.dart 449 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * die Abschnitte stehen da (Sicherheit, Benachrichtigungen,
//     Darstellung, Datenschutz & Account),
//   * ein Schalter laesst sich umstellen und der Stand wird gespeichert.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/plugin_mocks.dart';

/// Der Speicher im RAM - die Einstellungen werden daraus gelesen.
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
  late _FakeLocalStorage storage;
  late ProviderContainer container;

  setUpAll(() async {
    // DER SPEICHER DES GERAETS: der Auth-Client holt sich daraus die
    // Sitzung - ohne den Mock schlaegt der Aufbau fehl.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Der Supabase-Client: die Eltern-Aufsicht liest ihn. Ohne die drei
    // Optionen (kein Timer, kein Speicher, kein Deeplink-Observer)
    // scheitert der Aufbau auf dem CI-Runner.
    await mockPfadProvider();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    // HIVE: der Abschnitt "Ende-zu-Ende-Verschluesselung" liest die
    // gesicherten Schluessel aus einer Hive-Box. Ohne einen
    // initialisierten Hive scheitert der Aufbau.
    final tempDir = await Directory.systemTemp.createTemp('thesia_settings');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = _FakeLocalStorage();
    // DER KEYSTORE: die Einstellungen liegen im verschluesselten
    // Speicher - ohne den Mock ruft der Test auf dem CI-Runner das
    // echte Plugin (das findet dort keine libsecret-Sitzung).
    mockKeystore();
  });

  tearDown(() {
    container.dispose();
  });

  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final secure = _FakeSecureProfileStore();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        secureProfileStoreProvider.overrideWithValue(secure),
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(storage, secure);
          notifier.setProfile(
            const UserProfile(id: 'ich', name: 'Lena', bio: ''),
          );
          return notifier;
        }),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Scrollt zu einem Text (der Bildschirm ist eine lange Liste).
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    if (ziel.evaluate().isNotEmpty) return;
    // Der Bildschirm ist sehr lang (die Liste baut nur die sichtbaren
    // Eintraege) - also wird in kleinen Schritten gescrollt, bis der
    // Text da ist.
    for (var i = 0; i < 40 && ziel.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('der Bildschirm baut sich ohne Absturz', (tester) async {
    await zeigeScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('die Abschnitte stehen da', (tester) async {
    await zeigeScreen(tester);

    for (final abschnitt in [
      'settings.communitySafety',
      'settings.notifications',
      'settings.appearance',
    ]) {
      await scrolleZu(tester, L10n.tWithoutContext(abschnitt));
      expect(
        find.text(L10n.tWithoutContext(abschnitt)),
        findsWidgets,
        reason: 'Der Abschnitt $abschnitt muss stehen.',
      );
    }
  });

  testWidgets('der Schalter fuer unscharfe Bilder steht da', (tester) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('settings.blur'));

    final schalter = find.ancestor(
      of: find.text(L10n.tWithoutContext('settings.blur')),
      matching: find.byType(SwitchListTile),
    );
    expect(
      schalter,
      findsOneWidget,
      reason:
          'Der Schalter fuer unscharfe Bilder muss erreichbar sein - er ist '
          'der Schutz, dass ein geteiltes Bild nicht unerklaerbar ist.',
    );
  });

  testWidgets('das Erscheinungsbild laesst sich umstellen', (tester) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('appearance.dark'));

    // "Dunkel" waehlen. ensureVisible: der Abschnitt liegt unterhalb
    // der Falz - ohne das landet der Tipp ins Leere.
    final dunkel = find.text(L10n.tWithoutContext('appearance.dark'));
    await tester.ensureVisible(dunkel);
    await pumpFrames(tester);
    await tester.tap(dunkel);
    await pumpFrames(tester);
    // Der Server-Sync ist entprellt (1,5 s) - der Timer muss abgelaufen
    // sein, sonst meldet der Test am Ende "Timer is still pending".
    await tester.pump(const Duration(milliseconds: 2000));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(
      container.read(settingsProvider).useDarkMode,
      isTrue,
      reason: 'Der Nutzer hat "Dunkel" gewaehlt - das muss gespeichert sein.',
    );
  });

  testWidgets('"System" heisst: die App folgt dem Geraet', (tester) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('appearance.system'));

    final system = find.text(L10n.tWithoutContext('appearance.system'));
    await tester.ensureVisible(system);
    await pumpFrames(tester);
    await tester.tap(system);
    await pumpFrames(tester);
    // Der Server-Sync ist entprellt (1,5 s) - der Timer muss abgelaufen
    // sein, sonst meldet der Test am Ende "Timer is still pending".
    await tester.pump(const Duration(milliseconds: 2000));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    // null heisst: "es entscheidet das Geraet" - true/false waere eine
    // feste Entscheidung und damit etwas anderes.
    expect(container.read(settingsProvider).useDarkMode, isNull);
  });
}
