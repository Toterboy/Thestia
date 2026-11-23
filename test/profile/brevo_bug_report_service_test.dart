// Der Versand eines Bug-Reports (per E-Mail ueber Brevo).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/profile/brevo_bug_report_service.dart offene Zeilen. Der
// Versand ist der einzige Weg, mit dem der Nutzer der App einen Fehler
// melden kann - und er schickt dabei Bildschirmshots mit.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Report geht an die Edge Function (mit der Beschreibung und den
//     Geraeteinformationen),
//   * die Bilder kommen an - aber hoechstens fuenf,
//   * eine zu lange Beschreibung wird abgelehnt (der Server wuerde sie
//     ohnehin ablehnen - der Client soll es sofort sagen),
//   * ein Serverfehler wird als "nicht gesendet" gemeldet (nicht als
//     Erfolg).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thestia/services/profile/brevo_bug_report_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;
  late BrevoBugReportService dienst;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // DIE VERSION: Ohne sie bleibt die Geraeteinformation leer - der
    // Report waere dann nicht zuzuordnen.
    mockPackageInfo();
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
    // DER DIENST: Die Klasse hat einen privaten Konstruktor - der Test
    // holt sie sich ueber den Provider (so wie die App).
    final container = ProviderContainer();
    addTearDown(container.dispose);
    dienst = container.read(brevoBugReportServiceProvider);
  });

  setUp(() {
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
  });

  group('Der Bug-Report-Versand', () {
    test('der Report geht an die Edge Function', () async {
      final ok = await dienst.submitBugReport(
        summary: 'Zusammenfassung',
        description: 'Die App stuerzt beim Chat ab.',
      );

      expect(ok, isTrue);
      final aufruf = server.funktionsAufrufe.firstWhere(
        (c) => c['funktion'] == 'send-bug-report',
        orElse: () => <String, dynamic>{},
      );
      expect(aufruf, isNotEmpty, reason: 'Der Report muss raus.');
      expect(
        aufruf['description'],
        'Die App stuerzt beim Chat ab.',
        reason: 'Die Beschreibung ist das, was der Nutzer getippt hat.',
      );
      expect(
        aufruf['deviceInfo'],
        isNotNull,
        reason:
            'Ohne Geraeteinformation ist der Report nicht zuzuordnen - der '
            'Fehler kann an einer bestimmten App-Version haengen.',
      );
    });

    test('die Bilder kommen an - aber hoechstens fuenf', () async {
      await dienst.submitBugReport(
        summary: 'Zusammenfassung',
        description: 'Mit Bildern',
        base64Images: List<String>.filled(8, 'BASE64'),
      );

      final aufruf = server.funktionsAufrufe.firstWhere(
        (c) => c['funktion'] == 'send-bug-report',
      );
      final bilder = aufruf['images'] as List<dynamic>;
      expect(
        bilder.length,
        5,
        reason:
            'Mehr als fuenf Bilder nimmt der Server nicht an - der Client '
            'schickt auch nicht mehr.',
      );
    });

    test('eine zu lange Beschreibung wird abgelehnt', () async {
      final ok = await dienst.submitBugReport(
        summary: 'Zusammenfassung',
        description: 'x' * 5001,
      );

      expect(
        ok,
        isFalse,
        reason: 'Eine zu lange Beschreibung wird nicht verschickt.',
      );
      expect(
        server.funktionsAufrufe.any((c) => c['funktion'] == 'send-bug-report'),
        isFalse,
        reason:
            'Der Client muss gar nicht erst fragen - die Funktion wuerde die '
            'Beschreibung ohnehin ablehnen.',
      );
    });

    test('eine leere Beschreibung nutzt die Zusammenfassung', () async {
      await dienst.submitBugReport(
        summary: 'Nur die Zusammenfassung',
        description: '   ',
      );

      final aufruf = server.funktionsAufrufe.firstWhere(
        (c) => c['funktion'] == 'send-bug-report',
      );
      expect(
        aufruf['description'],
        'Nur die Zusammenfassung',
        reason:
            'Ohne Beschreibung soll die Zusammenfassung den Report tragen - '
            'sonst geht er leer raus.',
      );
    });

    test('ein Serverfehler wird als "nicht gesendet" gemeldet', () async {
      // DER SERVER LEHNT AB: Die Funktion antwortet mit einem Fehler.
      server.fehlerAntworten['/functions/v1/send-bug-report'] = (
        status: 500,
        body: '{"error":"kaputt"}',
      );

      final ok = await dienst.submitBugReport(
        summary: 'Zusammenfassung',
        description: 'Irgendetwas',
      );

      expect(
        ok,
        isFalse,
        reason:
            'Ein Fehler darf NICHT als Erfolg gemeldet werden - sonst '
            'glaubt der Nutzer, sein Report sei unterwegs.',
      );
    });
  });
}
