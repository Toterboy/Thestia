// Der Datenimport auf dem Datenschutz-Screen.
//
// ANLASS (19.11.2026): Der Export war getestet, der IMPORT nicht -
// `lib/screens/privacy/privacy_screen.dart` war nur zu 36 % abgedeckt.
// Der Import ist das Gegenstueck zum Export (DSGVO Art. 20): wer seine
// Daten mitgenommen hat, muss sie auch wiederherstellen koennen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Dialog fragt nach dem JSON und bricht ab, wenn man abbricht,
//   * kaputtes JSON wird abgewiesen (kein Absturz, kein halber Import),
//   * ein gueltiges JSON stellt Profil, Einstellungen und Praeferenzen
//     wieder her.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/screens/privacy/privacy_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM (der Screen braucht Profil und Einstellungen).
class _FakeLocalStorage implements LocalStorage {
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
  late FakeSupabaseServer server;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockKeystore();
    mockZeitzone();
    await mockPfadProvider();

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

  Future<ProviderContainer> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(_FakeLocalStorage()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PrivacyScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  /// Tippt den Import-Knopf (der Screen ist eine lange Liste).
  Future<void> tippeImport(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('privacy.import'));
    if (knopf.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        knopf,
        320,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.tap(knopf);
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Fuellt den Dialog mit JSON und bestaetigt (oder verwirft).
  Future<void> fuelleDialog(
    WidgetTester tester,
    String inhalt, {
    bool bestaetigen = true,
  }) async {
    await tester.enterText(find.byType(TextField), inhalt);
    await tester.pump();
    final knopf = find.text(
      L10n.tWithoutContext(
        bestaetigen ? 'privacy.importApply' : 'common.cancel',
      ),
    );
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // DER IMPORT STARTET TIMER: Das Speichern der Praeferenzen ist
    // verzoegert (Server-Abgleich). Ohne das Wenden laeuft der Timer
    // noch, wenn der Test endet - der Test waere rot.
    await tester.pump(const Duration(seconds: 2));
  }

  group('Der Import-Dialog', () {
    testWidgets('er fragt nach dem JSON', (tester) async {
      await zeigeScreen(tester);
      await tippeImport(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('privacy.importTitle')),
        findsWidgets,
      );
    });

    testWidgets('abbrechen aendert nichts', (tester) async {
      final container = await zeigeScreen(tester);
      await tippeImport(tester);
      await fuelleDialog(
        tester,
        jsonEncode(<String, dynamic>{
          'profile': <String, dynamic>{'id': 'x', 'name': 'Importiert'},
        }),
        bestaetigen: false,
      );

      expect(
        container.read(profileProvider).name,
        isNot('Importiert'),
        reason: 'Nach dem Abbrechen darf nichts uebernommen werden.',
      );
    });
  });

  group('Der Import', () {
    testWidgets('kaputtes JSON wird abgewiesen', (tester) async {
      final container = await zeigeScreen(tester);
      await tippeImport(tester);
      await fuelleDialog(tester, 'kein json {');

      expect(
        find.text(L10n.tWithoutContext('privacy.importInvalid')),
        findsWidgets,
        reason: 'Der Nutzer muss sehen, dass seine Datei nicht passt.',
      );
      expect(container.read(profileProvider).name, isNot('Importiert'));
    });

    testWidgets('das Profil wird wiederhergestellt', (tester) async {
      final container = await zeigeScreen(tester);
      await tippeImport(tester);
      await fuelleDialog(
        tester,
        jsonEncode(<String, dynamic>{
          'profile': <String, dynamic>{
            'id': 'x',
            'name': 'Importiert',
            'bio': 'Aus dem Export',
          },
        }),
      );

      expect(container.read(profileProvider).name, 'Importiert');
      expect(container.read(profileProvider).bio, 'Aus dem Export');
    });

    testWidgets('die Einstellungen werden uebernommen', (tester) async {
      final container = await zeigeScreen(tester);
      await tippeImport(tester);
      await fuelleDialog(
        tester,
        jsonEncode(<String, dynamic>{
          'settings': <String, dynamic>{'useDarkMode': true},
        }),
      );

      expect(
        container.read(settingsProvider).useDarkMode,
        isTrue,
        reason: 'Der Dunkelmodus muss aus dem Export kommen.',
      );
    });

    testWidgets('die Praeferenzen werden uebernommen', (tester) async {
      final container = await zeigeScreen(tester);
      await tippeImport(tester);
      await fuelleDialog(
        tester,
        jsonEncode(<String, dynamic>{
          'preferences': <String, dynamic>{'maxDistanceKm': 80},
        }),
      );

      expect(container.read(userPreferencesProvider).maxDistanceKm, 80);
    });
  });
}
