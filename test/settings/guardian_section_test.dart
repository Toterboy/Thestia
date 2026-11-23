// Der Elternbereich in den Einstellungen (Kinderschutz & Elternzugriff).
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte fuer
// lib/widgets/settings/guardian_section.dart 63 offene Zeilen. Der
// Abschnitt entscheidet, was der Jugendliche ueber die Aufsicht seiner
// Eltern sieht - und ob er etwas aendern darf (nur mit der PIN des
// Elternteils).
//
// WAS HIER GEPRUEFT WIRD:
//   * der Abruf schlaegt fehl: es gibt einen Grund und einen Knopf
//     (kein endloser Ladekreis - das war ein gemeldeter Fehler),
//   * ohne Freigabe steht das da (und ein Minderjaehriger kann eine
//     Freigabe anfordern),
//   * eine wartende Freigabe nennt die Adresse des Elternteils,
//   * eine aktive Freigabe zeigt Rhythmus und Nutzungszeit,
//   * ohne PIN kann nichts geaendert werden,
//   * die falsche PIN wird abgelehnt (mit klarer Meldung),
//   * mit der PIN wird der Bereich bearbeitbar und gespeichert.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/verification/guardian_status.dart';
import 'package:thestia/providers/settings/guardian_provider.dart';
import 'package:thestia/services/auth/supabase_service.dart';
import 'package:thestia/services/verification/guardian_service.dart';
import 'package:thestia/widgets/settings/guardian_section.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Ersatz fuer den Eltern-Dienst (kein Netz im Test).
class _FakeGuardianDienst extends GuardianService {
  _FakeGuardianDienst() : super(SupabaseService.client);

  /// Der Stand, den der Dienst liefert.
  GuardianStatus stand = const GuardianStatus(loaded: true);

  /// Wirft der Dienst beim Lesen einen Fehler?
  bool wirftFehler = false;

  /// Ist die PIN richtig?
  bool pinRichtig = true;

  /// Wie oft wurde der Stand gelesen?
  int anzahlLaden = 0;

  /// Die gespeicherten Aenderungen.
  final List<Map<String, dynamic>> gespeichert = <Map<String, dynamic>>[];

  @override
  Future<GuardianStatus> fetchStatus() async {
    anzahlLaden++;
    if (wirftFehler) {
      throw const GuardianServiceException('network');
    }
    return stand;
  }

  @override
  Future<bool> verifyPin(String pin) async => pinRichtig;

  @override
  Future<GuardianResult> updateSettingsWithPin({
    required String pin,
    String? notifyFrequency,
    bool? usageLimitEnabled,
    int? usageStartMin,
    int? usageEndMin,
  }) async {
    gespeichert.add(<String, dynamic>{
      'pin': pin,
      'notifyFrequency': notifyFrequency,
      'usageLimitEnabled': usageLimitEnabled,
      'usageStartMin': usageStartMin,
      'usageEndMin': usageEndMin,
    });
    return const GuardianResult.ok();
  }

  @override
  Future<GuardianResult> revoke() async => const GuardianResult.ok();
}

