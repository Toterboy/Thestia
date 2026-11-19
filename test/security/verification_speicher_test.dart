// Der lokale Speicher des Verifikationsvideos.
//
// ANLASS (19.11.2026): `lib/services/verification/verification_service.dart`
// war nur zu 28 % abgedeckt. Gerade der Speicher ist heikel: das Video
// zeigt Gesicht und Stimme und ist damit biometrie-nahe personenbezogene
// Daten (DSGVO). Wer es loescht, muss es WIRKLICH loeschen.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Aufnahme wird in den App-Support-Ordner kopiert und der
//     Cache-Original wird entfernt,
//   * bei erneuter Aufnahme kommt die NEUESTE zurueck (der alte Bug
//     lieferte das alte Video und liess das frische liegen),
//   * der Status "verifiziert" und das Loeschen funktionieren,
//   * "alles loeschen" entfernt auch verwaiste Videodateien.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thestia/services/verification/verification_service.dart';
import 'package:thestia/utils/common/best_effort.dart';

import '../support/plugin_mocks.dart';

/// Erzeugt eine echte (kleine) Videodatei im Cache.
Future<File> _aufnahme(String ordner, String name) async {
  final datei = File('$ordner/$name');
  await datei.writeAsBytes(<int>[1, 2, 3, 4]);
  return datei;
}

void main() {
  late Directory temp;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    temp = await Directory.systemTemp.createTemp('verification_service_test');
  });

  tearDown(() async {
    await bestEffort('Hive.close', () async {
      await Hive.close();
    });
    await bestEffort('temp.delete', () async {
      await temp.delete(recursive: true);
    });
  });

  Future<VerificationService> neuerDienst() async {
    final dienst = VerificationService();
    await dienst.initialize();
    return dienst;
  }

  group('Der leere Speicher', () {
    test('kein Video, kein verifizierter Nutzer', () async {
      final dienst = await neuerDienst();
      expect(dienst.getVerificationVideo(), isNull);
      expect(dienst.isVerified, isFalse);
    });
  });

  group('Das Speichern der Aufnahme', () {
    test('die Datei wird in den App-Ordner kopiert', () async {
      final dienst = await neuerDienst();
      final quelle = await _aufnahme(temp.path, 'take_1.mp4');

      final video = await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.speakNumber,
        challengeData: '4821',
      );

      expect(video.filePath, contains('verification_'));
      expect(video.filePath, endsWith('.mp4'));
      expect(File(video.filePath).existsSync(), isTrue);
      // Das Cache-Original gehoert dem Kamera-Plugin und wird entfernt.
      expect(quelle.existsSync(), isFalse);
      // Bei 'Zahl vorlesen' steht die Zahl im Text-Feld.
      expect(video.challengeText, '4821');
      expect(video.challengeGesture, isNull);
    });

    test('bei einer Geste steht sie im Gesten-Feld', () async {
      final dienst = await neuerDienst();
      final quelle = await _aufnahme(temp.path, 'take_2.mp4');
      final video = await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.makeGesture,
        challengeData: 'tongue',
      );
      expect(video.challengeText, isNull);
      expect(video.challengeGesture, 'tongue');
    });

    test(
      'eine fehlende Aufnahme wird gemeldet statt still zu scheitern',
      () async {
        final dienst = await neuerDienst();
        await expectLater(
          dienst.saveVerificationVideo(
            filePath: '${temp.path}/gibtsnicht.mp4',
            challengeType: VerificationChallengeType.smile,
            challengeData: 'smile',
          ),
          throwsStateError,
        );
      },
    );

    test('die NEUESTE Aufnahme gewinnt (alter Bug: die aelteste)', () async {
      final dienst = await neuerDienst();
      final erste = await _aufnahme(temp.path, 'take_old.mp4');
      final alte = await dienst.saveVerificationVideo(
        filePath: erste.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );
      // Der Zeitstempel kommt von DateTime.now() - eine kleine Pause
      // reicht, damit die zweite Aufnahme wirklich spaeter ist.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final zweite = await _aufnahme(temp.path, 'take_new.mp4');
      final neue = await dienst.saveVerificationVideo(
        filePath: zweite.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );
      expect(neue.recordedAt.isAfter(alte.recordedAt), isTrue);

      final gefunden = dienst.getVerificationVideo();
      expect(gefunden, isNotNull);
      expect(gefunden!.filePath, neue.filePath);
      // Die alte Datei ist weg - nur das aktuelle Video bleibt.
      expect(File(alte.filePath).existsSync(), isFalse);
      expect(File(neue.filePath).existsSync(), isTrue);
    });
  });

  group('Die Einreichung', () {
    test('ohne Video wird abgebrochen - mit verstaendlichem Grund', () async {
      final dienst = await neuerDienst();
      final erfolg = await dienst.submitVerification();
      expect(erfolg, isFalse);
      expect(
        dienst.lastSubmitError,
        contains('Kein Video'),
        reason:
            'Der Nutzer muss sehen, warum die Einreichung nicht lief - '
            'sonst haengt er an einem unsichtbaren Fehler fest.',
      );
    });

    test('offline gilt die Einreichung lokal als erledigt', () async {
      // DER GRUND: Der Nutzer hat seine Aufgabe erfuellt - der Upload
      // wird beim naechsten Start nachgeholt. Ohne diesen Pfad waere
      // die Einreichung bei kurzzeitigem Netzausfall verloren.
      final dienst = await neuerDienst();
      final quelle = await _aufnahme(temp.path, 'take_offline.mp4');
      await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );

      // In diesem Unit-Test ist der Supabase-Client nicht initialisiert.
      expect(await dienst.submitVerification(), isTrue);
    });
  });

  group('Der Status und das Loeschen', () {
    test('markAsVerified setzt den Status', () async {
      final dienst = await neuerDienst();
      final quelle = await _aufnahme(temp.path, 'take_3.mp4');
      final video = await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );
      expect(dienst.isVerified, isFalse);

      await dienst.markAsVerified(video.filePath);
      expect(dienst.isVerified, isTrue);
    });

    test('markAsVerified mit unbekanntem Pfad tut nichts', () async {
      final dienst = await neuerDienst();
      await dienst.markAsVerified('gibtsnicht');
      expect(dienst.isVerified, isFalse);
    });

    test('deleteVideo entfernt Eintrag und Datei', () async {
      final dienst = await neuerDienst();
      final quelle = await _aufnahme(temp.path, 'take_4.mp4');
      final video = await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );
      final pfad = video.filePath;

      await dienst.deleteVideo(pfad);

      expect(dienst.getVerificationVideo(), isNull);
      expect(File(pfad).existsSync(), isFalse);
    });

    test('deleteAllLocalData loescht auch verwaiste Videodateien', () async {
      final dienst = await neuerDienst();
      final quelle = await _aufnahme(temp.path, 'take_5.mp4');
      await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );
      // Eine verwaiste Datei im Support-Ordner (ohne Box-Eintrag).
      final verwaist = await _aufnahme(
        (await getApplicationSupportDirectory()).path,
        'verification_verwaist.mp4',
      );
      expect(verwaist.existsSync(), isTrue);

      await dienst.deleteAllLocalData();

      expect(dienst.getVerificationVideo(), isNull);
      expect(verwaist.existsSync(), isFalse);
    });
  });
}
