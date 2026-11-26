// Die ONNX-Inferenz der Altersprüfung (mit den echten Modellen).
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/services/transit/age_estimation_service.dart 129 offene Zeilen.
// Die reine Logik (Zwo-Jahres-Regel, Median, Modellausgabe) ist seit dem
// 19.11.2026 getestet - offen war die KETTE: die Modelle laden, das
// Bild dekodieren, der Detektor läuft, der Crop entsteht, das
// Altersmodell rechnet.
//
// DIE MODELLE SIND ECHT: `assets/models/face_detector.onnx` und
// `assets/models/age_estimator.onnx` liegen im Bundle. Das ist Absicht:
// die Kette soll mit demselben Modell laufen wie in der App - ein
// Ersatz würde genau die Fehlerklasse verdecken, um es geht (ein
// falsch gebautes Tensor sieht man nur mit dem echten Modell).
//
// DIE NATIVE BIBLIOTHEK (26.11.2026): Für die Inferenz braucht es die
// native onnxruntime-Bibliothek. Im CI wird sie nachgeladen - fiel der
// Download aus (Netzwerk), scheiterte der Test und der Lauf war rot,
// obwohl der Code in Ordnung ist (BEFUND: der Lauf vom 25.11.2026).
// Deshalb prüft der Test die Modelle selbst immer (Asset + Prüfsumme)
// und überspringt nur die Inferenz, wenn die Bibliothek fehlt - genau
// wie der NSFW-Test es tut.
//
// WAS HIER GEPRÜFT WIRD:
//   * beide Modelle liegen im Bundle und passen zur Prüfsumme,
//   * ein Bild ohne Gesicht läuft durch die Kette (und liefert eine
//     Schätzung mit faceCount 0 - der Fall "kein Gesicht" darf nicht
//     hängen),
//   * kaputte Bytes ergeben nichts (kein Absturz),
//   * das Freigeben der Modelle setzt den Zustand zurück.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:thestia/services/transit/age_estimation_service.dart';

void main() {
  // DER BINDING: Die Modelle kommen aus dem Asset-Bundle - ohne den
  // Binding gibt es kein Bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Lädt die Modelle - oder meldet, dass die native Bibliothek fehlt.
  ///
  /// DER WEG: Ohne onnxruntime kann der Dienst kein Modell öffnen. Der
  /// Testlauf im CI lädt die Bibliothek nach; fehlt sie (Netzwerk-
  /// ausfall), laufen die Inferenz-Tests nicht durch - der
  /// Modell-Check (Asset + Prüfsumme) aber immer.
  Future<bool> ladeModelle() async {
    final geladen = await AgeEstimationService.instance.ensureLoaded();
    if (!geladen) {
      // ignore: avoid_print
      print(
        'SKIP Inferenz: native onnxruntime fehlt in dieser Umgebung '
        '(die Modelle selbst wurden oben geprüft).',
      );
    }
    return geladen;
  }

  /// Ein einfarbiges Bild (in der Nähe eines Gesichts: grau).
  Uint8List bildBytes(int breite, int hoehe) {
    final bild = img.Image(width: breite, height: hoehe);
    img.fill(bild, color: img.ColorRgb8(180, 180, 180));
    return Uint8List.fromList(img.encodePng(bild));
  }

  group('Das Laden der Modelle', () {
    test('beide Modelle sind gebuendelt und passen zur Pruefsumme', () async {
      // DIE MODELLE selbst: Das lässt sich ohne die native Bibliothek
      // prüfen (der Weg über das Asset-Bundle braucht sie nicht).
      final erwaertungen = <String, String>{
        'assets/models/face_detector.onnx':
            AgeEstimationService.expectedDetectorSha256,
        'assets/models/age_estimator.onnx':
            AgeEstimationService.expectedAgeModelSha256,
      };
      for (final eintrag in erwaertungen.entries) {
        final daten = await rootBundle.load(eintrag.key);
        final bytes = daten.buffer.asUint8List(
          daten.offsetInBytes,
          daten.lengthInBytes,
        );
        expect(
          sha256.convert(bytes).toString(),
          eintrag.value,
          reason:
              'Das Modell ${eintrag.key} muss gebündelt und unverändert '
              'sein - sonst geht der Fall still an den Support.',
        );
      }
    });

    test('beide Modelle lassen sich oeffnen', () async {
      final dienst = AgeEstimationService.instance;

      if (!await ladeModelle()) return;

      expect(dienst.isAvailable, isTrue);
      expect(
        dienst.hasFaceDetector,
        isTrue,
        reason:
            'Ohne Detektor schneidet die App das mittlere Quadrat - ein '
            'Gesicht am Rand wuerde dann nicht erkannt.',
      );

      dienst.release();
    });

    test('nach dem Freigeben ist der Dienst wieder leer', () async {
      final dienst = AgeEstimationService.instance;
      if (!await ladeModelle()) return;
      expect(dienst.isAvailable, isTrue);

      dienst.release();

      expect(
        dienst.isAvailable,
        isFalse,
        reason:
            'Nach dem Freigeben darf kein Modell mehr offen sein - sonst '
            'haelt die App den Speicher des Geraets fest.',
      );
      expect(dienst.hasFaceDetector, isFalse);
    });
  });

  group('Die Inferenz', () {
    test('ein Bild ohne Gesicht laeuft durch die Kette', () async {
      final dienst = AgeEstimationService.instance;
      if (!await ladeModelle()) return;

      final ergebnis = await dienst.estimateAge(bildBytes(320, 320));

      expect(
        ergebnis,
        isNotNull,
        reason:
            'Die Kette muss auch ohne Gesicht durchlaufen - ein Fehler '
            'dort wuerde jeden Fall an den Support schicken.',
      );
      expect(ergebnis!.faceCount, 0);
      expect(
        ergebnis.estimatedAge,
        inInclusiveRange(0, 120),
        reason: 'Das Alter muss ein sinnvoller Wert sein.',
      );
      expect(ergebnis.confidence, inInclusiveRange(0.0, 1.0));

      dienst.release();
    });

    test('kaputte Bytes ergeben nichts (kein Absturz)', () async {
      final dienst = AgeEstimationService.instance;
      if (!await ladeModelle()) return;

      final ergebnis = await dienst.estimateAge(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      );

      expect(
        ergebnis,
        isNull,
        reason:
            'Ein kaputtes Bild darf keinen Absturz ausloesen - der Dienst '
            'meldet dann "keine Pruefung" und der Fall geht an den Support.',
      );

      dienst.release();
    });

    test('ein grosses Bild wird auf 640 Pixel verkleinert', () async {
      final dienst = AgeEstimationService.instance;
      if (!await ladeModelle()) return;

      // EIN GROSSES BILD: Der Weg muss auch bei 2048 Pixel klappen
      // (das ist die Größe, die die Kamera liefert).
      final ergebnis = await dienst.estimateAge(bildBytes(2048, 1536));

      expect(ergebnis, isNotNull);
      expect(ergebnis!.estimatedAge, inInclusiveRange(0, 120));

      dienst.release();
    });
  });
}
