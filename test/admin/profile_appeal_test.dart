// Der Foto-Einspruch im Profil-Editor (bisher ungetestet).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/profile/profile_edit_screen.dart 399 offene Zeilen.
//
// WARUM DAS WICHTIG IST: Wird ein Profilbild von der Moderation
// gesperrt, kann der Nutzer dagegen Einspruch einlegen. Das Team
// entscheidet - und die Entscheidung kommt ueber die Edge Function
// `get_my_photo_appeal` zurueck:
//   * approved = das Bild darf wieder als Profilbild dienen,
//   * rejected = die Sperre bleibt, und der Nutzer bekommt das gesagt.
//
// WAS HIER GEPRUEFT WIRD:
//   * ein genehmigter Einspruch fragt nach, bevor das Bild uebernommen
//     wird,
//   * ein abgelehnter Einspruch wird dem Nutzer gemeldet,
//   * die Entscheidung wird dem Server quittiert.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/screens/profile/profile_edit_screen.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

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
  });

  setUp(() {
    server.rpcAntworten.clear();
    server.pfade.clear();
    server.funktionsAufrufe.clear();
  });

  /// Baut den Profil-Editor.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
        child: const MaterialApp(home: ProfileEditScreen()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  group('Der Foto-Einspruch', () {
    testWidgets('ein genehmigter Einspruch fragt nach', (tester) async {
      server.rpcAntworten['get_my_photo_appeal'] = <String, dynamic>{
        'id': 'appeal-1',
        'status': 'approved',
        'storagePath': 'appeals/1.jpg',
      };
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Der Nutzer wird gefragt - das Bild wird nicht ungefragt gesetzt.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('profile.appeal.approvedTitle')),
        findsOneWidget,
      );

      // Der Dialog wird geschlossen - erst danach quittiert die App die
      // Entscheidung beim Server.
      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // Und die Entscheidung wird dem Server quittiert.
      expect(
        server.pfade.any((p) => p.contains('acknowledge_photo_appeal')),
        isTrue,
        reason:
            'Die Entscheidung muss quittiert werden - sonst fragt die App '
            'bei jedem Oeffnen erneut.',
      );
    });

    testWidgets('ein abgelehnter Einspruch wird gemeldet', (tester) async {
      server.rpcAntworten['get_my_photo_appeal'] = <String, dynamic>{
        'id': 'appeal-2',
        'status': 'rejected',
        'storagePath': 'appeals/2.jpg',
      };
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('profile.appeal.rejectedTitle')),
        findsOneWidget,
      );

      // Der Dialog wird geschlossen - erst danach quittiert die App die
      // Entscheidung beim Server.
      await tester.tap(find.text(L10n.tWithoutContext('profile.appeal.okBtn')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // Auch hier wird quittiert.
      expect(
        server.pfade.any((p) => p.contains('acknowledge_photo_appeal')),
        isTrue,
      );
    });

    testWidgets('ohne Einspruch passiert nichts', (tester) async {
      server.rpcAntworten['get_my_photo_appeal'] = null;
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      // Kein Dialog - der Nutzer wird nicht mit etwas belastet, das es
      // nicht gibt.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('der Editor baut sich ohne Absturz', (tester) async {
      server.rpcAntworten['get_my_photo_appeal'] = null;
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ProfileEditScreen), findsOneWidget);
    });
  });
}
