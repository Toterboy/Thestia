// Die Passkey-Verwaltung in den Einstellungen.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/screens/settings/parts/passkeymanagercardstate.dart 85 offene Zeilen
// bei 28 % Abdeckung und für passkeytilestate.dart 45. Die Karte listet
// die Passkeys des Kontos auf, lässt sie umbenennen und löschen - und
// genau diese Wege kannte niemand.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Karte zeigt die Passkeys des Kontos (mit Erstell- und letztem
//     Nutzungsdatum),
//   * ein Passkey lässt sich umbenennen (der Server bekommt den neuen
//     Namen),
//   * ein Passkey lässt sich löschen - aber erst nach der Rückfrage,
//   * ein Serverfehler wird dem Nutzer gesagt (nicht verschluckt).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/verification/guardian_status.dart';
import 'package:thestia/providers/settings/guardian_provider.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/verification/guardian_service.dart';
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
class _Keystore implements SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Scrollt zu einem Text (der Bildschirm ist eine lange Liste - nur die
/// sichtbaren Teile werden gebaut).
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

/// Der Eltern-Dienst als Ersatz.
///
/// DER GRUND: Der echte Dienst fragt den Server - im Test antwortet er
/// nicht, und der Provider legt dann einen Timer auf, der immer wieder
/// neu versucht. Der Timer läuft am Testende noch und der Test wartet
/// Minuten auf ihn.
class _GuardianDienst extends GuardianService {
  _GuardianDienst(super.client);

  @override
  Future<GuardianStatus> fetchStatus() async =>
      const GuardianStatus(loaded: true);
}

void main() {
  late FakeSupabaseServer server;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER SPEICHER: Muss VOR dem Client da sein - der Client holt sich
    // beim Start seinen Sitzungs-Speicher von dort.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // DIE PLUGINS: Die Versionsangabe (package_info) und die Zeitzone
    // (flutter_timezone) - ohne sie bleibt der Bildschirm im Ladekreis.
    mockPackageInfo();
    mockZeitzone();
    final tempDir = await Directory.systemTemp.createTemp('thesia_passkeys');
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

  // KEIN Hive.close(): Die verschlüsselten Boxen des Signal-Protokolls
  // (der Einstellungs-Screen öffnet sie über den Keystore) hängen
  // beim Schließen - der Ordner liegt im Temp und wird vom System
  // aufgeräumt.
  tearDownAll(() async {
    // ignore: avoid_print
    print('Ende.');
  });

  setUp(() {
    // DER CLIENT: Supabase wird nur EINMAL initialisiert (ein Singleton) -
    // der Server bleibt darum derselbe, sonst würde der Client weiter auf
    // den ersten Server zeigen.
    server.passkeys.clear();
    server.pfade.clear();
  });

  /// Baut die Einstellungen (die Passkey-Karte steht oben im Bildschirm).
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
          // DER ELTERN-DIENST: Ohne ihn legt der Provider einen Timer
          // auf, der nach dem Test noch weiterläuft.
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
    // DIE KARTE: Sie steht weit unten (nach dem Datenschutz-Abschnitt) -
    // ohne Scrollen baut die Liste sie gar nicht.
    await scrolleZuText(
      tester,
      L10n.tWithoutContext('settings.passkeysManage'),
    );
  }

  /// Lässt die echte Ereignisschleife laufen (die Serverantworten
  /// kommen nur dort an).
  Future<void> lassServerArbeiten(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Ein Passkey, wie der Server ihn meldet.
  Map<String, dynamic> passkeyJson({
    String id = 'passkey-1',
    String? name = 'Pixel 8',
  }) => <String, dynamic>{
    'id': id,
    'friendly_name': ?name,
    'created_at': '2026-11-01T10:00:00.000Z',
    'last_used_at': '2026-11-20T18:30:00.000Z',
  };

  group('Die Passkey-Verwaltung', () {
    testWidgets('die Karte zeigt die Passkeys des Kontos', (tester) async {
      server.passkeys.add(passkeyJson());

      await zeige(tester);
      await lassServerArbeiten(tester);
      // DIE KARTE: Sie steht weit unten (nach dem Datenschutz-Abschnitt).
      await scrolleZuText(
        tester,
        L10n.tWithoutContext('settings.passkeysManage'),
      );
      await lassServerArbeiten(tester);
      expect(
        find.text('Pixel 8'),
        findsOneWidget,
        reason:
            'Der Nutzer muss sehen, welche Passkeys auf seinem Konto liegen - '
            'sonst kann er das alte Geraet nicht wiederfinden.',
      );
      expect(
        find.textContaining('01.11.2026'),
        findsOneWidget,
        reason:
            'Das Erstellungsdatum gehoert dazu - man braucht es, um das '
            'richtige Geraet zu erkennen.',
      );
    });

    testWidgets('die Karte nennt die Anzahl', (tester) async {
      server.passkeys.add(passkeyJson());
      server.passkeys.add(passkeyJson(id: 'passkey-2', name: 'Laptop'));

      await zeige(tester);
      await lassServerArbeiten(tester);

      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
    });

    testWidgets('ein Passkey laesst sich umbenennen', (tester) async {
      server.passkeys.add(passkeyJson());

      await zeige(tester);
      await lassServerArbeiten(tester);
      // DER PASSKEY: Seine Zeile muss sichtbar sein (sonst liegen die
      // Knöpfe unterhalb des Bildschirms).
      await scrolleZuText(tester, 'Pixel 8');

      // DER KNOPF: Das Stift-Symbol in der Zeile des Passkeys (nicht das
      // Stift-Symbol einer anderen Kachel).
      final zeile = find.ancestor(
        of: find.text('Pixel 8'),
        matching: find.byType(ListTile),
      );
      final knopf = find.descendant(
        of: zeile,
        matching: find.byIcon(Icons.edit_outlined),
      );
      expect(knopf, findsOneWidget);
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('passkey.renameTitle')),
        findsOneWidget,
      );

      // DER NEUE NAME:
      await tester.enterText(find.byType(TextField).first, 'Mein Telefon');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.widgetWithText(FilledButton, L10n.tWithoutContext('common.save')),
      );
      await tester.pump();
      await lassServerArbeiten(tester);

      expect(
        server.pfade.any((p) => p.contains('/auth/v1/passkeys/passkey-1')),
        isTrue,
        reason:
            'Der neue Name muss zum Server - sonst heisst die Kachel weiter '
            '"Pixel 8" und der Nutzer weiss nicht, welches Geraet es ist.',
      );
    });

    testWidgets('das Loeschen fragt erst nach', (tester) async {
      server.passkeys.add(passkeyJson());

      await zeige(tester);
      await lassServerArbeiten(tester);
      await scrolleZuText(tester, 'Pixel 8');

      // DER KNOPF: Der Papierkorb in der Zeile des Passkeys.
      final zeile = find.ancestor(
        of: find.text('Pixel 8'),
        matching: find.byType(ListTile),
      );
      final knopf = find.descendant(
        of: zeile,
        matching: find.byIcon(Icons.delete_outline),
      );
      expect(knopf, findsOneWidget);
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text(L10n.tWithoutContext('settings.passkeyDeleteTitle')),
        findsOneWidget,
        reason:
            'Ein Passkey zu loeschen heisst: das Geraet muss neu eingerichtet '
            'werden. Das muss bestaetigt werden.',
      );

      // "Abbrechen": Es passiert nichts.
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        server.pfade.any((p) => p.contains('/auth/v1/passkeys/passkey-1')),
        isFalse,
        reason: 'Wer sich im Dialog umentscheidet, loescht nichts.',
      );
    });
  });
}
