// Das Speichern der elterlichen Einstellungen.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/settings/guardian_section.dart 99 offene Zeilen - genau
// der Teil, mit dem der Elternteil die Nutzungszeit ändert.
//
// DER GRUND: Hier geht es um die elterliche Aufsicht: die Nutzungszeit
// des Jugendlichen. Zwei Wege können hier schiefgehen:
//   * das Speichern geht nicht durch (die Änderung ist für den
//     Elternteil verloren),
//   * es wird die FALSCHE Nutzungszeit gespeichert.
// Der zweite Fall ist der teurere: eine falsche Zeit sperrt den
// Jugendlichen aus (oder lässt ihn durch).
//
// DIE PIN LÄUFT AUF DEM SERVER: Das Gerät kennt die PIN nie - der
// Vergleich passiert in der Datenbank (Migration 167). Deshalb wird
// hier der Server beantwortet, nicht die PIN nachgebaut.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/settings/guardian_section.dart';

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
    mockZeitzone();
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

  setUp(() {
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
    // Der Stand: das Konto steht unter Aufsicht, die Nutzungszeit ist
    // von 9:00 bis 20:00 begrenzt und es gibt eine PIN.
    server.rpcAntworten['get_my_guardian_status'] = <String, dynamic>{
      'consentState': 'granted',
      'supervised': true,
      'status': 'active',
      'age': 17,
      'guardianEmail': 'eltern@example.de',
      'usageLimitEnabled': true,
      'usageStartMin': 540,
      'usageEndMin': 1200,
      'hasPin': true,
      'accessPolicy': 'until_18',
      'loaded': true,
    };
    // Die PIN stimmt.
    server.rpcAntworten['verify_guardian_pin'] = true;
    // Das Speichern gelingt.
    server.rpcAntworten['set_guardian_settings_with_pin'] = <String, dynamic>{};
  });

  /// Baut den Abschnitt und wartet, bis der Stand geladen ist.
  Future<void> zeigeAbschnitt(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: GuardianSection())),
        ),
      ),
    );
    // Der Status kommt vom Server - das braucht echte Zeit.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Sperrt den Bereich mit der richtigen PIN auf.
  Future<void> entsperre(WidgetTester tester) async {
    final knopf = find.text(L10n.tWithoutContext('guardian.pinLocked'));
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pump();
    await tester.tap(find.text(L10n.tWithoutContext('common.ok')));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Tippt auf einen Knopf (er kann unterhalb der Falz liegen).
  Future<void> knopfTippen(WidgetTester tester, Finder knopf) async {
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Wartet, bis der Server geantwortet hat.
  Future<void> warteAufServer(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Der Aufruf des Speicherns (oder null, wenn es keinen gab).
  Map<String, dynamic>? speichernAufruf() {
    for (final aufruf in server.rpcAufrufe) {
      if (aufruf['funktion'] == 'set_guardian_settings_with_pin') {
        return aufruf;
      }
    }
    return null;
  }

  /// Öffnet den Zeit-Wähler und bestätigt ihn OHNE Änderung.
  ///
  /// DER WEG: Der Knopf wird über seinen INHALT gesucht (nicht über
  /// `find.text`) - im Dialog-Route trifft die Textsuche nicht
  /// zuverlässig.
  Future<void> waehlerBestaetigen(WidgetTester tester, String knopfText) async {
    // DER WEG: Der Zeit-Wähler ist breiter als ein Telefon-Bildschirm.
    // Auf einer schmalen Testfläche liegt sein Bestätigungs-Knopf
    // außerhalb - der Tipp ginge ins Leere. Darum wird hier breiter
    // gearbeitet.
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    await tester.pump();

    await knopfTippen(tester, find.text(knopfText));

    // Der Dialog braucht einen Moment, bis er ganz da ist.
    await tester.pump(const Duration(milliseconds: 400));

    final l10n = Localizations.of<MaterialLocalizations>(
      tester.element(find.byType(GuardianSection)),
      MaterialLocalizations,
    )!;
    final ok = find.byWidgetPredicate(
      (w) =>
          w is TextButton &&
          w.child is Text &&
          (w.child as Text).data == l10n.okButtonLabel,
    );
    expect(ok, findsOneWidget, reason: 'Der Zeit-Waehler muss aufgehen.');

    // Ohne Änderung bestätigen.
    await tester.tap(ok);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('Das Speichern der elterlichen Einstellungen', () {
    testWidgets('die Aenderung geht an den Server', (tester) async {
      await zeigeAbschnitt(tester);
      await entsperre(tester);

      // DER FALL: Der Elternteil schaltet die Nutzungszeit ab.
      final schalter = find.byType(Switch);
      expect(schalter, findsOneWidget);
      await knopfTippen(tester, schalter);

      await knopfTippen(
        tester,
        find.text(L10n.tWithoutContext('guardian.saveBtn')),
      );
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      final aufruf = speichernAufruf();
      expect(
        aufruf,
        isNotNull,
        reason: 'Die Aenderung muss an den Server gehen.',
      );
      expect(
        aufruf!['p_usage_limit_enabled'],
        isFalse,
        reason: 'Die abgeschaltete Nutzungszeit muss gespeichert werden.',
      );
      // Und der PIN ist mitgeschickt worden (ohne PIN nimmt der Server
      // die Änderung nicht an).
      expect(aufruf['p_pin'], '1234');
    });

    testWidgets('nach dem Speichern wird der Bereich wieder gesperrt', (
      tester,
    ) async {
      await zeigeAbschnitt(tester);
      await entsperre(tester);

      await knopfTippen(
        tester,
        find.text(L10n.tWithoutContext('guardian.saveBtn')),
      );
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.pinLocked')),
        findsOneWidget,
        reason:
            'Nach dem Speichern muss der Bereich wieder gesperrt sein - '
            'die PIN gilt nur fuer die Dauer der Bearbeitung.',
      );
    });

    testWidgets('eine falsche PIN beim Speichern wird abgewiesen', (
      tester,
    ) async {
      await zeigeAbschnitt(tester);
      await entsperre(tester);

      // DER FALL: Die PIN war beim Entsperren noch richtig, beim
      // Speichern nicht mehr (der Elternteil hat sie inzwischen
      // geändert, oder jemand anders hat sie geraten).
      server.rpcAntworten['set_guardian_settings_with_pin'] = <String, dynamic>{
        'error': 'wrong_pin',
      };

      await knopfTippen(
        tester,
        find.text(L10n.tWithoutContext('guardian.saveBtn')),
      );
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.pinWrong')),
        findsOneWidget,
        reason: 'Eine falsche PIN muss beim Speichern gemeldet werden.',
      );
      // Der Bereich bleibt offen - der Elternteil kann es nochmal
      // versuchen.
      expect(
        find.text(L10n.tWithoutContext('guardian.pinLocked')),
        findsNothing,
      );
    });

    testWidgets('ein Serverfehler beim Speichern wird gemeldet', (
      tester,
    ) async {
      await zeigeAbschnitt(tester);
      await entsperre(tester);

      server.rpcAntworten['set_guardian_settings_with_pin'] = <String, dynamic>{
        'error': 'kaputt',
      };

      await knopfTippen(
        tester,
        find.text(L10n.tWithoutContext('guardian.saveBtn')),
      );
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.errorGeneric')),
        findsOneWidget,
        reason:
            'Ein Serverfehler muss gemeldet werden - sonst glaubt der '
            'Elternteil, die Aenderung sei gespeichert.',
      );
    });

    testWidgets('die bestehende Startzeit bleibt erhalten', (tester) async {
      await zeigeAbschnitt(tester);
      await entsperre(tester);

      // DER FALL: Der Elternteil schaut nur in die Zeitauswahl (und
      // bestätigt sie, ohne etwas zu ändern). Die Grenze darf dabei
      // nicht springen.
      //
      // DER GRUND: Der Wähler muss mit dem aktuellen Wert starten.
      // Startet er mit einem anderen, springt die Grenze beim
      // Bestätigen - und der Jugendliche verliert oder gewinnt
      // Nutzungszeit, ohne dass es jemand bemerkt.
      await waehlerBestaetigen(
        tester,
        '${L10n.tWithoutContext('guardian.usageFrom')} 09:00',
      );

      await knopfTippen(
        tester,
        find.text(L10n.tWithoutContext('guardian.saveBtn')),
      );
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      final aufruf = speichernAufruf();
      expect(aufruf, isNotNull);
      expect(
        aufruf!['p_usage_start_min'],
        540,
        reason:
            'Die Startzeit (9:00) muss unveraendert gespeichert werden - '
            'ein Sprung auf 12:00 waere eine stille Aenderung der '
            'Nutzungszeit.',
      );
    });

    testWidgets('die bestehende Endzeit bleibt erhalten', (tester) async {
      await zeigeAbschnitt(tester);
      await entsperre(tester);

      await waehlerBestaetigen(
        tester,
        '${L10n.tWithoutContext('guardian.usageTo')} 20:00',
      );

      await knopfTippen(
        tester,
        find.text(L10n.tWithoutContext('guardian.saveBtn')),
      );
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      final aufruf = speichernAufruf();
      expect(aufruf, isNotNull);
      expect(
        aufruf!['p_usage_end_min'],
        1200,
        reason:
            'Die Endzeit (20:00) muss unveraendert gespeichert werden - '
            'ein Sprung auf 12:00 wuerde die Nutzungszeit auf null '
            'zusammenschrumpfen lassen.',
      );
    });
  });
}
