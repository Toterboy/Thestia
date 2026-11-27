// Die Verifizierung: die Challenge, das Aufräumen und die Einreichung.
//
// ANLASS (26.11.2026): Die Abdeckung zeigte für
// lib/services/verification/verification_service.dart 47 offene Zeilen.
// Getestet waren Aufnahme und Ablage - die Challenge, das Aufräumen
// und der Weg zum Server nicht.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Challenge liefert eine gültige Aufgabe (und keine vorhersagbare),
//   * ein Video lässt sich als geprüft markieren und wieder löschen,
//   * das Aufräumen nimmt Box und Dateien mit,
//   * die Einreichung lädt das Video VERSCHLÜSSELT hoch und schickt
//     den Schlüssel getrennt mit,
//   * eine angenommene Einreichung löscht die lokale Kopie,
//   * eine abgelehnte Einreichung nennt den Grund,
//   * ein Netzausfall gilt als "lokal pending" (nicht als Fehler),
//   * ein vom Server abgelehnter Upload ist KEIN Netzausfall.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/verification/verification_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseServer server;
  late VerificationService service;
  late Directory tempDir;

  setUpAll(() async {
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thesia_verif_server');
    Hive.init(tempDir.path);
    server.funktionsAntworten.clear();
    server.funktionsAufrufe.clear();
    server.fehlerAntworten.clear();
    service = VerificationService();
    await service.initialize();
  });

  tearDown(() async {
    await service.deleteAllLocalData();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Legt eine Aufnahme-Datei an (wie die Kamera sie liefert).
  String legeAufnahmeAn() {
    final ordner = Directory.systemTemp.createTempSync('verif_aufnahme');
    final datei = File('${ordner.path}/cache_video.mp4');
    datei.writeAsBytesSync(<int>[1, 2, 3, 4, 5]);
    return datei.path;
  }

  /// Speichert ein Video und gibt seinen Pfad zurück.
  Future<String> speichereVideo() async {
    final video = await service.saveVerificationVideo(
      filePath: legeAufnahmeAn(),
      challengeType: VerificationChallengeType.speakNumber,
      challengeData: '42',
    );
    return video.filePath;
  }

  group('Die Challenge', () {
    test('liefert eine gültige Aufgabe', () {
      for (var i = 0; i < 40; i++) {
        final (typ, daten) = service.generateChallenge();
        switch (typ) {
          case VerificationChallengeType.speakNumber:
            expect(daten, matches(RegExp(r'^\d{4}$')));
          case VerificationChallengeType.makeGesture:
            expect(
              daten,
              anyOf('tongue', 'blink', 'brows'),
              reason: 'Die Geste muss eine der drei bekannten sein.',
            );
          case VerificationChallengeType.turnHead:
            expect(daten, anyOf('left_right', 'right_left'));
          case VerificationChallengeType.smile:
            expect(daten, 'smile');
        }
      }
    });

    test('die Aufgabe ist nicht immer die gleiche', () {
      final aufgaben = <String>{};
      for (var i = 0; i < 60; i++) {
        final (typ, daten) = service.generateChallenge();
        aufgaben.add('${typ.name}:$daten');
      }

      expect(
        aufgaben.length,
        greaterThan(3),
        reason:
            'Eine feste Aufgabe wäre vorbereitbar - der Zufall ist der '
            'Witz der Liveness-Prüfung.',
      );
    });
  });

  group('Der Status', () {
    test('ein Video lässt sich als geprüft markieren', () async {
      final pfad = await speichereVideo();

      await service.markAsVerified(pfad);

      expect(service.isVerified, isTrue);
    });

    test('ein unbekanntes Video ändert nichts', () async {
      await service.markAsVerified('gibt-es-nicht.mp4');

      expect(service.isVerified, isFalse);
    });

    test('ein gelöschtes Video ist weg', () async {
      final pfad = await speichereVideo();

      await service.deleteVideo(pfad);

      expect(service.getVerificationVideo(), isNull);
      expect(File(pfad).existsSync(), isFalse);
    });

    test('das Aufräumen nimmt Box und Datei mit', () async {
      final pfad = await speichereVideo();

      await service.deleteAllLocalData();

      expect(service.getVerificationVideo(), isNull);
      expect(
        File(pfad).existsSync(),
        isFalse,
        reason:
            'Beim Aufräumen müssen auch die Dateien weg - sonst bleibt '
            'das biometrische Material auf dem Gerät.',
      );
    });
  });

  group('Die Einreichung zum Server', () {
    test('das Video wird verschlüsselt hochgeladen', () async {
      await speichereVideo();
      server.funktionsAntworten['verify-account'] = <String, dynamic>{
        'status': 'pending',
      };

      final ok = await service.submitVerification(
        estimatedAge: 30,
        faceCount: 1,
      );

      expect(ok, isTrue);
      // Der Upload ging an den privaten Bucket.
      expect(
        server.pfade.any((p) => p.contains('video.mp4.enc')),
        isTrue,
        reason: 'Das Video muss in den privaten Bucket.',
      );
      // Und die Edge Function bekam den Schlüssel getrennt vom Chiffrat.
      final aufruf = server.funktionsAufrufe.firstWhere(
        (z) => z['funktion'] == 'verify-account',
        orElse: () => <String, dynamic>{},
      );
      expect(aufruf, isNotEmpty);
      expect(aufruf['action'], 'submit');
      expect('${aufruf['videoKey']}'.isNotEmpty, isTrue);
      expect('${aufruf['videoIv']}'.isNotEmpty, isTrue);
      expect(aufruf['estimatedAge'], 30);
      expect(aufruf['faceCount'], 1);
    });

    test('eine angenommene Einreichung löscht die lokale Kopie', () async {
      final pfad = await speichereVideo();
      server.funktionsAntworten['verify-account'] = <String, dynamic>{
        'status': 'pending',
      };

      final ok = await service.submitVerification();

      expect(ok, isTrue);
      expect(
        File(pfad).existsSync(),
        isFalse,
        reason:
            'Nach der Annahme liegt das Video serverseitig - die lokale '
            'Kopie muss weg (Datenschutz).',
      );
    });

    test('eine Minderjährige wird angenommen (manuelle Prüfung)', () async {
      await speichereVideo();
      server.funktionsAntworten['verify-account'] = <String, dynamic>{
        'status': 'pending_minor',
      };

      final ok = await service.submitVerification();

      expect(
        ok,
        isTrue,
        reason:
            'Der Server hat die Einreichung angenommen - die App darf sie '
            'nicht als "abgelehnt" melden.',
      );
    });

    test('eine abgelehnte Einreichung nennt den Grund', () async {
      await speichereVideo();
      server.funktionsAntworten['verify-account'] = <String, dynamic>{
        'status': 'rejected',
        'error': 'Video zu kurz',
      };

      final ok = await service.submitVerification();

      expect(ok, isFalse);
      expect(service.lastSubmitError, contains('Video zu kurz'));
    });

    test('ein Netzausfall gilt als lokal pending', () async {
      await speichereVideo();
      // DER NETZAUSFALL: Der Server meldet, dass die Verbindung weg ist
      // (das ist, was ein echter Netzausfall zurückgibt).
      server.fehlerAntworten['/functions/v1/verify-account'] = (
        status: 500,
        body: '{"message":"Connection refused"}',
      );

      final ok = await service.submitVerification();

      expect(
        ok,
        isTrue,
        reason:
            'Der Server war nicht erreichbar - der Nutzer hat seine Aufgabe '
            'gemacht, der Upload kommt beim nächsten Start nach.',
      );
      expect(service.lastSubmitError, isNull);
    });

    test('ein abgelehnter Upload ist kein Netzausfall', () async {
      await speichereVideo();
      // DER ABGELEHNTE UPLOAD: Der Server antwortet, aber mit einem
      // Fehler - das Video liegt nirgends. Das darf NICHT als "lokal
      // pending" durchgehen (sonst erscheint der Fall nie im
      // Adminbereich).
      server.fehlerAntworten['/functions/v1/verify-account'] = (
        status: 403,
        body: '{"message":"Permission denied"}',
      );

      final ok = await service.submitVerification();

      expect(ok, isFalse);
      expect(service.lastSubmitError, isNotNull);
    });
  });

  group('Die automatische Freigabe', () {
    test('der Server kann sofort freigeben', () async {
      await speichereVideo();
      server.funktionsAntworten['verify-account'] = <String, dynamic>{
        'status': 'auto',
      };

      final ok = await service.autoVerification(
        estimatedAge: 30,
        faceCount: 1,
        deviation: 1,
      );

      expect(ok, isTrue);
      final aufruf = server.funktionsAufrufe.firstWhere(
        (z) => z['funktion'] == 'verify-account',
        orElse: () => <String, dynamic>{},
      );
      expect(aufruf['action'], 'auto');
      expect(aufruf['liveness'], isTrue);
    });

    test('ohne Freigabe bleibt es bei false', () async {
      await speichereVideo();
      server.funktionsAntworten['verify-account'] = <String, dynamic>{
        'status': 'pending',
      };

      final ok = await service.autoVerification(
        estimatedAge: 30,
        faceCount: 1,
        deviation: 1,
      );

      expect(ok, isFalse);
    });

    test('ohne Video wird nichts freigegeben', () async {
      final ok = await service.autoVerification(
        estimatedAge: 30,
        faceCount: 1,
        deviation: 1,
      );

      expect(ok, isFalse);
      expect(server.funktionsAufrufe, isEmpty);
    });
  });
}
