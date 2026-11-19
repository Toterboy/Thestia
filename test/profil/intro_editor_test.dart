// Der Vorstellungs-Editor (Text + Audio) - bisher ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/widgets/intro_editor.dart 260 offene Zeilen bei 333 Zeilen gesamt -
// der Editor, in dem die Person sich selbst vorstellt, war ungetestet.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Text wird gemeldet (der Text ist die Pflichtangabe),
//   * die Aufnahme startet und die Uhr laeuft,
//   * eine zu kurze Aufnahme wird abgelehnt (Mindestlaenge),
//   * das Verwerfen der Aufnahme fragt erst nach (die Aufnahme ist sonst
//     weg),
//   * das Loeschen der gespeicherten Aufnahme fragt erst nach,
//   * die Pflichtangabe: der Text allein reicht (die Aufnahme ist
//     optional).
//
// OHNE MIKROFON: Das Aufnahme-Plugin wird durch einen Ersatz beantwortet
// (test/support/plugin_mocks.dart) - es gibt im Test kein Mikrofon.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/supabase_storage_service.dart';
import 'package:thestia/widgets/intro_editor.dart';

import '../support/plugin_mocks.dart';

/// Der Speicher-Dienst ohne Server.
///
/// DER GRUND: Der echte Dienst braucht eine Anmeldung und den
/// Supabase-Client. Im Test reicht der Ersatz: er meldet das
/// Hochladen und das Loeschen zurueck.
class _FakeStorage extends SupabaseStorageService {
  _FakeStorage() : super(_dummyClient);

  /// Der Client wird nie benutzt (alle Methoden sind ueberschrieben).
  static final _dummyClient = supabase.Supabase.instance.client;

  /// Die hochgeladenen Daten (in Byte).
  final List<List<int>> hochgeladen = [];

  /// Wurde geloescht?
  bool geloescht = false;

  @override
  Future<String> uploadIntroAudio(List<int> data) async {
    hochgeladen.add(data);
    return 'hochgeladen/intro.m4a';
  }

