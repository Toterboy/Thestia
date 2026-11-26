// Die Bild-Meldung: die KI-Prüfung und der Melde-Dialog.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/services/profile/image_report_service.dart 76 offene Zeilen. Der
// Weg ist heikel: der Nutzer meldet ein Bild, die App prüft es lokal
// (auf dem Gerät), schickt es zum Server und bekommt das KI-Ergebnis
// zurück.
//
// DIE WICHTIGEN EIGENSCHAFTEN (und die Testfälle dazu):
//   * das Bild verlässt das Gerät ERST, wenn der Nutzer auf
//     "Meldung absenden" tippt (nicht vorher, nicht automatisch),
//   * die Reporter-ID geht pseudonymisiert raus (kein Klartext-UUID),
//   * die KI bestätigt die Meldung -> der Nutzer sieht die
//     Bestätigung,
//   * die KI widerspricht -> der Nutzer kann eskalieren (an das Team),
//   * ohne Bild sagt der Dialog das (statt still zu nichts zu tun),
//   * schlägt die Meldung fehl, wird das gesagt (eine Meldung, die
//     nicht ankommt, ist keine Meldung).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/verification/report_models.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/services/profile/image_report_service.dart';
import 'package:thestia/services/profile/image_safety_service.dart';
import 'package:thestia/services/profile/report_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/utils/common/constants.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import '../support/router_harness.dart';

/// Das gemeldete Bild (ein winziges PNG als Data-URL).
const String _bildDataUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Der Ersatz für den Bild-Melde-Dienst.
///
/// DER GRUND FÜR DEN ERSATZ: Im Widget-Test läuft die Uhr des
/// Test-Fensters, nicht die des Netzes - eine echte Anfrage würde dort
/// hängenbleiben. Der Dialog selbst wird mit dem Ersatz geprüft; die
/// Anfrage an den Server prüfen die Tests weiter unten (mit dem echten
/// Dienst).
class _FakeBildMeldeDienst extends ImageReportService {
  /// Das Ergebnis, das der Dienst liefert.
  ImageReportOutcome ergebnis = const ImageReportOutcome(
    aiAvailable: true,
    aiAgrees: true,
    score: 0.9,
    operatorNotified: true,
  );

  /// Wirft der Dienst einen Fehler? (der Fall "die Meldung kommt nicht an")
  bool wirftFehler = false;

  /// Die Aufrufe (damit der Test sieht, was rausgegangen wäre).
  final List<Map<String, dynamic>> aufrufe = <Map<String, dynamic>>[];

  @override
  Future<ImageReportOutcome> reportChatImage({
    required String imageBase64,
    required String reportedUserId,
    required String reason,
    String details = '',
    bool escalate = false,
    List<String> contextMessages = const [],
    double? localScore,
  }) async {
    if (wirftFehler) {
      throw StateError('Meldung fehlgeschlagen (Status 500).');
    }
    aufrufe.add(<String, dynamic>{
      'imageBase64': imageBase64,
      'reportedUserId': reportedUserId,
      'reason': reason,
      'details': details,
      'escalate': escalate,
      'localScore': localScore,
    });
    return ergebnis;
  }
}

/// Der Ersatz für den Melde-Dienst (kein Speicher, kein Netz).
class _FakeMeldeDienst extends ReportService {
  /// Wie viele Meldungen wurden erzeugt?
  int anzahl = 0;

  @override
  Future<ReportSubmission> createReport({
    required String reporterId,
    required String reporterUserName,
    required String reportedUserId,
    required String reportedUserName,
    required ReportType type,
    String? description,
    List<Message>? messages,
  }) async {
    anzahl++;
    return ReportSubmission(
      report: UserReport(
        id: 'report-$anzahl',
        reporterId: reporterId,
        reportedUserId: reportedUserId,
        type: type,
        description: description,
        createdAt: DateTime.now(),
      ),
      serverAccepted: true,
    );
  }
}

