// Die Geschlechts-Präferenz ("Ich suche").
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/settings/gender_preference_selector.dart 23 offene Zeilen
// bei 36 % Abdeckung. Die Mehrfachauswahl ist die Voreinstellung, mit der
// die App filtert - und "Alle" ist dabei die Besonderheit: ein erneuter
// Tipp auf "Alle" hebt die komplette Auswahl auf.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Chips stehen da ("Alle" plus die Geschlechter),
//   * ein Geschlecht lässt sich an- und abwählen,
//   * "Alle" wählt alle und hebt die Auswahl beim zweiten Tipp wieder auf,
//   * die Auswahl geht auch in die Datenbank (sie muss auf anderen
//     Geräten dieselbe sein).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/gender.dart';
import 'package:thestia/providers/settings/user_preferences_provider.dart';
import 'package:thestia/widgets/settings/gender_preference_selector.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

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
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() {
    server.zeilen.clear();
    server.schreibvorgaenge.clear();
  });

  /// Baut die Auswahl.
  Future<ProviderContainer> baue(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: GenderPreferenceSelector()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  /// Lässt den entprellten Server-Sync ablaufen (1,5 Sekunden).
  ///
  /// DER GRUND: Der Sync-Timer läuft sonst beim Testende noch - der
  /// Test scheitert dann an "Timer is still pending".
  Future<void> syncAblaufenLassen(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Die Geschlechts-Präferenz', () {
    testWidgets('die Chips stehen da', (tester) async {
      await baue(tester);

      expect(
        find.text(L10n.tWithoutContext('genderpref.all')),
        findsOneWidget,
        reason: '"Alle" ist die Kurzform fuer alle Geschlechter.',
      );
      for (final gender in Gender.values) {
        expect(
          find.text(L10n.tWithoutContext(gender.labelKey)),
          findsOneWidget,
          reason: 'Jedes Geschlecht braucht seinen eigenen Chip.',
        );
      }
    });

    testWidgets('ein Geschlecht lässt sich wählen und abwählen', (
      tester,
    ) async {
      final container = await baue(tester);
      final chip = find.text(L10n.tWithoutContext(Gender.female.labelKey));

      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(userPreferencesProvider).genderPreferences,
        contains(Gender.female.value),
        reason: 'Das gewaehlte Geschlecht muss gespeichert werden.',
      );

      // NOCHMAL: Jetzt ist es wieder abgewahlt.
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(userPreferencesProvider).genderPreferences,
        isNot(contains(Gender.female.value)),
        reason: 'Der zweite Tipp nimmt die Auswahl zurueck.',
      );

      await syncAblaufenLassen(tester);
    });

    testWidgets('"Alle" wählt alle und hebt die Auswahl wieder auf', (
      tester,
    ) async {
      final container = await baue(tester);
      final alle = find.text(L10n.tWithoutContext('genderpref.all'));

      await tester.tap(alle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(userPreferencesProvider).genderPreferences.length,
        kAllGenderValues.length,
        reason: '"Alle" heisst alle Geschlechter.',
      );

      // NOCHMAL: Die Auswahl ist weg (sonst kännte man "Alle" nie
      // abwählen).
      await tester.tap(alle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(userPreferencesProvider).genderPreferences,
        isEmpty,
        reason:
            'Der zweite Tipp auf "Alle" hebt die komplette Auswahl auf - '
            'sonst waere "Alle" nie wieder wegzuwaehlen.',
      );

      await syncAblaufenLassen(tester);
    });

    testWidgets('die Auswahl geht in die Datenbank', (tester) async {
      await baue(tester);

      await tester.tap(find.text(L10n.tWithoutContext(Gender.male.labelKey)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // DER SERVER: Die Auswahl muss auch dort ankommen - sonst sieht der
      // Nutzer auf einem anderen Gerät etwas anderes.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });
        await tester.pump(const Duration(milliseconds: 60));
      }

      final schreibvorgaenge = server.schreibvorgaenge
          .where((v) => v['tabelle'] == 'profiles')
          .toList();
      expect(
        schreibvorgaenge,
        isNotEmpty,
        reason:
            'Die Praeferenz muss in die Datenbank - sonst ist sie auf '
            'anderen Geraeten weg.',
      );

      await syncAblaufenLassen(tester);
    });
  });
}
