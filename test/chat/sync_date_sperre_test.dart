// Die Sperre während eines laufenden Sync-Dates.
//
// ANLASS (27.11.2026): Der Betreiber: "Es darf nur dieser Chat während
// des Dates in der App genutzt werden (also alle anderen Chats und Modi
// sind nicht verfügbar, bis das Date zu Ende ist - sowas wie
// Einstellungen soll aber gehen)."
//
// WAS HIER GEPRÜFT WIRD:
//   * der Chat des Dates ist frei,
//   * ein anderer Chat ist gesperrt,
//   * die Einstellungen bleiben offen (das muss gehen),
//   * die Umleitung des Routers schickt in den gesperrten Chat,
//   * die Karte setzt die Sperre, solange das Date läuft.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/dating_hour/sync_date.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/models/settings/app_settings.dart';
import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/dating_hour/sync_date_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/routing/sync_date_routes.dart';
import 'package:thestia/services/auth/app_auth_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Aufruf der Umleitung mit dem Ref des Containers.
final umleitungsAnbieter = Provider<Future<String?> Function(String)>((ref) {
  return (pfad) => umleitung(ref, pfad);
});

/// Der Speicher im RAM (die Einstellungen kommen daraus).
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

/// Der Auth-Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst holt die Session vom Server - im Test
/// gibt es keinen Server. Wichtig ist nur, OB jemand angemeldet ist.
class _Auth implements AppAuthService {
  @override
  Future<bool> restoreSession() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return false;
  }

  @override
  Future<void> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {}

  @override
  Future<void> loginWithPasskey({String? captchaToken}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<UserProfile> register({
    required String email,
    required String password,
    required String name,
    String? gender,
    required DateTime birthDate,
    double? latitude,
    double? longitude,
    String? captchaToken,
  }) async {
    throw UnimplementedError('Der Test registriert niemanden.');
  }
}

/// Die Einstellungen als Ersatz.
class _Einstellungen extends SettingsNotifier {
  _Einstellungen(Ref ref) : super(_Speicher(), ref);
}

/// Das Profil als Ersatz.
class _Profil extends ProfileNotifier {
  _Profil() : super(_Speicher(), _Keystore());
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

/// Der Container, in dem die Umleitung entscheidet.
ProviderContainer baueContainer() {
  return ProviderContainer(
    overrides: <Override>[
      localStorageProvider.overrideWithValue(_Speicher()),
      secureProfileStoreProvider.overrideWithValue(_Keystore()),
      settingsProvider.overrideWith((ref) => _Einstellungen(ref)),
      profileProvider.overrideWith((ref) => _Profil()),
      authProvider.overrideWith(
        (ref) => AuthNotifier(_Auth(), ref.read(profileProvider.notifier), ref),
      ),
    ],
  );
}

/// Bringt den Container in den Zustand, in dem die Umleitung entscheidet:
/// angemeldet, Einstellungen geladen, Server-Sync fertig.
Future<void> _bereite(ProviderContainer container) async {
  // DER AUTH-ANBIETER: Beim ersten Lesen startet die Wiederherstellung
  // (sie fragt die Session beim Server). Der Test wartet sie ab und setzt
  // den Zustand DANACH - sonst überschreibt die Wiederherstellung ihn und
  // die Umleitung schickt zum Login.
  container.read(authProvider.notifier);
  await Future<void>.delayed(const Duration(milliseconds: 60));
  container.read(authProvider.notifier).state = const AsyncValue.data(true);
  container.read(settingsLoadedProvider.notifier).state = true;
  container.read(serverSyncDoneProvider.notifier).state = true;
  // DIE EINSTELLUNGEN: "fertig" - sonst schickt die Umleitung zur
  // Einrichtung und die Sync-Sperre kommt gar nicht dran.
  container.read(settingsProvider.notifier).state = AppSettings.defaults()
      .copyWith(
        introSeen: true,
        onboardingDone: true,
        onboardingCompleted: true,
        oneTimeSettingsCompleted: true,
        communityGuidelinesAccepted: true,
        personalityTestCompleted: true,
        datingSafetyEducationCompleted: true,
        signupWelcomeSeen: true,
        datingHourIntroSeen: true,
      );
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: der Auth-Anbieter legt seine Boxen an - ohne initialisiertes
    // Hive schlägt der Aufbau fehl.
    await mockHive();
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

  group('Die freien Wege', () {
    test('der Chat des Dates ist frei', () {
      expect(syncDateFrei('/chat/7', '7'), isTrue);
    });

    test('ein anderer Chat ist gesperrt', () {
      expect(
        syncDateFrei('/chat/8', '7'),
        isFalse,
        reason: 'Ein anderer Chat darf waehrend des Dates nicht offen sein.',
      );
    });

    test('die Einstellungen bleiben offen', () {
      expect(
        syncDateFrei('/settings', '7'),
        isTrue,
        reason:
            'Der Betreiber: "sowas wie Einstellungen soll aber gehen" - '
            'man muss die App auch bedienen koennen.',
      );
    });

    test('die anderen Modi sind gesperrt', () {
      expect(syncDateFrei('/interessen', '7'), isFalse);
      expect(syncDateFrei('/dating-hour', '7'), isFalse);
      expect(syncDateFrei('/', '7'), isFalse);
    });
  });

  group('Die Umleitung', () {
    test('ein anderer Chat landet im gesperrten Chat', () async {
      final container = baueContainer();
      addTearDown(container.dispose);
      // DER ZUSTAND: Der Nutzer ist angemeldet, die Einstellungen sind
      // geladen und der Server-Sync ist fertig - sonst greift eine der
      // anderen Regeln der Umleitung (und nicht die Sync-Sperre).
      await _bereite(container);
      container.read(syncDateSperreProvider.notifier).state = '7';

      final umleit = container.read(umleitungsAnbieter);

      expect(
        await umleit('/chat/8'),
        '/chat/7',
        reason:
            'Waehrend des Dates fuehrt kein Weg aus dem Chat heraus - '
            'ausser in die Einstellungen.',
      );
      expect(await umleit('/chat/7'), isNull);
    });

    test('ohne Date wird nichts umgeleitet', () async {
      final container = baueContainer();
      addTearDown(container.dispose);
      await _bereite(container);
      container.read(syncDateSperreProvider.notifier).state = null;

      final umleit = container.read(umleitungsAnbieter);

      expect(await umleit('/chat/8'), isNull);
    });
  });

  group('Der Anbieter der Sperre', () {
    test('steht auf null, wenn kein Date laeuft', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(syncDateSperreProvider), isNull);
    });

    test('nimmt die Match-ID auf', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(syncDateSperreProvider.notifier).state = '7';

      expect(container.read(syncDateSperreProvider), '7');
    });
  });

  group('Das laufende Date', () {
    test('laeuft, wenn der Startzeitpunkt erreicht ist', () {
      final date = SyncDate(
        matchId: '7',
        idea: SyncDateIdee.kochDuell,
        startAt: DateTime.now().subtract(const Duration(minutes: 5)),
        proposedByMe: true,
        acceptedByMe: true,
        acceptedByPartner: true,
      );

      expect(date.laeuft, isTrue);
      expect(date.bothAccepted, isTrue);
    });

    test('laeuft noch nicht, wenn der Termin in der Zukunft liegt', () {
      final date = SyncDate(
        matchId: '7',
        idea: SyncDateIdee.kochDuell,
        startAt: DateTime.now().add(const Duration(hours: 2)),
        proposedByMe: true,
        acceptedByMe: true,
        acceptedByPartner: true,
      );

      expect(date.laeuft, isFalse);
    });
  });
}