/// Der Knopf, der den Melde-Dialog öffnet.
///
/// EIGENTLICHER GRUND FÜR DIESE KLASSE: Der Dialog braucht einen
/// [WidgetRef] (er liest daraus das Profil und den Melde-Dienst). Der
/// Ref kommt nur aus einem Consumer-Widget - deshalb ist der Knopf hier
/// ein [ConsumerWidget].
class _MeldeKnopf extends ConsumerWidget {
  const _MeldeKnopf({required this.nachricht});

  final Message nachricht;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showImageReportDialog(
            context: ctx,
            ref: ref,
            message: nachricht,
            reportedUserId: 'die-andere',
            reportedUserName: 'Jemand',
          ),
          child: const Text('MELDEN'),
        ),
      ),
    );
  }
}

void main() {
  late FakeSupabaseServer server;

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
    server.pfade.clear();
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
    server.rpcAufrufe.clear();
    // DIE FEHLERANTWORTEN: Sie gelten nur für den einen Test, der sie
    // stellt - sonst würde der nächste Test denselben Fehler sehen.
    server.fehlerAntworten.clear();
    ImageSafetyService.classifyOverride = null;
  });

  tearDown(() {
    ImageSafetyService.classifyOverride = null;
  });

  group('Die Meldung an den Server', () {
    test('das Ergebnis kommt vom Server', () async {
      server.funktionsAntworten['report-image'] = <String, dynamic>{
        'available': true,
        'nsfw': true,
        'score': 0.87,
        'notified': true,
      };

      final ergebnis = await ImageReportService().reportChatImage(
        imageBase64: 'AAAA',
        reportedUserId: 'die-andere',
        reason: 'Unangemessene Inhalte',
      );

      expect(ergebnis.aiAvailable, isTrue);
      expect(ergebnis.aiAgrees, isTrue);
      expect(ergebnis.score, closeTo(0.87, 0.001));
      expect(ergebnis.operatorNotified, isTrue);
    });

    test('die Reporter-ID geht pseudonymisiert raus', () async {
      await ImageReportService().reportChatImage(
        imageBase64: 'AAAA',
        reportedUserId: 'die-andere',
        reason: 'Unangemessene Inhalte',
      );

      expect(server.funktionsAufrufe, isNotEmpty);
      final aufruf = server.funktionsAufrufe.firstWhere(
        (c) => c['funktion'] == 'report-image',
      );
      expect(
        aufruf['reporterIdSha256'],
        isNot(AppConstants.currentUserId),
        reason:
            'Die Klartext-ID darf nicht raus - sie wird pseudonymisiert '
            '(SHA-256) geschickt.',
      );
      expect((aufruf['reporterIdSha256'] as String).length, 64);
    });

    test('das Bild geht mit der Meldung raus', () async {
      await ImageReportService().reportChatImage(
        imageBase64: 'DAS-BILD',
        reportedUserId: 'die-andere',
        reason: 'Unangemessene Inhalte',
        details: 'Siehe oben',
      );

      final aufruf = server.funktionsAufrufe.firstWhere(
        (c) => c['funktion'] == 'report-image',
      );
      expect(aufruf['imageBase64'], 'DAS-BILD');
      expect(aufruf['reason'], 'Unangemessene Inhalte');
      expect(aufruf['details'], 'Siehe oben');
      expect(aufruf['reportedUserId'], 'die-andere');
    });

    test('ein zu grosses Bild wird abgelehnt', () async {
      await expectLater(
        ImageReportService().reportChatImage(
          imageBase64: 'x' * (3 * 1024 * 1024 + 1),
          reportedUserId: 'die-andere',
          reason: 'Unangemessene Inhalte',
        ),
        throwsA(isA<StateError>()),
        reason:
            'Ein Bild, das das Server-Limit sprengt, muss abgelehnt werden - '
            'sonst wartet der Nutzer vergeblich.',
      );
      expect(server.funktionsAufrufe, isEmpty);
    });

    test('ein Serverfehler wird nicht verschluckt', () async {
      server.fehlerAntworten['/functions/v1/report-image'] = (
        status: 500,
        body: '{"message":"Serverfehler"}',
      );

      await expectLater(
        ImageReportService().reportChatImage(
          imageBase64: 'AAAA',
          reportedUserId: 'die-andere',
          reason: 'Unangemessene Inhalte',
        ),
        throwsA(anything),
      );
    });
  });

  group('Der Melde-Dialog', () {
    /// Der Ersatz für den Bild-Melde-Dienst.
    final _FakeBildMeldeDienst bildDienst = _FakeBildMeldeDienst();

    /// Der Ersatz für den Melde-Dienst (kein Speicher, kein Netz).
    final _FakeMeldeDienst meldeDienst = _FakeMeldeDienst();

    setUp(() {
      bildDienst.aufrufe.clear();
      bildDienst.wirftFehler = false;
      bildDienst.ergebnis = const ImageReportOutcome(
        aiAvailable: true,
        aiAgrees: true,
        score: 0.9,
        operatorNotified: true,
      );
      meldeDienst.anzahl = 0;
      // DIE LOKALE PRÜFUNG: Ohne das läuft das echte Modell (das
      // dauert Sekunden). Der Test gibt den Befund selbst vor.
      ImageSafetyService.classifyOverride = (bytes) =>
          const ImageSafetyResult(nsfl: 0.0, nsfw: 0.0, sfw: 1.0);
    });

    /// Baut die Seite mit dem Melde-Knopf.
    Future<void> zeigeMeldeKnopf(
      WidgetTester tester, {
      required Message nachricht,
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            localStorageProvider.overrideWithValue(TestSpeicher()),
            profileProvider.overrideWith((ref) => TestProfil()),
            reportServiceProvider.overrideWithValue(meldeDienst),
            imageReportServiceProvider.overrideWithValue(bildDienst),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: _MeldeKnopf(nachricht: nachricht),
          ),
        ),
      );
      await tester.pump();
    }

    /// Die Nachricht mit dem Bild.
    Message bildNachricht({bool mitBild = true}) => Message(
      id: 'm1',
      senderId: 'die-andere',
      receiverId: 'ich',
      type: MessageType.image,
      mediaUrl: mitBild ? _bildDataUrl : null,
      timestamp: DateTime.now(),
    );

    /// Wählt den Grund "Unangemessene Inhalte" und schickt die Meldung.
    Future<void> waehleGrund(WidgetTester tester) async {
      final grund = find.text(
        L10n.tWithoutContext('report.type.inappropriateContent'),
      );
      await tester.ensureVisible(grund);
      await tester.pump();
      await tester.tap(grund);
      await tester.pump();
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('report.sendReport'),
        ),
      );
      await tester.pump();
    }

    testWidgets('ohne Bild sagt der Dialog das', (tester) async {
      await zeigeMeldeKnopf(tester, nachricht: bildNachricht(mitBild: false));

      await tester.tap(find.text('MELDEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('report.imageUnavailable')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass das Bild nicht gemeldet werden '
            'kann - sonst denkt er, es sei passiert.',
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('die Meldung geht mit dem Bild raus', (tester) async {
      await zeigeMeldeKnopf(tester, nachricht: bildNachricht());

      await tester.tap(find.text('MELDEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // DER GRUND: Ohne Grund darf nichts raus.
      expect(
        find.text(L10n.tWithoutContext('report.sendReport')),
        findsOneWidget,
      );
      expect(bildDienst.aufrufe, isEmpty);

      final grund = find.text(
        L10n.tWithoutContext('report.type.inappropriateContent'),
      );
      await tester.ensureVisible(grund);
      await tester.pump();
      await tester.tap(grund);
      await tester.pump();

      final knopf = tester.widget<FilledButton>(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('report.sendReport'),
        ),
      );
      expect(
        knopf.onPressed,
        isNotNull,
        reason:
            'Nach der Wahl des Grundes muss der Knopf aktiv sein - sonst '
            'kann der Nutzer nicht melden.',
      );

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('report.sendReport'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        bildDienst.aufrufe.length,
        1,
        reason:
            'Das Bild muss mit der Meldung raus - erst mit dem Absenden '
            'verlaesst es das Geraet.',
      );
      expect(
        bildDienst.aufrufe.first['reason'],
        L10n.tWithoutContext('report.type.inappropriateContent'),
      );
      expect(
        meldeDienst.anzahl,
        1,
        reason:
            'Zusaetzlich muss der klassische Report-Eintrag entstehen - '
            'sonst fehlt die Meldung im Admin-Bereich.',
      );
    });

    testWidgets('die lokale Pruefung meldet ein anstoessiges Bild', (
      tester,
    ) async {
      // DER BEFUND DER LOKALEN PRÜFUNG: Das Bild ist auffällig. Der
      // Nutzer soll das WISSEN - die Meldung geht trotzdem raus, aber er
      // weiß, was er meldet.
      ImageSafetyService.classifyOverride = (bytes) =>
          const ImageSafetyResult(nsfl: 0.1, nsfw: 0.9, sfw: 0.0);
      await zeigeMeldeKnopf(tester, nachricht: bildNachricht());

      await tester.tap(find.text('MELDEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('90 %'),
        findsOneWidget,
        reason:
            'Der Nutzer muss den Befund der lokalen Pruefung sehen - die '
            'Meldung soll nicht blind abgeschickt werden.',
      );
    });

    testWidgets('die KI bestaetigt die Meldung', (tester) async {
      await zeigeMeldeKnopf(tester, nachricht: bildNachricht());

      await tester.tap(find.text('MELDEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await waehleGrund(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('report.confirmed')),
        findsOneWidget,
        reason:
            'Die KI hat die Meldung bestaetigt - der Nutzer muss das sehen, '
            'sonst weiss er nicht, ob seine Meldung angekommen ist.',
      );
    });

    testWidgets('die KI widerspricht: der Nutzer kann eskalieren', (
      tester,
    ) async {
      // DIE KI SIEHT ES ANDERS: Das Bild ist für sie harmlos. Der
      // Nutzer muss die Meldung trotzdem an das Team geben können.
      bildDienst.ergebnis = const ImageReportOutcome(
        aiAvailable: true,
        aiAgrees: false,
        score: 0.05,
        operatorNotified: false,
      );
      await zeigeMeldeKnopf(tester, nachricht: bildNachricht());

      await tester.tap(find.text('MELDEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await waehleGrund(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('report.aiResult')),
        findsOneWidget,
        reason:
            'Die KI widerspricht - der Nutzer muss die Meldung an das Team '
            'weiterleiten koennen, wenn die KI falsch liegt.',
      );

      // DIE ESKALATION: Der zweite Aufruf trägt "escalate" - erst dann
      // geht das Bild an das Team.
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('report.forwardBtn'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(bildDienst.aufrufe.length, 2);
      expect(
        bildDienst.aufrufe.last['escalate'],
        isTrue,
        reason:
            'Die Eskalation muss als solche markiert sein - das Team '
            'sieht sonst nicht, dass der Nutzer die KI widerlegt hat.',
      );
      expect(
        find.text(L10n.tWithoutContext('report.forwardedTitle')),
        findsOneWidget,
      );
    });

    testWidgets('schlaegt die Meldung fehl, wird das gesagt', (tester) async {
      bildDienst.wirftFehler = true;
      await zeigeMeldeKnopf(tester, nachricht: bildNachricht());

      await tester.tap(find.text('MELDEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await waehleGrund(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('report.failedTitle')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass die Meldung nicht angekommen ist - '
            'eine Meldung, die nicht ankommt, ist keine Meldung.',
      );
    });
  });
}
