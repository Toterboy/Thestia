// Die Aufbewahrungsfrist der Verifikationsvideos.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/verification/verification_service.dart 90 offene Zeilen -
// darunter die Aufräum-Politik, die nach 7 Tagen alte Videos und ihre
// Dateien entfernt.
//
// DER GRUND: Das Video zeigt Gesicht und Stimme. Es ist damit
// biometrie-nahe personenbezogene Daten. Die Aufbewahrungsfrist ist
// keine Kosmetik: sie ist die Zusage "wir behalten dein Video nicht
// ewig". Ein Fehler darin - ein Filter, der zu wenig loescht - heisst:
// das Video bleibt auf dem Geraet, ohne dass der Nutzer davon weiss.
//
// WAS HIER GEPRUEFT WIRD:
//   * eine Aufnahme, die aelter als die Frist ist, wird beim naechsten
//     Start vom Geraet UND aus dem Speicher entfernt,
//   * eine frische Aufnahme bleibt erhalten,
//   * verwaiste Dateien (der Speichereintrag fehlt schon) werden nach
//     dem Alter der Datei entfernt,
//   * eine fremde Datei im selben Ordner bleibt unangetastet.
//
// ANMERKUNG: Der Aufraeum-Vorgang laeuft im Hintergrund (er blockiert
// die Initialisierung nicht). Der Test wartet deshalb aktiv auf das
// Ergebnis, statt auf eine feste Zeit zu schlafen.
//
// DER WEG BEIM "BLEIBT ERHALTEN": Ein Test, der nur prueft "die Datei
// ist noch da", kann auch dann gruen sein, wenn der Aufraeum noch gar
// nicht gelaufen ist. Deshalb legt der Test ZUSATZLICH eine abgelaufene
// Datei an und wartet, BIS DIE WEG IST - erst dann weiss er, dass der
// Aufraeum gelaufen ist, und kann die frische Datei pruefen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/services/verification/verification_service.dart';
import 'package:thestia/utils/common/best_effort.dart';

import '../support/plugin_mocks.dart';

/// Der Name der Box, in der die Videos liegen.
const String _boxName = 'verification_videos';