  @override
  Future<void> deleteIntroAudio() async {
    geloescht = true;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER SPEICHER: Der Auth-Client des Supabase-Clients legt seinen
    // Token dort ab - ohne den Ersatz sucht der Test auf dem CI-Runner
    // das echte Plugin.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // DER CLIENT: Der Speicher-Fake braucht einen Client (der echte
    // Dienst auch). Ohne Initialisierung wirft `Supabase.instance` eine
    // Assertion.
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    // DIE AUFNAHME: Das Mikrofon wird ueber das Plugin bedient - ohne
    // den Ersatz wartet der Aufruf endlos.
    mockAufnahme();
  });

  /// Baut den Editor und liefert die gemeldeten Aenderungen.
  ///
  /// [audioPath] ist ein vorhandener Pfad (die Aufnahme ist gespeichert).
  Future<List<String?>> baueEditor(
    WidgetTester tester, {
    String? audioPath,
    bool required = true,
  }) async {
    final gemeldet = <String?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseStorageServiceProvider.overrideWithValue(_FakeStorage()),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            // DER GRUND FUER DIE SCROLL-ANSICHT: In der App sitzt der
            // Editor in einer langen Liste (die scrollt). Ohne das
            // laeuft der Editor hier ueber den Rand - nicht weil die App
            // kaputt waere, sondern weil der Test ihm den Rahmen
            // wegnimmt.
            body: SingleChildScrollView(
              child: IntroEditor(
                initialText: 'Hallo, ich bin Lena.',
                initialAudioPath: audioPath,
                required: required,
                onChanged: (text, pfad) => gemeldet.add(pfad),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return gemeldet;
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

  group('Der Vorstellungs-Editor', () {
    testWidgets('der Text wird gemeldet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final gemeldet = await baueEditor(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'Hallo, ich mag lange Spaziergaenge am Fluss.',
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        gemeldet,
        isNotEmpty,
        reason:
            'Der Text muss gemeldet werden - ohne ihn kann die App die '
            'Vorstellung nicht speichern.',
      );
    });

    testWidgets('die Aufnahme startet und die Uhr laeuft', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await baueEditor(tester);

      await knopfTippen(tester, L10n.tWithoutContext('intro.record'));
      // Das Mikrofon wird angefragt (das Plugin ist ein Ersatz).
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Aufnahme-Zustand steht da.
      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsOneWidget,
        reason: 'Der Nutzer muss sehen, dass gerade aufgenommen wird.',
      );
      // Und die Uhr zaehlt.
      expect(find.text('0:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:02'), findsOneWidget);
    });

    testWidgets('eine zu kurze Aufnahme wird abgelehnt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await baueEditor(tester);

      await knopfTippen(tester, L10n.tWithoutContext('intro.record'));
      await tester.pump(const Duration(milliseconds: 300));

      // Nach zwei Sekunden stoppen - die Mindestlaenge ist zehn Sekunden.
      await knopfTippen(tester, L10n.tWithoutContext('intro.stopListen'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Der Nutzer bekommt den Grund zu sehen.
      expect(
        find.textContaining('10'),
        findsWidgets,
        reason:
            'Eine zu kurze Aufnahme wird abgelehnt - der Nutzer muss wissen, '
            'wie lang sie sein muss.',
      );
    });

    testWidgets('das Verwerfen der Aufnahme fragt erst nach', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await baueEditor(tester);

      await knopfTippen(tester, L10n.tWithoutContext('intro.record'));
      await tester.pump(const Duration(milliseconds: 300));

      // Der Muell-Eimer verwirft die laufende Aufnahme. Er liegt unten
      // in der Aufnahme-Ansicht - erst dorthin scrollen, sonst trifft der
      // Tipp ins Leere.
      final muell = find.byTooltip(L10n.tWithoutContext('intro.discard'));
      await tester.ensureVisible(muell);
      await tester.pump();
      await tester.tap(muell);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Ohne Rueckfrage waere die Aufnahme weg - und der Nutzer haette sie
      // nicht behalten wollen.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('intro.discardTitle')),
        findsOneWidget,
      );

      // "Behalten" - die Aufnahme laeuft weiter.
      await tester.tap(
        find.widgetWithText(
          TextButton,
          L10n.tWithoutContext('intro.discardKeep'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsOneWidget,
      );
    });

    testWidgets('das Loeschen der Aufnahme fragt erst nach', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final gemeldet = await baueEditor(
        tester,
        audioPath: 'hochgeladen/intro.m4a',
      );

      // Der Muelleimer (nur da, wenn eine Aufnahme gespeichert ist).
      final knopf = find.byTooltip(L10n.tWithoutContext('intro.deleteTooltip'));
      expect(knopf, findsOneWidget);
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('intro.deleteTitle')),
        findsOneWidget,
      );

      // Bestaetigen - dann wird die Aufnahme gemeldet als weg.
      await tester.tap(
        find.widgetWithText(FilledButton, L10n.tWithoutContext('intro.delete')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        gemeldet,
        contains(null),
        reason:
            'Nach dem Loeschen muss der Editor melden, dass die Aufnahme weg '
            'ist - sonst speichert die App sie weiter.',
      );
    });

    test('der Text allein reicht als Pflichtangabe', () {
      // BEFUND (09.11.2026): "Es kann jedoch, wenn man sich vorstellt nur
      // eine textliche Vorstellung sein und die Audio kann man dann bei
      // einem Funken hoeren."
      expect(IntroEditor.isValid(text: 'Hallo, ich bin Lena.'), isTrue);
      expect(IntroEditor.isValid(text: '   '), isFalse);
      expect(IntroEditor.isValid(text: ''), isFalse);
      // Die Aufnahme ist optional.
      expect(IntroEditor.isValid(text: 'Hallo', audioPath: null), isTrue);
    });
  });
}