void main() {
  late FakeSupabaseServer server;
  late _FakeGuardianDienst dienst;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
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
    dienst = _FakeGuardianDienst();
  });

  /// Baut den Abschnitt.
  Future<void> zeigeAbschnitt(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          guardianServiceProvider.overrideWithValue(dienst),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(
            body: SingleChildScrollView(child: GuardianSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('Der Abruf', () {
    testWidgets('schlaegt er fehl, gibt es einen Grund und einen Knopf', (
      tester,
    ) async {
      dienst.wirftFehler = true;

      await zeigeAbschnitt(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.loadErrorTitle')),
        findsOneWidget,
        reason:
            'Der Nutzer muss einen Grund sehen - ein endloser Ladekreis '
            'war der gemeldete Fehler ("der Elternbereich laedt ewig lang").',
      );
      expect(
        find.text(L10n.tWithoutContext('guardian.retry')),
        findsOneWidget,
        reason: 'Es muss einen Weg aus dem Bildschirm geben.',
      );
    });

    testWidgets('der Knopf holt den Stand erneut', (tester) async {
      dienst.wirftFehler = true;
      await zeigeAbschnitt(tester);
      final vorher = dienst.anzahlLaden;

      await tester.tap(find.text(L10n.tWithoutContext('guardian.retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(dienst.anzahlLaden, greaterThan(vorher));
    });
  });

  group('Der Zustand', () {
    testWidgets('ohne Freigabe steht das da', (tester) async {
      dienst.stand = const GuardianStatus(loaded: true, status: 'none');

      await zeigeAbschnitt(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.noConsentTitle')),
        findsOneWidget,
      );
    });

    testWidgets('eine wartende Freigabe nennt die Adresse', (tester) async {
      dienst.stand = const GuardianStatus(
        loaded: true,
        status: 'pending',
        guardianEmail: 'eltern@example.de',
      );

      await zeigeAbschnitt(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.pendingTitle')),
        findsOneWidget,
      );
      expect(
        find.textContaining('eltern@example.de'),
        findsOneWidget,
        reason:
            'Der Jugendliche muss sehen, bei wem die Freigabe haengt - er '
            'hat die Adresse selbst eingetragen.',
      );
    });

    testWidgets('eine aktive Freigabe zeigt Rhythmus und Nutzungszeit', (
      tester,
    ) async {
      dienst.stand = const GuardianStatus(
        loaded: true,
        status: 'active',
        notifyFrequency: 'daily',
        usageLimitEnabled: true,
        usageStartMin: 9 * 60,
        usageEndMin: 22 * 60,
        hasPin: true,
      );

      await zeigeAbschnitt(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.activeTitle')),
        findsOneWidget,
      );
      expect(
        find.textContaining('09:00'),
        findsOneWidget,
        reason: 'Das Nutzungsfenster muss fuer den Nutzer sichtbar sein.',
      );
      expect(find.textContaining('22:00'), findsOneWidget);
    });

    testWidgets('ohne PIN kann nichts geaendert werden', (tester) async {
      dienst.stand = const GuardianStatus(
        loaded: true,
        status: 'active',
        hasPin: false,
      );

      await zeigeAbschnitt(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.pinLocked')),
        findsNothing,
        reason:
            'Ohne PIN gibt es keinen Knopf zum Aendern - die PIN gehoert '
            'dem Elternteil.',
      );
      expect(
        find.text(L10n.tWithoutContext('guardian.usagePinNote')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass die Aenderung nur mit der PIN des '
            'Elternteils geht.',
      );
    });
  });

  group('Die PIN', () {
    /// Tippt die PIN ein und bestaetigt.
    Future<void> tippePin(WidgetTester tester, String pin) async {
      final knopf = find.text(L10n.tWithoutContext('guardian.pinLocked'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.enterText(find.byType(TextField), pin);
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, L10n.tWithoutContext('common.ok')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('eine falsche PIN wird abgelehnt', (tester) async {
      dienst.pinRichtig = false;
      dienst.stand = const GuardianStatus(
        loaded: true,
        status: 'active',
        hasPin: true,
      );
      await zeigeAbschnitt(tester);

      await tippePin(tester, '1234');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.pinWrong')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass die PIN nicht stimmt - er kennt '
            'die PIN des Elternteils nicht.',
      );
      expect(
        find.text(L10n.tWithoutContext('guardian.saveBtn')),
        findsNothing,
        reason: 'Ohne richtige PIN darf der Bereich nicht offen sein.',
      );
    });

    testWidgets('mit der richtigen PIN wird der Bereich bearbeitbar', (
      tester,
    ) async {
      dienst.pinRichtig = true;
      dienst.stand = const GuardianStatus(
        loaded: true,
        status: 'active',
        hasPin: true,
      );
      await zeigeAbschnitt(tester);

      await tippePin(tester, '1234');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('guardian.saveBtn')),
        findsOneWidget,
        reason:
            'Mit der PIN darf der Jugendliche die Einstellungen der Aufsicht '
            'aendern - geprueft wird sie auf dem Server.',
      );
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('das Speichern geht mit der PIN an den Server', (tester) async {
      dienst.pinRichtig = true;
      dienst.stand = const GuardianStatus(
        loaded: true,
        status: 'active',
        hasPin: true,
      );
      await zeigeAbschnitt(tester);

      await tippePin(tester, '1234');

      final speichern = find.text(L10n.tWithoutContext('guardian.saveBtn'));
      await tester.ensureVisible(speichern);
      await tester.pump();
      await tester.tap(speichern);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        dienst.gespeichert.length,
        1,
        reason:
            'Die Aenderung muss mit der PIN zum Server - ohne PIN aendert '
            'gar nichts.',
      );
      expect(dienst.gespeichert.first['pin'], '1234');
    });
  });
}