void main() {
  late Directory temp;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    temp = await Directory.systemTemp.createTemp('verification_aufbewahrung');
  });

  tearDown(() async {
    await bestEffort('Hive.close', () async {
      await Hive.close();
    });
    await bestEffort('temp.delete', () async {
      await temp.delete(recursive: true);
    });
  });

  /// Legt eine Datei an und setzt ihr Alter (der Aufraeum-Vorgang
  /// beurteilt verwaiste Datei nach ihrer Aenderungszeit).
  Future<File> dateiMitAlter(String ordner, String name, Duration alter) async {
    final datei = File('$ordner/$name');
    await datei.writeAsBytes(<int>[1, 2, 3, 4]);
    await datei.setLastModified(DateTime.now().subtract(alter));
    return datei;
  }

  /// Wartet aktiv darauf, dass [bedingung] eintritt (hoechstens 5 Sekunden).
  Future<bool> warteBis(bool Function() bedingung) async {
    for (var i = 0; i < 50; i++) {
      if (bedingung()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return bedingung();
  }

  /// Der Ablage-Ordner der App (dorthin wandern die Verifikationsvideos).
  Future<String> appOrdner() async =>
      (await getApplicationSupportDirectory()).path;

  /// Baut einen frischen Dienst - sein Start loest den Aufraeum aus.
  Future<VerificationService> dienstMitAufraeum() async {
    final dienst = VerificationService();
    await dienst.initialize();
    return dienst;
  }

  group('Die Aufbewahrungsfrist', () {
    test('eine alte Aufnahme verschwindet vom Geraet', () async {
      final dienst = VerificationService();
      await dienst.initialize();

      final quelle = await dateiMitAlter(
        temp.path,
        'take_alt.mp4',
        Duration.zero,
      );
      final video = await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );
      expect(File(video.filePath).existsSync(), isTrue);

      // DER WEG: Der Aufraeum beurteilt den Box-Eintrag nach dem
      // Aufnahmezeitpunkt. Der Test veraltet ihn - so braucht man
      // keine acht Tage zu warten.
      final box = Hive.box<String>(_boxName);
      final roh = box.get(video.filePath);
      expect(roh, isNotNull, reason: 'Die Aufnahme muss im Speicher stehen.');
      final eintrag = jsonDecode(roh!) as Map<String, dynamic>;
      eintrag['recordedAt'] = DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String();
      await box.put(video.filePath, jsonEncode(eintrag));

      // Der naechste Start raeumt auf.
      final neu = await dienstMitAufraeum();

      expect(
        await warteBis(() => !File(video.filePath).existsSync()),
        isTrue,
        reason:
            'Die Datei muss auch vom Geraet verschwinden - der '
            'Speichereintrag allein waere nur die halbe Loeschung.',
      );
      expect(
        neu.getVerificationVideo(),
        isNull,
        reason:
            'Nach der Frist darf kein Video mehr im Speicher stehen - '
            'das ist die Zusage der Datenminimierung.',
      );
    });

    test('eine frische Aufnahme bleibt erhalten', () async {
      final dienst = VerificationService();
      await dienst.initialize();

      final quelle = await dateiMitAlter(
        temp.path,
        'take_neu.mp4',
        Duration.zero,
      );
      final video = await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );

      // Der Ausloeser fuer "der Aufraeum ist gelaufen": eine abgelaufene
      // Datei, die verschwinden MUSS.
      final ordner = await appOrdner();
      final ausloeser = await dateiMitAlter(
        ordner,
        'verification_ausloeser.mp4',
        const Duration(days: 10),
      );

      final neu = await dienstMitAufraeum();
      expect(
        await warteBis(() => !ausloeser.existsSync()),
        isTrue,
        reason: 'Der Aufraeum muss gelaufen sein - sonst waere der Test leer.',
      );

      expect(
        neu.getVerificationVideo(),
        isNotNull,
        reason:
            'Eine Aufnahme innerhalb der Frist muss erhalten bleiben - '
            'sonst koennte der Nutzer sein Video nicht mehr pruefen.',
      );
      expect(File(video.filePath).existsSync(), isTrue);
    });

    test('eine verwaiste alte Datei wird entfernt', () async {
      // DER FALL: Der Box-Eintrag fehlt schon (etwa weil die App
      // abgestuerzt ist), die Datei liegt aber noch da. Ohne den
      // zweiten Teil des Aufraeums bliebe sie liegen.
      final ordner = await appOrdner();
      final verwaist = await dateiMitAlter(
        ordner,
        'verification_verwaist.mp4',
        const Duration(days: 10),
      );
      expect(verwaist.existsSync(), isTrue);

      await dienstMitAufraeum();

      expect(
        await warteBis(() => !verwaist.existsSync()),
        isTrue,
        reason:
            'Eine verwaiste Datei, die aelter als die Frist ist, muss '
            'weg - sonst sammelt sich biometrisches Material auf dem '
            'Geraet an.',
      );
    });

    test('eine verwaiste frische Datei bleibt erhalten', () async {
      final ordner = await appOrdner();
      final frisch = await dateiMitAlter(
        ordner,
        'verification_frisch.mp4',
        Duration.zero,
      );
      expect(frisch.existsSync(), isTrue);
      // Der Ausloeser: eine abgelaufene Datei, die verschwinden MUSS.
      final ausloeser = await dateiMitAlter(
        ordner,
        'verification_ausloeser2.mp4',
        const Duration(days: 10),
      );

      await dienstMitAufraeum();
      expect(
        await warteBis(() => !ausloeser.existsSync()),
        isTrue,
        reason: 'Der Aufraeum muss gelaufen sein - sonst waere der Test leer.',
      );

      expect(
        frisch.existsSync(),
        isTrue,
        reason:
            'Eine frische Datei darf nicht weggeraeumt werden - sie '
            'koennte noch zu einer laufenden Aufnahme gehoeren.',
      );
    });

    test('eine fremde Datei bleibt unangetastet', () async {
      // DER GRUND: Der Aufraeum darf nicht den ganzen Ordner leeren -
      // er raeumt nur die Verifikationsvideos.
      final ordner = await appOrdner();
      final fremd = await dateiMitAlter(
        ordner,
        'mein_foto.jpg',
        const Duration(days: 30),
      );
      expect(fremd.existsSync(), isTrue);
      // Der Ausloeser: eine abgelaufene Verifikationsdatei.
      final ausloeser = await dateiMitAlter(
        ordner,
        'verification_ausloeser3.mp4',
        const Duration(days: 10),
      );

      await dienstMitAufraeum();
      expect(
        await warteBis(() => !ausloeser.existsSync()),
        isTrue,
        reason: 'Der Aufraeum muss gelaufen sein - sonst waere der Test leer.',
      );

      expect(
        fremd.existsSync(),
        isTrue,
        reason:
            'Der Aufraeum gehoert nur den Verifikationsvideos - '
            'sonst wuerde er die Bilder des Nutzers loeschen.',
      );
    });

    test('der Aufraeum laeuft auch ohne Aufnahme', () async {
      // DER GRUND: Der Aufraeum darf nicht abstuerzen, wenn es nichts
      // zu loeschen gibt - sonst waere der naechste Start der App
      // kaputt.
      final dienst = await dienstMitAufraeum();
      expect(dienst.getVerificationVideo(), isNull);
      // Und die Box ist danach weiter benutzbar.
      final quelle = await dateiMitAlter(
        temp.path,
        'take_danach.mp4',
        Duration.zero,
      );
      final video = await dienst.saveVerificationVideo(
        filePath: quelle.path,
        challengeType: VerificationChallengeType.smile,
        challengeData: 'smile',
      );
      expect(video.filePath, isNotEmpty);
    });
  });
}
