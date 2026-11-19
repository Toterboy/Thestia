// Die Bild-Meldung (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/image_report_service.dart 0 %.
//
// WARUM DAS WICHTIG IST: Wenn ein Nutzer ein Chat-Bild meldet, geht
// genau EIN Bild an die KI-Pruefung und an das Moderations-Team. Zwei
// Zusagen haengen daran:
//   1. Es geht NUR das gemeldete Bild raus - nicht irgendein Bild.
//   2. Die Reporter-ID wird pseudonymisiert (SHA-256) - der Klartext-UUID
//      geht nicht ueber die Kabel.
//
// DER SERVER: Der Client zeigt auf den Ersatz-Server aus
// test/support/fake_supabase_server.dart. Der zeichnet die
// Edge-Function-Aufrufe auf - damit ist sichtbar, WAS rausging.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/image_report_service.dart';

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
  });

  setUp(() {
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
  });

  /// Ein winziges Bild als Base64.
  const bild = 'iVBORw0KGgoAAAANSUhEUg==';

  group('Die Bild-Meldung', () {
    test('das gemeldete Bild geht an den Server', () async {
      final service = ImageReportService();

      final ergebnis = await service.reportChatImage(
        imageBase64: bild,
        reportedUserId: 'user-42',
        reason: 'Unangemessen',
        details: 'Bitte pruefen',
      );

      expect(server.funktionsAufrufe, hasLength(1));
      final aufruf = server.funktionsAufrufe.first;
      expect(aufruf['funktion'], 'report-image');
      // GENAU das gemeldete Bild - nicht irgendein anderes.
      expect(aufruf['imageBase64'], bild);
      expect(aufruf['reportedUserId'], 'user-42');
      expect(aufruf['reason'], 'Unangemessen');
      expect(aufruf['details'], 'Bitte pruefen');
      // Und das Ergebnis wird ausgewertet.
      expect(ergebnis.aiAvailable, isFalse);
    });

    test('die Reporter-ID wird pseudonymisiert', () async {
      final service = ImageReportService();

      await service.reportChatImage(
        imageBase64: bild,
        reportedUserId: 'user-42',
        reason: 'Unangemessen',
      );

      final aufruf = server.funktionsAufrufe.first;
      final pseudonym = aufruf['reporterIdSha256'] as String?;
      expect(pseudonym, isNotNull);
      // Der Klartext-UUID darf NICHT raus.
      expect(pseudonym, isNot(contains('me')));
      expect(pseudonym, hasLength(64)); // SHA-256 als Hex-String
    });

    test('ohne Eskalation geht das Bild nur einmal raus', () async {
      final service = ImageReportService();

      await service.reportChatImage(
        imageBase64: bild,
        reportedUserId: 'user-42',
        reason: 'Unangemessen',
      );

      expect(server.funktionsAufrufe, hasLength(1));
      expect(server.funktionsAufrufe.first['escalate'], isFalse);
    });

    test('mit Eskalation geht es mit dem Vermerk "eskalieren" raus', () async {
      final service = ImageReportService();

      await service.reportChatImage(
        imageBase64: bild,
        reportedUserId: 'user-42',
        reason: 'Unangemessen',
        escalate: true,
      );

      expect(server.funktionsAufrufe, hasLength(1));
      expect(server.funktionsAufrufe.first['escalate'], isTrue);
    });

    test('ein zu grosses Bild wird abgelehnt', () async {
      final service = ImageReportService();

      // Obergrenze + 1: das Bild darf nicht raus (der Server haette es
      // auch abgelehnt - aber es soll gar nicht erst gesendet werden).
      final zuGross = 'A' * (3 * 1024 * 1024 + 1);

      await expectLater(
        service.reportChatImage(
          imageBase64: zuGross,
          reportedUserId: 'user-42',
          reason: 'Unangemessen',
        ),
        throwsA(isA<StateError>()),
      );
      // Und nichts ist rausgegangen.
      expect(server.funktionsAufrufe, isEmpty);
    });

    test('das KI-Erultat wird ausgewertet', () async {
      server.funktionsAntworten['report-image'] = <String, dynamic>{
        'available': true,
        'nsfw': true,
        'score': 0.87,
        'notified': true,
      };
      final service = ImageReportService();

      final ergebnis = await service.reportChatImage(
        imageBase64: bild,
        reportedUserId: 'user-42',
        reason: 'Unangemessen',
      );

      expect(ergebnis.aiAvailable, isTrue);
      expect(ergebnis.aiAgrees, isTrue);
      expect(ergebnis.score, closeTo(0.87, 0.001));
      expect(ergebnis.operatorNotified, isTrue);
    });

    test('ohne KI ist das Ergebnis "nicht verfuegbar"', () async {
      server.funktionsAntworten['report-image'] = <String, dynamic>{
        'available': false,
        'notified': false,
      };
      final service = ImageReportService();

      final ergebnis = await service.reportChatImage(
        imageBase64: bild,
        reportedUserId: 'user-42',
        reason: 'Unangemessen',
      );

      expect(ergebnis.aiAvailable, isFalse);
      expect(ergebnis.aiAgrees, isFalse);
      expect(ergebnis.operatorNotified, isFalse);
    });
  });
}
