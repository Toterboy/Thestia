// Der Abgleich nach dem Login (der Auth-Anbieter) - ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/providers/auth/auth_provider.dart 189 offene Zeilen. Der Abgleich nach
// dem Login traegt eine Zusage: "Die Einrichtung erscheint nach einer
// Neuinstallation NICHT noch einmal" (Migration 065, `onboarding_done`).
//
// WAS HIER GEPRUEFT WIRD:
//   * die Setup-Flags des Servers werden uebernommen (die Einrichtung
//     erscheint nicht wieder),
//   * die UI-Einstellungen des Servers werden uebernommen,
//   * der Router wird freigegeben (der Lade-Screen verschwindet),
//   * ohne Serverstand bleibt der lokale Stand unangetastet.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/providers/auth/auth_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

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

/// Der Keystore ohne Plugin.
class _Keystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {
    // Der Test speichert kein Profil im Keystore.
  }

  @override
  Future<void> delete() async {
    // Der Test loescht kein Profil im Keystore.
  }
}

void main() {
  /// Der Ersatz-Server (der Stand des Kontos kommt von dort).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockZeitzone();
    // DER SPEICHER: der Chat-Dienst oeffnet beim Abgleich seine Box.
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
  });

  setUp(() {
    server.zeilen.clear();
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
  });

  /// Baut den Container und wartet auf den Abgleich.
  Future<ProviderContainer> baueContainer() async {
    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_Speicher()),
        secureProfileStoreProvider.overrideWithValue(_Keystore()),
      ],
    );
    addTearDown(container.dispose);

    // Der Auth-Anbieter wird beim Lesen erzeugt - dabei laeuft die
    // Wiederherstellung (und mit der Session der Abgleich).
    container.read(authProvider);

    // Der Abgleich braucht die echte Schleife (die HTTP-Antworten kommen
    // nur dort an).
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return container;
  }

  group('Der Abgleich nach dem Login', () {
    test('die Setup-Flags des Servers werden uebernommen', () async {
      // Der Server meldet: die Einrichtung ist erledigt.
      server.zeilen['profiles'] = <String, dynamic>{
        'user_id': 'ich',
        'name': 'Lena',
        'one_time_settings_completed': true,
        'community_guidelines_accepted': true,
        'personality_test_completed': true,
        'onboarding_done': true,
        'dating_hour_intro_seen': true,
        'paused': false,
      };
      await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');

      final container = await baueContainer();

      final stand = container.read(settingsProvider);
      expect(
        stand.oneTimeSettingsCompleted,
        isTrue,
        reason:
            'Die Einrichtung darf nach einer Neuinstallation nicht wieder '
            'erscheinen - der Server weiss, dass sie erledigt ist.',
      );
      expect(stand.communityGuidelinesAccepted, isTrue);
      expect(stand.personalityTestCompleted, isTrue);
      expect(stand.onboardingDone, isTrue);
      expect(
        container.read(setupFlagsKnownProvider),
        isTrue,
        reason: 'Der Server-Stand ist bekannt - das muss der Router wissen.',
      );
      expect(
        container.read(serverSyncDoneProvider),
        isTrue,
        reason: 'Nach dem Abgleich darf der Router weiterlaufen.',
      );
    });

    test('ohne Serverstand bleibt der lokale Stand', () async {
      // Der Server weiss nichts (leere Zeile).
      server.zeilen['profiles'] = <String, dynamic>{'user_id': 'ich'};
      await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');

      final container = await baueContainer();

      final stand = container.read(settingsProvider);
      expect(
        stand.oneTimeSettingsCompleted,
        isFalse,
        reason:
            'Ohne Serverstand bleibt der lokale Stand unangetastet - die App '
            'darf die Einrichtung nicht eigenmaechtig abhaken.',
      );
      expect(container.read(serverSyncDoneProvider), isTrue);
    });
  });

  group('Die Selbstheilung: lokale Flags gehen zum Server', () {
    /// Baut einen Container, OHNE den Abgleich zu starten - so kann der
    /// Test den lokalen Stand vorher setzen (der erste Abgleich darf
    /// lokale Werte noch nicht hochschieben).
    Future<ProviderContainer> baueContainerOhneAbgleich() async {
      final container = ProviderContainer(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_Speicher()),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// Wartet, bis der Abgleich durch ist (die HTTP-Antworten kommen nur
    /// in der echten Schleife an).
    Future<void> warteAufAbgleich() async {
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

    /// Wartet, BIS eine Bedingung eintritt (hoechstens [sekunden]).
    ///
    /// DER GRUND: Ein Schreibvorgang kann nach dem Abgleich noch
    /// eintrudeln. Ohne Warten landet er im NAECHSTEN Test - und der
    /// glaubt dann, sein eigener Weg habe geschrieben.
    Future<bool> warteBis(bool Function() bedingung, {int sekunden = 8}) async {
      for (var i = 0; i < sekunden * 10; i++) {
        if (bedingung()) return true;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return bedingung();
    }

    /// Hat der Server ein "erledigt"-Flag bekommen?
    bool flagGeschrieben(String schluessel) => server.schreibvorgaenge.any(
      (v) => v['tabelle'] == 'profiles' && v[schluessel] == true,
    );

    test(
      'nach dem zweiten Abgleich wird das lokale Flag nachgezogen',
      () async {
        // Der Server kennt die Einrichtung NICHT (das Speichern bei der
        // Einrichtung schlug still fehl).
        server.zeilen['profiles'] = <String, dynamic>{
          'user_id': 'ich',
          'name': 'Lena',
          'one_time_settings_completed': false,
          'community_guidelines_accepted': false,
        };
        await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');

        final container = await baueContainer();

        // Lokal ist die Einrichtung erledigt (z. B. nach einem Update).
        await container
            .read(settingsProvider.notifier)
            .completeOneTimeSettings();
        expect(
          container.read(settingsProvider).oneTimeSettingsCompleted,
          isTrue,
        );

        // Der naechste Abgleich schiebt das Flag zum Server.
        await container
            .read(authProvider.notifier)
            .silentLogin(email: 'lena@example.de', password: 'geheim123');

        // Auf den Schreibvorgang WARTEN - sonst eilt der Test davon und
        // der Vorgang landet im naechsten Test.
        await warteBis(() => flagGeschrieben('one_time_settings_completed'));
        await warteAufAbgleich();

        expect(
          flagGeschrieben('one_time_settings_completed'),
          isTrue,
          reason:
              'Das lokale "erledigt" muss zum Server - sonst erscheint die '
              'Einrichtung nach der naechsten Neuinstallation erneut.',
        );
      },
    );

    test('beim ERSTEN Abgleich wird nichts hochgeschoben', () async {
      // DER GRUND fuer die Sperre: Wer sich gerade registriert hat, hat
      // lokal noch nichts erledigt. Ein lokaler Restwert (aus einem
      // frueheren Test oder einer alten Installation) darf die
      // Einrichtung nicht ueberspringen.
      server.zeilen['profiles'] = <String, dynamic>{
        'user_id': 'ich',
        'name': 'Lena',
        'one_time_settings_completed': false,
      };
      await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');

      // Der lokale Stand wird VOR dem ersten Abgleich gesetzt.
      final container = await baueContainerOhneAbgleich();
      await container.read(settingsProvider.notifier).completeOneTimeSettings();

      // Jetzt der erste Abgleich. Vorher die Schreibvorgaenge leeren:
      // ein spaeter eintrudelnder Vorgang des Vorherigen Tests darf
      // diesen Test nicht beeinflussen.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      server.schreibvorgaenge.clear();
      container.read(authProvider);
      await warteAufAbgleich();

      expect(
        flagGeschrieben('one_time_settings_completed'),
        isFalse,
        reason:
            'Beim ersten Abgleich wird nichts hochgeschoben - sonst '
            'ueberspringt die App die Einrichtung.',
      );
    });
  });
}
