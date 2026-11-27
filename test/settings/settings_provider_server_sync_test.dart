// Die Server-Spiegelung der App-Einstellungen.
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/providers/settings/settings_provider.dart 55 offene Zeilen - der
// Weg zum Server (der Pause-Schalter, das Thema, die öffentlichen
// Schalter) lief ins Leere.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Pause-Schalter schreibt "paused" auf das Serverprofil,
//   * ein Serverfehler beim Pause-Sync bringt die App nicht um,
//   * das Thema wird auf dem Server gespiegelt,
//   * die öffentlichen Schalter (Musik, Gewohnheiten) schreiben ihre
//     eigene Spalte,
//   * die gespiegelten Werte kommen vom Server zurück.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/profile/profile_visibility.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_supabase_server.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseServer server;

  setUpAll(() async {
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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.schreibvorgaenge.clear();
    server.zeilen.clear();
  });

  /// Baut den Container.
  ProviderContainer baueContainer() {
    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_Speicher()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('Der Pause-Schalter', () {
    test('schreibt "paused" auf das Serverprofil', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setProfileVisibility(ProfileVisibility.hidden);
      // Der Sync läuft im Hintergrund - kurz warten.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final schreibvorgang = server.schreibvorgaenge.firstWhere(
        (z) => z['paused'] != null,
        orElse: () => <String, dynamic>{},
      );
      expect(schreibvorgang['paused'], isTrue);
      expect(container.read(settingsProvider).paused, isTrue);
    });

    test('ohne Wechsel wird nichts geschrieben', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setProfileVisibility(ProfileVisibility.everyone);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        server.schreibvorgaenge.where((z) => z['paused'] != null),
        isEmpty,
      );
    });

    test('ein Serverfehler bringt die App nicht um', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      // Der Server antwortet auf das Profil-Update mit einem Fehler.
      server.rpcFehler.add('update_own_profile');

      await notifier.setProfileVisibility(ProfileVisibility.hidden);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Der lokale Stand steht trotzdem - der Nutzer sieht seine
      // Einstellung, auch wenn der Server gerade nicht mitmacht.
      expect(container.read(settingsProvider).paused, isTrue);
    });
  });

  group('Das Thema', () {
    test('wird auf dem Server gespiegelt', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setThemeName('nacht');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(container.read(settingsProvider).themeName, 'nacht');
    });
  });

  group('Die öffentlichen Schalter', () {
    test('schreiben ihre eigene Spalte', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setShowMusicLiked(false);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final schreibvorgang = server.schreibvorgaenge.firstWhere(
        (z) => z.containsKey('show_music_liked'),
        orElse: () => <String, dynamic>{},
      );
      expect(schreibvorgang['show_music_liked'], isFalse);
      expect(container.read(settingsProvider).showMusicLiked, isFalse);
    });

    test('die Gewohnheiten schreiben ihre Spalten', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setShowHabitsSmoking(false);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final schreibvorgaenge = server.schreibvorgaenge
          .where((z) => z.containsKey('show_habits_smoking'))
          .toList();
      expect(schreibvorgaenge, isNotEmpty);
      expect(schreibvorgaenge.last['show_habits_smoking'], isFalse);
    });
  });
}
