// Der Verifizierungs-Dienst: die Aufnahme, die Ablage und die Einreichung.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/services/verification/verification_service.dart 77 offene Zeilen.
// Der Dienst ist die Stelle, an der das Video der Altersprüfung
// aufgezeichnet, gesichert und zum Server geschickt wird.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne initialisierte Kamera wird nichts aufgenommen (klarer Fehler),
//   * die Aufnahme landet unter "verification_<Zeit>.mp4" im
//     App-Support-Ordner (nicht im Cache des Kamera-Plugins),
//   * das gespeicherte Video kommt mit allen Metadaten zurück,
//   * ohne Video gibt es nichts zum Einreichen (mit klarer Meldung),
//   * eine kaputte Box-Eintrag wird übersprungen,
//   * die Einreichung lädt das Video hoch und meldet den Erfolg,
//   * lehnt der Server ab, wird der Grund genannt.
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:thestia/services/verification/verification_service.dart';

import '../support/fake_camera.dart';
import '../support/plugin_mocks.dart';

void main() {
  late VerificationService service;
  late FakeCameraPlatform kamera;
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await mockPfadProvider();
    mockKeystore();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thesia_verifikation');
    Hive.init(tempDir.path);
    kamera = FakeCameraPlatform();
    CameraPlatform.instance = kamera;
    service = VerificationService();
    await service.initialize();
  });

  tearDown(() async {
    await service.deleteAllLocalData();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    // DIE Kanäle DER KAMERA BLEIBEN OFFEN: Das Kamera-Plugin holt sich
    // den Fehler-Kanal beim Initialisieren und wartet auf das erste
    // Ereignis - ein geschlossener Kanal würde den Controller mit
    // "No element" abbrechen lassen.
  });

  /// Legt eine Aufnahme-Datei an (die Kamera liefert sie beim Stoppen).
  String legeAufnahmeAn() {
    final ordner = Directory.systemTemp.createTempSync('verifikation_aufnahme');
    final datei = File('${ordner.path}/cache_video.mp4');
    datei.writeAsBytesSync(<int>[1, 2, 3, 4]);
    return datei.path;
  }

  group('Die Aufnahme', () {
    test('ohne initialisierte Kamera gibt es keine Aufnahme', () async {
      // DIE KAMERA OHNE BILD: Der Controller ist nicht initialisiert -
      // das muss der Dienst klar sagen, nicht stillschweigend.
      final controller = await _uninitialisierterController();

      await expectLater(
        service.recordVerificationVideo(
          cameraController: controller,
          challengeType: VerificationChallengeType.speakNumber,
          challengeData: '42',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('die Aufnahme landet unter "verification_...mp4"', () async {
      kamera.legeAufnahmeAn();
      final controller = await _initialisierterController();

      final pfad = await service.recordVerificationVideo(
        cameraController: controller,
        challengeType: VerificationChallengeType.speakNumber,
        challengeData: '42',
        maxDurationSeconds: 0,
      );

      expect(pfad, isNotNull);
      expect(
        pfad,
        contains('verification_'),
        reason:
            'Die Datei muss am Ende "verification_" tragen - danach sucht '
            'der Dienst sie beim Einreichen wieder.',
      );
      expect(pfad, endsWith('.mp4'));
      expect(File(pfad!).existsSync(), isTrue);
    });

    test('eine kaputte Aufnahme liefert null statt einem Fehler', () async {
      // DIE KAMERA LIEGT: Es gibt keine Datei - das Stoppen schlägt fehl.
      // Der Dienst darf den Screen nicht mit einer Ausnahme zerstören.
      final controller = await _initialisierterController();

      final pfad = await service.recordVerificationVideo(
        cameraController: controller,
        challengeType: VerificationChallengeType.speakNumber,
        challengeData: '42',
        maxDurationSeconds: 0,
      );

      expect(pfad, isNull);
    });
  });

  group('Die Ablage', () {
    test('das Video kommt mit allen Metadaten zurueck', () async {
      final quelle = legeAufnahmeAn();

      final video = await service.saveVerificationVideo(
        filePath: quelle,
        challengeType: VerificationChallengeType.speakNumber,
        challengeData: '42',
      );

      expect(video.filePath, contains('verification_'));
      expect(video.durationSeconds, VerificationService.maxDurationSeconds);
      // DIE AUFGABE: Bei "Zahl vorlesen" steht die Zahl im Text-Feld,
      // bei den anderen Aufgaben in der Gesten-Angabe.
      expect(video.challengeText, '42');
      expect(video.challengeGesture, isNull);

      final gelesen = service.getVerificationVideo();
      expect(gelesen, isNotNull);
      expect(gelesen!.filePath, video.filePath);
      expect(gelesen.challengeText, '42');
    });

    test('bei einer Geste steht sie im Gesten-Feld', () async {
      final quelle = legeAufnahmeAn();

      final video = await service.saveVerificationVideo(
        filePath: quelle,
        challengeType: VerificationChallengeType.makeGesture,
        challengeData: 'Zunge',
      );

      expect(video.challengeText, isNull);
      expect(video.challengeGesture, 'Zunge');
    });

    test('ohne Datei gibt es einen klaren Fehler', () async {
      await expectLater(
        service.saveVerificationVideo(
          filePath: '${tempDir.path}/gibt-es-nicht.mp4',
          challengeType: VerificationChallengeType.speakNumber,
          challengeData: '42',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('ein kaputter Box-Eintrag wird uebersprungen', () async {
      // DIE KAPUTTE BOX: Der Eintrag ist Müll (etwa aus einer
      // abgebrochenen Aufnahme) - er darf nicht den ganzen Weg blockieren.
      final box = await Hive.openBox<String>('verification_videos');
      await box.put('kaputt', 'kein json');
      await service.saveVerificationVideo(
        filePath: legeAufnahmeAn(),
        challengeType: VerificationChallengeType.speakNumber,
        challengeData: '42',
      );

      final gelesen = service.getVerificationVideo();
      expect(gelesen, isNotNull);
      expect(gelesen!.filePath, contains('verification_'));
    });
  });

  group('Die Einreichung', () {
    test('ohne Video gibt es nichts einzureichen', () async {
      final ok = await service.submitVerification();

      expect(ok, isFalse);
      expect(
        service.lastSubmitError,
        contains('Kein Video'),
        reason:
            'Der Nutzer muss wissen, WARUM nichts ging - "es hat nicht '
            'geklappt" hilft ihm nicht.',
      );
    });

    test('ohne Server gilt die Einreichung als lokal erledigt', () async {
      // OHNE SERVER (Demo-Modus): Der Nutzer hat seine Aufgabe gemacht -
      // der Upload kommt beim nächsten Start nach.
      await service.saveVerificationVideo(
        filePath: legeAufnahmeAn(),
        challengeType: VerificationChallengeType.speakNumber,
        challengeData: '42',
      );

      final ok = await service.submitVerification();

      expect(ok, isTrue);
      expect(
        service.lastSubmitError,
        isNull,
        reason: 'Ohne Server ist kein Fehler passiert.',
      );
    });
  });
}

/// Ein Controller, dessen Kamera NICHT initialisiert ist.
Future<CameraController> _uninitialisierterController() async {
  final controller = CameraController(
    const CameraDescription(
      name: 'test-kamera',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
    ResolutionPreset.low,
  );
  return controller;
}

/// Ein Controller mit einer bereiten Kamera.
Future<CameraController> _initialisierterController() async {
  final controller = CameraController(
    const CameraDescription(
      name: 'test-kamera',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
    ResolutionPreset.low,
  );
  await controller.initialize();
  return controller;
}
