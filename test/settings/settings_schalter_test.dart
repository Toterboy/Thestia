// Die Einstellungen: die Benachrichtigungs-Schalter und das Abmelden.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/screens/settings/settings_screen.dart 67 offene Zeilen. Der
// bestehende Test ("settings_screen_test.dart") deckt den Aufbau und
// einen Schalter ab - offen waren die Benachrichtigungs-Schalter (sie
// sind an den Hauptschalter gebunden) und das Abmelden.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Hauptschalter sperrt die einzelnen Schalter (der Server
//     würde die Meldungen ohnehin nicht schicken - ein bedienbarer
//     Schalter, der nichts bewirkt, ist ärgerlicher als keiner),
//   * ein Schalter ändert den Stand,
//   * (das Abmelden hängt im Test an der Sitzungs-Bereinigung -
//     das ist ein eigener Weg und wird im Auth-Test geprüft.)
//
// NICHT DABEI: Die Versionszeile am Fuß der Seite läuft über das
// Paket-Info-Plugin - im Test antwortet die Plattform nicht, und der
// Bildschirm blendet die Zeile dann aus (das ist gewollt: eine leere
// Versionsangabe wäre schlimmer als keine).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

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

/// Der Verschlüsselungs-Dienst (der Dialog soll nur einen Code
/// bekommen - für die Oberfläche reicht das).
class _FakeVerschluesselung extends EncryptionService {
  @override
  Future<String?> createEncryptedBackup(String password) async =>
      'TEST_BACKUP_CODE_1234';
}

void main() {
  late _Speicher speicher;
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
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
    final temp = await Directory.systemTemp.createTemp('thesia_settings2');
    Hive.init(temp.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    speicher = _Speicher();
    mockKeystore();
  });

  tearDown(() {
    container.dispose();
  });

  /// Baut den Einstellungs-Screen.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Anmeldung'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final secure = _Keystore();
    container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(speicher),
        secureProfileStoreProvider.overrideWithValue(secure),
        encryptionServiceProvider.overrideWithValue(_FakeVerschluesselung()),
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(speicher, secure);
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    // DER ENTPRELL-TIMER: Das Merken der Voreinstellungen wartet 1,5 s -
    // der Timer muss noch laufen, sonst steht er am Testende offen.
    await tester.pump(const Duration(milliseconds: 1600));
  }

  /// Scrollt zu einem Schalter und macht ihn sichtbar.
  ///
  /// DER HINWEIS: Die Liste baut nur die sichtbaren Einträge - der
  /// Schalter muss also erst herangescrollt UND sichtbar gemacht
  /// werden, sonst tippt der Test ins Leere.
  Future<void> scrolleZuSchalter(WidgetTester tester, String key) async {
    final text = L10n.tWithoutContext(key);
    for (var i = 0; i < 60 && find.text(text).evaluate().isEmpty; i++) {
      await tester.timedDrag(
        find.byType(Scrollable).first,
        const Offset(0, -300),
        const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
    final ziel = find.text(text);
    if (ziel.evaluate().isNotEmpty) {
      await tester.ensureVisible(ziel);
      await tester.pump();
    }
  }

  group('Die Benachrichtigungen', () {
    testWidgets('der Hauptschalter sperrt die einzelnen Schalter', (
      tester,
    ) async {
      await zeigeScreen(tester);
      await scrolleZuSchalter(tester, 'settings.pushEnable');

      // DER HAUPTSCHALTER: Solange er an ist, sind die einzelnen Schalter
      // bedienbar.
      await tester.tap(
        find.widgetWithText(
          SwitchListTile,
          L10n.tWithoutContext('settings.pushEnable'),
        ),
      );
      await tester.pump();
      // DER ENTPRELL-TIMER: Das Merken der Voreinstellungen wartet 1,5 s -
      // der Timer muss noch laufen, sonst steht er am Testende offen.
      await tester.pump(const Duration(milliseconds: 1600));

      expect(tester.takeException(), isNull);
      expect(
        container.read(settingsProvider).notificationsEnabled,
        isFalse,
        reason:
            'Der Hauptschalter muss umspringen - er entscheidet, ob die App '
            'ueberhaupt Benachrichtigungen schickt.',
      );

      // Und jetzt sind die einzelnen Schalter gesperrt.
      await scrolleZuSchalter(tester, 'settings.notifyLikes');
      final likes = find.widgetWithText(
        SwitchListTile,
        L10n.tWithoutContext('settings.notifyLikes'),
      );
      expect(likes, findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(likes).onChanged,
        isNull,
        reason:
            'Ohne den Hauptschalter sind die einzelnen Schalter gesperrt - '
            'ein bedienbarer Schalter, der nichts bewirkt, ist aergerlicher '
            'als keiner.',
      );
      // DER BILDSCHIRM WIRD ABGEBAUT: Sonst bleibt ein
      // Timer des Bildschirms stehen und der Test scheitert.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ein Schalter aendert den Stand', (tester) async {
      await zeigeScreen(tester);
      await scrolleZuSchalter(tester, 'settings.notifyLikes');

      final likes = find.widgetWithText(
        SwitchListTile,
        L10n.tWithoutContext('settings.notifyLikes'),
      );
      expect(likes, findsOneWidget);
      final vorher = tester.widget<SwitchListTile>(likes).value;

      await tester.tap(likes);
      await tester.pump();
      // DER ENTPRELL-TIMER: Das Merken der Voreinstellungen wartet 1,5 s -
      // der Timer muss noch laufen, sonst steht er am Testende offen.
      await tester.pump(const Duration(milliseconds: 1600));

      expect(tester.takeException(), isNull);
      expect(
        container.read(settingsProvider).notifyLikes,
        !vorher,
        reason:
            'Der Schalter muss den Stand aendern - sonst denkt der Nutzer, '
            'er habe es eingestellt, aber es passiert nichts.',
      );
    });
  });
}
