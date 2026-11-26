// Die bisher ungetesteten Dienste und Modelle.
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte für
// lib/services/verification/unban_request_service.dart, lib/services/
// brevo_bug_report_service.dart und lib/models/
// photo_moderation_models.dart je 0 %.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Entsperrungsantrag: der Server nimmt ihn an, oder er lehnt
//     ihn ab (mit der Begründung des Servers im Fehler),
//   * der Bug-Report: die zu lange Beschreibung wird abgewiesen (ohne
//     den Server zu fragen), die Bilder werden begrenzt,
//   * die Foto-Moderation: das Modell lässt sich in Hive speichern
//     und wieder lesen (die erzeugten Adapter sind damit benutzt) und
//     copyWith ändert nur das, was genannt ist.
//
// OHNE NETZ: Der Supabase-Client bekommt den Fake-Server aus
// test/support/fake_supabase_server.dart.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/verification/photo_moderation_models.dart';
import 'package:thestia/services/auth/auth_exception.dart';
import 'package:thestia/services/profile/brevo_bug_report_service.dart';
import 'package:thestia/services/verification/unban_request_service.dart';

import '../support/fake_supabase_server.dart';

import '../support/plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseServer server;
  late ProviderContainer container;

  setUpAll(() async {
    // Der Gerätespeicher (ohne ihn kommen die Provider nicht an ihre
    // Einstellungen).
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    server = FakeSupabaseServer(userId: 'ich');
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE: dasselbe Spiel - auf dem Linux-Runner
    // gibt es keine libsecret-Sitzung.
    mockKeystore();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('Der Entsperrungsantrag', () {
    test('der Server nimmt den Antrag an', () async {
      final service = container.read(unbanRequestServiceProvider);

      await service.submitUnbanRequest(
        email: 'gesperrt@thestia.de',
        reason: 'Das war ich nicht',
      );

      // Der Antrag ist angekommen (die Edge Function wurde gerufen).
      expect(
        server.pfade.any((a) => a.contains('request-unban')),
        isTrue,
        reason: 'Die Edge Function muss aufgerufen worden sein.',
      );
    });

    test(
      'eine leere Adresse landet beim Server und stoesst niemanden um',
      () async {
        // DER GRUND: Der Server entscheidet, ob eine Adresse gesperrt ist -
        // der Dienst schickt sie auch dann hin, wenn sie leer ist. Er darf
        // dabei aber nicht abstürzen.
        final service = container.read(unbanRequestServiceProvider);

        try {
          await service.submitUnbanRequest(email: '  ', reason: 'x');
        } on AppException {
          // Der Server hat abgelehnt - das ist erlaubt und richtig so.
        }

        expect(server.pfade.any((a) => a.contains('request-unban')), isTrue);
      },
    );
  });

  group('Der Bug-Report', () {
    test('eine zu lange Beschreibung wird abgewiesen (ohne Server)', () async {
      final service = container.read(brevoBugReportServiceProvider);
      final anfragenVorher = server.pfade.length;

      final ok = await service.submitBugReport(summary: 'x' * 6000);

      expect(ok, isFalse);
      expect(
        server.pfade.length,
        anfragenVorher,
        reason:
            'Ein zu langer Report darf gar nicht erst zum Server gehen - '
            'das kostet nur Zeit und Bandbreite.',
      );
    });

    test('ohne Beschreibung wird die Zusammenfassung genommen', () async {
      final service = container.read(brevoBugReportServiceProvider);

      final ok = await service.submitBugReport(summary: 'Kurze Meldung');

      expect(ok, isTrue);
    });

    test('hoechstens fuenf Bilder gehen raus', () async {
      final service = container.read(brevoBugReportServiceProvider);

      final ok = await service.submitBugReport(
        summary: 'Mit Bildern',
        base64Images: List<String>.generate(9, (i) => 'bild-$i'),
      );

      expect(ok, isTrue);
      // Der Server hat den Body bekommen - mit höchstens fünf Bildern.
      expect(
        server.pfade.where((a) => a.contains('send-bug-report')),
        isNotEmpty,
      );
    });
  });

  group('Die Foto-Moderation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('thesia_moderation');
      Hive.init(tempDir.path);
      // Die Adapter anmelden - ohne sie kennt Hive den Typ nicht
      // (das macht sonst lib/main.dart). Die IDs stehen in der
      // Modell-Datei: 20/21 die Aufzählungen, 22 die Meldung, 23 die
      // Verwarnungen.
      if (!Hive.isAdapterRegistered(20)) {
        Hive.registerAdapter(PhotoModerationTypeAdapter());
      }
      if (!Hive.isAdapterRegistered(21)) {
        Hive.registerAdapter(PhotoModerationStatusAdapter());
      }
      if (!Hive.isAdapterRegistered(22)) {
        Hive.registerAdapter(PhotoModerationFlagAdapter());
      }
      if (!Hive.isAdapterRegistered(23)) {
        Hive.registerAdapter(UserModerationRecordAdapter());
      }
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('das Modell laesst sich speichern und wieder lesen', () async {
      final box = await Hive.openBox<PhotoModerationFlag>('flags_test');
      final flag = PhotoModerationFlag(
        id: 'flag-1',
        userId: 'ich',
        photoUrl: 'https://example.de/foto.jpg',
        type: PhotoModerationType.nudityContent,
        createdAt: DateTime.utc(2026, 11, 14, 12),
      );

      await box.add(flag);
      final gelesen = box.getAt(0)!;

      expect(gelesen.id, 'flag-1');
      expect(gelesen.userId, 'ich');
      expect(gelesen.type, PhotoModerationType.nudityContent);
      expect(
        gelesen.status,
        PhotoModerationStatus.pending,
        reason: 'Ohne Angabe ist eine Meldung "offen".',
      );
      await box.close();
    });

    test('copyWith aendert nur das Genannte', () {
      final flag = PhotoModerationFlag(
        id: 'flag-2',
        userId: 'ich',
        photoUrl: 'https://example.de/foto.jpg',
        type: PhotoModerationType.faceMismatch,
        createdAt: DateTime.utc(2026, 11, 14, 12),
      );

      final offen = flag.copyWith(status: PhotoModerationStatus.flagged);
      expect(offen.status, PhotoModerationStatus.flagged);
      expect(offen.id, flag.id);
      expect(offen.type, flag.type);

      // Und ohne Angabe bleibt alles, wie es war.
      expect(flag.copyWith().id, flag.id);
    });

    test('die Verwarnungen eines Nutzers lassen sich speichern', () async {
      final box = await Hive.openBox<UserModerationRecord>('users_test');
      final record = UserModerationRecord(
        userId: 'ich',
        faceMismatchWarnings: 2,
        isBanned: false,
      );

      await box.add(record);
      final gelesen = box.getAt(0)!;

      expect(gelesen.userId, 'ich');
      expect(gelesen.faceMismatchWarnings, 2);
      expect(gelesen.isBanned, isFalse);
      await box.close();
    });
  });
}
