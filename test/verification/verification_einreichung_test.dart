// Die Einreichung der Alters-Verifizierung.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/verification/verification_service.dart 67 offene Zeilen.
// Die Aufnahme und die Ablage sind getestet - offen war das
// EINREICHEN: das Video verschluesselt hochladen, dem Server geben und
// die Antwort auswerten.
//
// DER WEG: Der Supabase-Client bekommt den [FakeSupabaseServer] - der
// kann den Speicher-Upload und die Edge Function beantworten.
//
// WAS HIER GEPRUEFT WIRD:
//   * ohne Datei auf dem Geraet wird der Grund genannt (nicht nur
//     "fehlgeschlagen"),
//   * der Server nimmt die Einreichung an - und das Video wird danach
//     vom Geraet geloescht (der Speicher des Nutzers soll nicht voller
//     Videos bleiben),
//   * lehnt der Server ab, steht der Grund in der Meldung.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/services/verification/verification_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

void main() {
  late FakeSupabaseServer server;
  late VerificationService service;
  late Directory tempDir;

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
    // DIE SITZUNG: Ohne sie schickt der Dienst nichts ("Nicht
    // eingeloggt").
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('verifikation_einreichung');
    Hive.init(tempDir.path);
    server.pfade.clear();
    server.funktionsAufrufe.clear();
    server.funktionsAntworten.clear();
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

  /// Legt eine Video-Datei an und merkt sich ihren Pfad.
  String legeVideoAn() {
    final datei = File('${tempDir.path}/video.mp4');
    datei.writeAsBytesSync(<int>[1, 2, 3, 4]);
    return datei.path;
  }

  /// Merkt das Video im Dienst ab (wie nach der Aufnahme).
  Future<void> merkeVideoAn(String pfad) async {
    await service.saveVerificationVideo(
      filePath: pfad,
      challengeType: VerificationChallengeType.speakNumber,
      challengeData: '42',
    );
  }

  group('Die Einreichung', () {
    test('ohne Datei wird der Grund genannt', () async {
      // DER FEHLENDE FILE: Das Video steht in der Ablage, die Datei
      // fehlt aber (z. B. weil der Speicher voll war).
      legeVideoAn();
      await merkeVideoAn(legeVideoAn());
      // DIE KOPIE: Das Video liegt nach dem Speichern an einem anderen Ort
      // (im App-Support-Verzeichnis) - genau die Datei muss fehlen.
      final gespeichert = service.getVerificationVideo()!.filePath;
      await File(gespeichert).delete();

      final ok = await service.submitVerification();

      expect(ok, isFalse);
      expect(
        service.lastSubmitError,
        contains('fehlt'),
        reason:
            'Der Nutzer muss erfahren, dass die Datei fehlt - ein '
            'generisches "fehlgeschlagen" hilft ihm nicht.',
      );
    });

    test('der Server nimmt die Einreichung an', () async {
      server.funktionsAntworten['verify-account'] = <String, dynamic>{
        'status': 'pending',
      };
      final pfad = legeVideoAn();
      await merkeVideoAn(pfad);

      final ok = await service.submitVerification();

      expect(ok, isTrue);
      expect(
        server.funktionsAufrufe.any((c) => c['funktion'] == 'verify-account'),
        isTrue,
        reason:
            'Die Einreichung muss bei der Edge Function landen - dort '
            'entscheidet der Server ueber die Freigabe.',
      );
      expect(
        File(pfad).existsSync(),
        isFalse,
        reason:
            'Nach der Annahme wird das Video vom Geraet geloescht - der '
            'Speicher des Nutzers soll nicht voller Videos bleiben.',
      );
    });

    test('lehnt der Server ab, steht der Grund drin', () async {
      server.funktionsAntworten['verify-account'] = <String, dynamic>{
        'status': 'rejected',
        'error': 'Das Alter passt nicht zur Schätzung',
      };
      await merkeVideoAn(legeVideoAn());

      final ok = await service.submitVerification();

      expect(ok, isFalse);
      expect(
        service.lastSubmitError,
        contains('Das Alter passt nicht zur Schätzung'),
        reason:
            'Der Nutzer muss den Grund der Ablehnung kennen - nur so '
            'kann er etwas dagegen tun.',
      );
    });
  });
}
