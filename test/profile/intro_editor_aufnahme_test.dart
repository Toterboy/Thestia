// Die Aufnahme-Steuerung des Vorstellungs-Editors.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/profile/intro_editor.dart 104 offene Zeilen. Genau die
// Aufnahme-Steuerung war ungetestet: die Mikrofon-Ablehnung, das
// Anhalten und das Fortsetzen.
//
// DER GRUND: Der Nutzer stellt sich mit einem Audio vor. Wenn das
// Mikrofon fehlt, muss er das ERFAHREN (sonst passiert beim Tippen
// nichts). Und wenn er beim Sprechen unterbrochen wird, muss er
// anhalten können - ohne dass die Uhr weiterzählt: eine Aufnahme
// darf nicht still im Hintergrund weiterlaufen, nur weil der Nutzer
// kurz Pause gemacht hat.
//
// OHNE MIKROFON: Das Aufnahme-Plugin wird durch einen Ersatz
// beantwortet (test/support/plugin_mocks.dart) - es gibt im Test kein
// Mikrofon.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/server/supabase_storage_service.dart';
import 'package:thestia/widgets/profile/intro_editor.dart';

import '../support/plugin_mocks.dart';

/// Der Speicher-Dienst ohne Server.
///
/// DER GRUND: Der echte Dienst braucht eine Anmeldung und den
/// Supabase-Client. Im Test reicht der Ersatz: er meldet das
/// Hochladen und das Löschen zurück.
class _FakeStorage extends SupabaseStorageService {
  _FakeStorage() : super(_dummyClient);

  /// Der Client wird nie benutzt (alle Methoden sind überschrieben).
  static final _dummyClient = supabase.Supabase.instance.client;

  @override
  Future<String> uploadIntroAudio(List<int> data) async =>
      'hochgeladen/intro.m4a';

  @override
  Future<void> deleteIntroAudio() async {
    // Der Test löscht keine Aufnahme vom Server.
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    // DER GRUND: Der Standard ist "erlaubt" - die Tests, die die
    // Ablehnung brauchen, stellen ihn selbst um.
    mockAufnahme();
  });

  /// Baut den Editor.
  Future<void> baueEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseStorageServiceProvider.overrideWithValue(_FakeStorage()),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: IntroEditor(
                initialText: 'Hallo, ich bin Lena.',
                initialAudioPath: null,
                required: true,
                onChanged: (text, pfad) {
                  // Der Test braucht die Meldung nicht.
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Tippt auf einen Knopf (der Knopf kann unterhalb der Falz liegen).
  Future<void> knopfTippen(WidgetTester tester, String text) async {
    final knopf = find.text(text);
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Tippt auf den Aufnahme-Knopf und wartet, bis die Aufnahme läuft.
  Future<void> aufnahmeStarten(WidgetTester tester) async {
    await knopfTippen(tester, L10n.tWithoutContext('intro.record'));
    // Das Mikrofon wird angefragt (das Plugin ist ein Ersatz).
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Die Aufnahme-Steuerung', () {
    testWidgets('ohne Mikrofon gibt es einen Hinweis', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // DER FALL: Der Nutzer hat dem Mikrofon nicht zugestimmt (oder er
      // hat es versehentlich abgelehnt).
      mockAufnahme(erlaubt: false);
      await baueEditor(tester);

      await aufnahmeStarten(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('intro.micDenied')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass das Mikrofon fehlt - sonst '
            'tippt er auf "Aufnehmen" und es passiert nichts.',
      );
      // Und es wurde NICHT aufgenommen.
      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsNothing,
      );
    });

    testWidgets('die Aufnahme laesst sich anhalten und fortsetzen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await baueEditor(tester);
      await aufnahmeStarten(tester);

      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsOneWidget,
      );

      // Anhalten.
      await knopfTippen(tester, L10n.tWithoutContext('intro.pause'));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('intro.pausedState')),
        findsOneWidget,
        reason: 'Der Nutzer muss sehen, dass die Aufnahme angehalten ist.',
      );
      expect(
        find.widgetWithText(
          OutlinedButton,
          L10n.tWithoutContext('intro.resume'),
        ),
        findsOneWidget,
        reason: 'Der Knopf muss jetzt zum Fortsetzen einladen.',
      );

      // Fortsetzen.
      await knopfTippen(tester, L10n.tWithoutContext('intro.resume'));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          OutlinedButton,
          L10n.tWithoutContext('intro.pause'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('im Pausenzustand zaehlt die Uhr nicht', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await baueEditor(tester);
      await aufnahmeStarten(tester);

      // Die Uhr läuft.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:02'), findsOneWidget);

      // Anhalten: ab jetzt zählt die Uhr nicht mehr. Sonst wäre die
      // Aufnahme nach dem Anhalten länger, obwohl der Nutzer nicht
      // gesprochen hat - und sie kännte dadurch zu kurz oder zu lang
      // werden.
      await knopfTippen(tester, L10n.tWithoutContext('intro.pause'));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('0:02'), findsOneWidget);

      // Nach dem Fortsetzen läuft sie weiter.
      await knopfTippen(tester, L10n.tWithoutContext('intro.resume'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:04'), findsOneWidget);
    });
  });
}
