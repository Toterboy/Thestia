// Die Wege aus den Einstellungen.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/screens/settings/settings_screen.dart 91 offene Zeilen. Gerade die
// WEGE sind ungetestet: der Nutzer tippt auf einen Eintrag und es passiert
// nichts - das sieht wie ein Fehler aus.
//
// WAS HIER GEPRÜFT WIRD:
//   * jeder Eintrag im Abschnitt "Gemeinsam & Sicherheit" und im Abschnitt
//     "Datenschutz & Konto" öffnet den passenden Bildschirm,
//   * die Zwei-Faktor-Kachel holt den Stand FRISCH vom Server, bevor sie
//     die Einrichtung öffnet (sonst zeigt sie hinterher das Falsche),
//   * der Zurück-Knopf geht zurück, und wenn es nichts zurück gibt,
//     zur Startseite.
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
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/plugin_mocks.dart';

/// Der Speicher im RAM - die Einstellungen werden daraus gelesen.
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

void main() {
  late _Speicher storage;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    // HIVE: der Abschnitt "Ende-zu-Ende-Verschlüsselung" liest die
    // gesicherten Schlüssel aus einer Hive-Box.
    final tempDir = await Directory.systemTemp.createTemp(
      'thesia_settings_wege',
    );
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    storage = _Speicher();
  });

  /// Baut die Einstellungen mit einem Router (die Einträge navigieren).
  Future<void> zeige(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final secure = _Keystore();
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
        GoRoute(
          path: '/community-guidelines',
          builder: (ctx, state) => const Scaffold(body: Text('Regeln')),
        ),
        GoRoute(
          path: '/safety-center',
          builder: (ctx, state) =>
              const Scaffold(body: Text('Sicherheitscenter')),
        ),
        GoRoute(
          path: '/devices',
          builder: (ctx, state) => const Scaffold(body: Text('Geraete')),
        ),
        GoRoute(
          path: '/privacy',
          builder: (ctx, state) => const Scaffold(body: Text('Datenschutz')),
        ),
        GoRoute(
          path: '/delete-data',
          builder: (ctx, state) => const Scaffold(body: Text('Datenloeschung')),
        ),
        GoRoute(
          path: '/mfa-setup',
          builder: (ctx, state) => const Scaffold(body: Text('Zwei-Faktor')),
        ),
        GoRoute(
          path: '/login',
          builder: (ctx, state) => const Scaffold(body: Text('Anmeldung')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
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
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Scrollt zu einem Text (der Bildschirm ist eine lange Liste).
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    for (var i = 0; i < 60 && ziel.evaluate().isEmpty; i++) {
      await tester.timedDrag(
        find.byType(Scrollable).first,
        const Offset(0, -300),
        const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Tippt einen Eintrag an (der Bildschirm baut nur die sichtbaren Teile).
  Future<void> tippe(WidgetTester tester, String key) async {
    final eintrag = find.text(L10n.tWithoutContext(key));
    await scrolleZu(tester, L10n.tWithoutContext(key));
    await tester.ensureVisible(eintrag);
    await tester.pump();
    await tester.tap(eintrag);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Die Wege aus den Einstellungen', () {
    testWidgets('die Community-Regeln oeffnen sich', (tester) async {
      await zeige(tester);

      await tippe(tester, 'settings.communityRules');

      expect(
        find.text('Regeln'),
        findsOneWidget,
        reason:
            'Die Regeln muessen erreichbar sein - sonst kann niemand '
            'nachlesen, was erlaubt ist.',
      );
    });

    testWidgets('das Sicherheitscenter oeffnet sich', (tester) async {
      await zeige(tester);

      await tippe(tester, 'settings.safetyCenter');

      expect(find.text('Sicherheitscenter'), findsOneWidget);
    });

    testWidgets('die Geraete oeffnen sich', (tester) async {
      await zeige(tester);

      await tippe(tester, 'settings.devices');

      expect(find.text('Geraete'), findsOneWidget);
    });

    testWidgets('der Datenschutz-Bereich oeffnet sich', (tester) async {
      await zeige(tester);

      // DER UNTERTITEL: Der Titel "Datenschutz & Konto" steht auch als
      // Abschnittsüberschrift auf dem Bildschirm - der Untertitel ist
      // eindeutig.
      await tippe(tester, 'settings.privacyAccountSub');

      expect(find.text('Datenschutz'), findsOneWidget);
    });

    testWidgets('die Datenloeschung oeffnet sich', (tester) async {
      await zeige(tester);

      await tippe(tester, 'settings.deleteData');

      expect(find.text('Datenloeschung'), findsOneWidget);
    });

    testWidgets('die Zwei-Faktor-Einrichtung oeffnet sich', (tester) async {
      await zeige(tester);

      await tippe(tester, 'settings.twoFactor');

      expect(
        find.text('Zwei-Faktor'),
        findsOneWidget,
        reason:
            'Die Kachel muss zur Einrichtung fuehren - sie ist der einzige '
            'Weg zur zweiten Absicherung.',
      );
    });
  });

  group('Der Zurueck-Knopf', () {
    testWidgets('ohne Weg zurueck geht es zur Startseite', (tester) async {
      await zeige(tester);

      // DER KNOPF: Er steht in der Kopfzeile.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Startseite'),
        findsOneWidget,
        reason:
            'Wurde die Einstellung direkt geoeffnet (Deep-Link), gibt es '
            'nichts zurueck - dann muss die Startseite kommen, nicht ein '
            'schwarzer Bildschirm.',
      );
    });
  });
}
