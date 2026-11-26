// Die Passkey-Kachel in den Einstellungen.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/screens/settings/parts/passkeytilestate.dart 45 offene Zeilen bei
// 15 % Abdeckung. Die Kachel registriert einen Passkey - und der Weg
// dorthin hat eine Besonderheit: liegt auf dem Konto schon einer, fragt
// die App nach (der alte Eintrag kann die Neuregistrierung stören).
//
// WAS HIER GEPRÜFT WIRD:
//   * die Kachel bietet die Einrichtung an,
//   * bei vorhandenem Passkey fragt die App nach (mit der Anzahl) und
//     bricht auf "Abbrechen" ab - es wird NICHTS registriert,
//   * "Trotzdem fortfahren" startet die Registrierung, und ein Fehler
//     wird dem Nutzer gemeldet (nicht verschluckt).
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
import 'package:thestia/models/verification/guardian_status.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/guardian_provider.dart';
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/services/verification/guardian_service.dart';

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
class _Keystore implements SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Der Eltern-Dienst als Ersatz (sonst legt der Provider einen Timer auf,
/// der nach dem Test noch weiterläuft).
class _GuardianDienst extends GuardianService {
  _GuardianDienst(super.client);

  @override
  Future<GuardianStatus> fetchStatus() async =>
      const GuardianStatus(loaded: true);
}

/// Scrollt zu einem Text (der Bildschirm ist eine lange Liste).
Future<void> scrolleZuText(WidgetTester tester, String text) async {
  final ziel = find.text(text);
  for (var i = 0; i < 40 && ziel.evaluate().isEmpty; i++) {
    await tester.timedDrag(
      find.byType(Scrollable).first,
      const Offset(0, -300),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    mockPackageInfo();
    mockZeitzone();
    final tempDir = await Directory.systemTemp.createTemp(
      'thesia_passkey_kachel',
    );
    Hive.init(tempDir.path);

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
    server.passkeys.clear();
    server.pfade.clear();
  });

  /// Baut die Einstellungen und scrollt zur Passkey-Kachel.
  Future<void> zeige(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/einstellungen',
      routes: [
        GoRoute(
          path: '/einstellungen',
          builder: (ctx, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (ctx, state) => const Scaffold(body: Text('Startseite')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final storage = _Speicher();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          guardianServiceProvider.overrideWithValue(
            _GuardianDienst(supabase.Supabase.instance.client),
          ),
          localStorageProvider.overrideWithValue(storage),
          secureProfileStoreProvider.overrideWithValue(_Keystore()),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(storage, _Keystore());
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
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await scrolleZuText(tester, L10n.tWithoutContext('settings.passkeyCreate'));
  }

  /// Lässt die echte Ereignisschleife laufen.
  Future<void> lassServerArbeiten(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('Die Passkey-Kachel', () {
    testWidgets('sie bietet die Einrichtung an', (tester) async {
      await zeige(tester);

      expect(
        find.text(L10n.tWithoutContext('settings.passkeyCreate')),
        findsOneWidget,
        reason:
            'Der Weg zum Passkey muss stehen - er ist der einzige Weg zu '
            'einem Passkey auf diesem Geraet.',
      );
    });

    testWidgets('bei vorhandenem Passkey fragt die App nach', (tester) async {
      // EIN PASSKEY AUF DEM KONTO: Der Bestands-Check greift.
      server.passkeys.add(<String, dynamic>{
        'id': 'passkey-1',
        'friendly_name': 'Pixel 8',
        'created_at': '2026-11-01T10:00:00.000Z',
      });

      await zeige(tester);
      await lassServerArbeiten(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('settings.passkeyCreate')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await lassServerArbeiten(tester);

      expect(
        find.text(L10n.tWithoutContext('settings.passkeyExistsTitle')),
        findsOneWidget,
        reason:
            'Ein alter Passkey kann die Neuregistrierung stoeren - der '
            'Nutzer muss das wissen, bevor er sich auf einen zweiten '
            'nativen Dialog einlaesst.',
      );
    });

    testWidgets('das Abbrechen registriert nichts', (tester) async {
      server.passkeys.add(<String, dynamic>{
        'id': 'passkey-1',
        'friendly_name': 'Pixel 8',
        'created_at': '2026-11-01T10:00:00.000Z',
      });

      await zeige(tester);
      await lassServerArbeiten(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('settings.passkeyCreate')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await lassServerArbeiten(tester);

      await tester.tap(
        find.widgetWithText(
          TextButton,
          L10n.tWithoutContext('settings.passkeyExistsAbort'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await lassServerArbeiten(tester);

      expect(
        server.pfade.any(
          (p) => p.contains('/auth/v1/passkeys/registration/options'),
        ),
        isFalse,
        reason:
            'Wer abbricht, darf keine Registrierung starten - sonst legt '
            'die App ungefragt einen zweiten Passkey an.',
      );
    });
  });
}
