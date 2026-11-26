// Die Einstellungen und ihre Serverspiegelung - der Abgleich war
// ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte für
// lib/providers/settings/settings_provider.dart 168 offene Zeilen bei 321 Zeilen
// gesamt. Der Abgleich mit dem Server ist wichtig: nach einer
// Neuinstallation oder auf einem zweiten Gerät muss der Serverstand
// gelten ("Server gewinnt") - sonst glaubt der Nutzer, eine Einstellung
// sei aus, während der Server sie weiter hat.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Server gewinnt bei den UI-Einstellungen,
//   * der Blind Mode wird NICHT vom Server übernommen (er ist fest AN -
//     ein alter Serverstand würde die App wieder ausblenden),
//   * "pausiert" blendet das Profil aus,
//   * die Schalter in eigenen Spalten werden übernommen,
//   * fehlende Schlüssel lassen den lokalen Stand unangetastet.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  /// Der Ersatz-Server.
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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    server.schreibvorgaenge.clear();
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

  group('Die Einstellungen vom Server', () {
    test('der Server gewinnt bei den UI-Einstellungen', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.applyServerUiPrefs(<String, dynamic>{
        'revealPhotosAfterMatch': true,
        'profileVisibility': 'everyone',
        'useDarkMode': true,
        'notificationsEnabled': false,
        'notifyMatches': true,
        'notifyLikes': false,
        'notifyMessages': true,
        'notifyDatingHour': false,
        'contextIcebreakerEnabled': true,
        'habitsDealbreaker': true,
      });

      final stand = container.read(settingsProvider);
      expect(stand.revealPhotosAfterMatch, isTrue);
      expect(stand.useDarkMode, isTrue);
      expect(stand.notificationsEnabled, isFalse);
      expect(stand.notifyMatches, isTrue);
      expect(stand.notifyLikes, isFalse);
      expect(stand.notifyMessages, isTrue);
      expect(stand.notifyDatingHour, isFalse);
      expect(stand.contextIcebreakerEnabled, isTrue);
      expect(stand.habitsDealbreaker, isTrue);
    });

    test('der Blind Mode wird NICHT uebernommen', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      // Ein alter Serverstand (Blind Mode aus) darf die App NICHT wieder
      // ausblenden - der Blind Mode ist fest AN.
      await notifier.applyServerUiPrefs(<String, dynamic>{
        'blindModeEnabled': false,
      });

      expect(
        container.read(settingsProvider).blindModeEnabled,
        isTrue,
        reason:
            'Der Blind Mode ist fest AN - ein alter Serverstand darf ihn '
            'nicht ausschalten.',
      );
    });

    test('"pausiert" blendet das Profil aus', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.applyServerUiPrefs(<String, dynamic>{'paused': true});

      final stand = container.read(settingsProvider);
      expect(stand.paused, isTrue);
      expect(
        stand.profileVisibility,
        ProfileVisibility.hidden,
        reason:
            'Wer pausiert ist, will nicht gefunden werden - das Profil muss '
            'ausgeblendet sein.',
      );
    });

    test('ohne Serverangaben bleibt der lokale Stand', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.applyServerUiPrefs(null);
      await notifier.applyServerUiPrefs(<String, dynamic>{});
      await notifier.applyServerSwitches(null);
      await notifier.applyServerSwitches(<String, dynamic>{});

      expect(
        container.read(settingsProvider).useDarkMode,
        isNull,
        reason:
            'Fehlt der Serverstand (alter Serverstand), bleibt der lokale '
            'Wert unangetastet.',
      );
    });

    test('die Schalter in eigenen Spalten werden uebernommen', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      await notifier.applyServerSwitches(<String, dynamic>{
        'show_distance': true,
        'notifications_enabled': true,
        'notify_matches': false,
        'notify_likes': true,
        'notify_messages': false,
        'notify_dating_hour': true,
        'transit_show_name': true,
        'transit_show_name_set': true,
      });

      final stand = container.read(settingsProvider);
      expect(stand.showDistance, isTrue);
      expect(stand.notificationsEnabled, isTrue);
      expect(stand.notifyMatches, isFalse);
      expect(stand.notifyLikes, isTrue);
      expect(stand.notifyMessages, isFalse);
      expect(stand.notifyDatingHour, isTrue);
      expect(stand.transitShowName, isTrue);
      expect(
        stand.transitShowNameSet,
        isTrue,
        reason:
            'Das "hat der Nutzer entschieden"-Flag kommt vom Server - sonst '
            'fragt der Dialog auf dem zweiten Geraet nochmal.',
      );
    });

    test('der Schalter wandert auch zum Server', () async {
      final container = baueContainer();
      final notifier = container.read(settingsProvider.notifier);

      // Der Vorgabe-Wert ist "aus" - also AN schalten (sonst ändert
      // sich nichts und es gibt nichts zu spiegeln).
      await notifier.setShowDistance(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        server.schreibvorgaenge.any(
          (s) => s['tabelle'] == 'profiles' && s['show_distance'] == true,
        ),
        isTrue,
        reason:
            'Der Schalter muss zum Server - sonst gilt er nur auf diesem '
            'Geraet.',
      );
    });
  });
}
