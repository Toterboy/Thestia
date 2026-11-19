// Der Kinderschutz-Abschnitt in den Einstellungen.
//
// ANLASS (16.11.2026): Die Coverage-Messung zeigte fuer
// lib/widgets/guardian_section.dart 256 offene Zeilen - und gerade hier
// geht es um die elterliche Aufsicht (Nutzungszeit, PIN).
//
// WAS HIER GEPRUEFT WIRD:
//   * der Stand kommt vom Server und wird angezeigt,
//   * das Entsperren fragt nach der vierstelligen PIN,
//   * eine falsche PIN (zu kurz oder falsch) wird abgewiesen,
//   * die richtige PIN schaltet die Aenderungen frei.
//
// DIE PIN LAEUFT AUF DEM SERVER: Das Geraet kennt die PIN nie - der
// Vergleich passiert in der Datenbank (Migration 167). Deshalb wird
// hier der Server beantwortet, nicht die PIN nachgebaut.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/guardian_section.dart';

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
    // HIVE: der Signal-Dienst (der im Hintergrund mitlaeuft) liest seine
    // verschluesselten Boxen - ohne initialisierten Hive scheitert der
    // Aufbau.
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
    // Der Stand: das Konto steht unter Aufsicht, die Nutzungszeit ist
    // begrenzt und es gibt eine PIN.
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
  });

  /// Baut den Abschnitt und wartet, bis der Stand geladen ist.
  Future<void> zeigeAbschnitt(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            // Der Abschnitt ist laenger als der Bildschirm - in der App
            // steht er in einer scrollbaren Liste.
            body: SingleChildScrollView(child: GuardianSection()),
          ),
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

  group('Der Kinderschutz-Abschnitt', () {
    testWidgets('der Stand kommt vom Server', (tester) async {
      await zeigeAbschnitt(tester);

      expect(tester.takeException(), isNull);
      // Die Nutzungszeit steht da (9:00 bis 20:00).
      expect(find.textContaining('09:00'), findsWidgets);
      expect(find.textContaining('20:00'), findsWidgets);
    });

    testWidgets('das Entsperren fragt nach der PIN', (tester) async {
      await zeigeAbschnitt(tester);

      final knopf = find.text(L10n.tWithoutContext('guardian.pinLocked'));
      expect(knopf, findsOneWidget);
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('guardian.unlockTitle')),
        findsOneWidget,
      );
    });

    testWidgets('eine zu kurze PIN wird abgewiesen', (tester) async {
      await zeigeAbschnitt(tester);

      final knopf = find.text(L10n.tWithoutContext('guardian.pinLocked'));
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Drei Ziffern sind keine PIN.
      await tester.enterText(find.byType(TextField).first, '123');
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('common.ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.pinWrong')),
        findsOneWidget,
        reason:
            'Eine zu kurze PIN muss abgewiesen werden - die Aenderung an '
            'der Nutzungszeit gehoert dem Elternteil.',
      );
    });

    testWidgets('die falsche PIN wird abgewiesen', (tester) async {
      await zeigeAbschnitt(tester);
      // Der Server lehnt die PIN ab.
      server.rpcAntworten['verify_guardian_pin'] = false;

      final knopf = find.text(L10n.tWithoutContext('guardian.pinLocked'));
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField).first, '9999');
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('common.ok')));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.pinWrong')),
        findsOneWidget,
        reason: 'Eine falsche PIN muss abgewiesen werden.',
      );
      // Und der Server wurde gefragt (der Vergleich laeuft dort).
      expect(
        server.pfade.any((p) => p.contains('verify_guardian_pin')),
        isTrue,
      );

      // UND: Der Bereich bleibt gesperrt - die Nutzungszeit des
      // Jugendlichen darf nur der Elternteil aendern.
      expect(
        find.text(L10n.tWithoutContext('guardian.pinLocked')),
        findsOneWidget,
        reason:
            'Nach einer falschen PIN muss der Bereich gesperrt bleiben - '
            'sonst koennte der Jugendliche seine Nutzungszeit selbst '
            'aendern.',
      );
    });

    testWidgets('die richtige PIN schaltet die Aenderungen frei', (
      tester,
    ) async {
      await zeigeAbschnitt(tester);
      // Der Server bestaetigt die PIN.
      server.rpcAntworten['verify_guardian_pin'] = true;

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

      expect(tester.takeException(), isNull);
      // Der Sperr-Knopf ist weg - jetzt kann bearbeitet werden.
      expect(
        find.text(L10n.tWithoutContext('guardian.pinLocked')),
        findsNothing,
        reason:
            'Mit der richtigen PIN muss die Bearbeitung moeglich sein - '
            'sonst kann der Elternteil gar nichts aendern.',
      );
    });
  });
}
