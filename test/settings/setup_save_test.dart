// Das Speichern in der Ersteinrichtung (bisher ungetestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte für
// lib/screens/onboarding/settings_privacy_once_screen.dart 373 offene
// Zeilen.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Angaben aus der Ersteinrichtung landen beim Server (nicht nur
//     lokal - sonst wären sie nach der Ersteinrichtung weg),
//   * das Land wird mitgespeichert,
//   * die Interessen werden mitgespeichert.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart.
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
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/onboarding/settings_privacy_once_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM.
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
  late FakeSupabaseServer server;

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

    // HIVE: die verschlüsselten Schlüssel (Signal-Protokoll) liegen in
    // Hive-Boxen - ohne initialisierten Hive schlägt der Aufbau fehl.
    final tempDir = await Directory.systemTemp.createTemp('thesia_setup');
    Hive.init(tempDir.path);

    // ANGEMELDET: Ohne Sitzung gibt der Server-Dienst nichts frei
    // ("Nicht eingeloggt") - das Profil würde nie gespeichert.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
    server.schreibvorgaenge.clear();
    server.zeilen.clear();
  });

  /// Baut die Ersteinrichtung.
  Future<void> zeigeEinrichtung(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/einrichtung',
      routes: [
        GoRoute(
          path: '/einrichtung',
          builder: (context, state) => const SettingsPrivacyOnceScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    final storage = _FakeLocalStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(
            _FakeSecureProfileStore(),
          ),
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
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Geht zur Profilseite und füllt sie.
  Future<void> fuelleProfil(WidgetTester tester) async {
    await tester.tap(find.text(L10n.tWithoutContext('onb.next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(
      find.byType(TextFormField).first,
      'Ich mag lange Spaziergaenge am Fluss.',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Ein Interesse wählen (der Chip liegt unterhalb der Falz).
    final chip = find.widgetWithText(FilterChip, 'Sport');
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Das Speichern in der Ersteinrichtung', () {
    testWidgets('die Angaben landen beim Server', (tester) async {
      await zeigeEinrichtung(tester);
      await fuelleProfil(tester);

      // "Weiter" auf der Profilseite speichert die Angaben.
      await tester.tap(find.text(L10n.tWithoutContext('onb.next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);

      // Der Server hat ein Profil-Update bekommen.
      final updates = server.schreibvorgaenge
          .where((s) => s['tabelle'] == 'profiles')
          .toList();
      expect(updates, isNotEmpty, reason: 'Es muss ein Update geben.');

      final profil = updates.last;
      expect(profil['bio'], 'Ich mag lange Spaziergaenge am Fluss.');
      expect(profil['interests'], contains('Sport'));
      // Und das Land (sonst stünden alle Profile auf 'Deutschland').
      expect(profil['country'], isNotNull);
    });

    testWidgets('das Land wird mitgespeichert', (tester) async {
      await zeigeEinrichtung(tester);
      await fuelleProfil(tester);

      await tester.tap(find.text(L10n.tWithoutContext('onb.next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final updates = server.schreibvorgaenge
          .where((s) => s['tabelle'] == 'profiles')
          .toList();
      expect(updates, isNotEmpty);
      expect(updates.last['country'], 'Deutschland');
    });
  });
}
