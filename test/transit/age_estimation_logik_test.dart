// Die reine Logik der lokalen Alterschaetzung (v0.9.1).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/transit/age_estimation_service.dart 193 offene Zeilen bei
// 24 % Abdeckung. Die ONNX-Teile (die Modelle selbst) brauchen die
// native Schicht - die werden NICHT getestet. Die ENTSCHEIDUNGEN
// darum herum sind reine Funktionen, und die sind sicherheitsrelevant:
//
//   * die 2-Jahres-Regel (wer zu alt aussieht, wird manuell geprueft),
//   * der Median ueber die Frames (ein Ausreiser darf nicht durchschlagen),
//   * das Auslesen der Modell-Ausgabe (Jahre direkt, FairFace-Gruppen,
//     Verteilung),
//   * die Gesichtserkennung (NMS - zwei ueberlappende Gesichter duerfen
//     nicht als zwei gelten).
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/transit/age_estimation_service.dart';

void main() {
  group('Die Zwo-Jahres-Regel', () {
    test('genau ein Gesicht und zwei Jahre Abweichung: keine Pruefung', () {
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 30,
          statedAge: 28,
          faceCount: 1,
        ),
        isFalse,
      );
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 30,
          statedAge: 32,
          faceCount: 1,
        ),
        isFalse,
        reason: 'Die Regel gilt in BEIDE Richtungen.',
      );
    });

    test('mehr als zwei Jahre Abweichung: der Support prueft', () {
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 33,
          statedAge: 30,
          faceCount: 1,
        ),
        isTrue,
        reason:
            'Mehr als zwei Jahre sind ein deutlicher Widerspruch - da '
            'muss der Support hinschauen.',
      );
    });

    test('ohne genau ein Gesicht: der Support prueft', () {
      // 0 Gesichter: es ist nicht einmal ein Alter da.
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 30,
          statedAge: 30,
          faceCount: 0,
        ),
        isTrue,
      );
      // 2 Gesichter: das Alter gehoert zu NIEMANDEM.
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 30,
          statedAge: 30,
          faceCount: 2,
        ),
        isTrue,
      );
      // -1 heisst "unbekannt" (kein Detektor geladen) - auch das ist
      // kein "genau ein Gesicht".
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 30,
          statedAge: 30,
          faceCount: -1,
        ),
        isTrue,
      );
    });
  });

  group('Der Median ueber die Frames', () {
    test('eine ungerade Zahl nimmt den mittleren Wert', () {
      expect(AgeEstimationService.medianAge([30.0, 20.0, 25.0]), 25.0);
    });

    test('eine gerade Zahl mittelt die beiden mittleren', () {
      expect(AgeEstimationService.medianAge([10.0, 20.0, 30.0, 40.0]), 25.0);
    });

    test('die Eingabeliste wird nicht veraendert', () {
      final werte = [30.0, 10.0, 20.0];
      AgeEstimationService.medianAge(werte);
      expect(werte, [
        30,
        10,
        20,
      ], reason: 'Der Median darf die Liste des Aufrufers nicht sortieren.');
    });

    test('eine leere Liste hat keinen Median', () {
      expect(AgeEstimationService.medianAge([]), isNull);
    });

    test('ein einzelner Wert ist sein eigener Median', () {
      expect(AgeEstimationService.medianAge([42.0]), 42.0);
    });
  });

  group('Die Zusammenfassung der Frames', () {
    test('zu wenige Frames ergeben nichts', () {
      expect(
        AgeEstimationService.summarizeFrames([
          const AgeEstimation(estimatedAge: 30, confidence: 1, faceCount: 1),
        ]),
        isNull,
        reason:
            'Ein einzelnes Selfie ist kein Beweis - der Support muss '
            'hinschauen (Mindestzahl: '
            '${AgeEstimationService.minFramesForMedian}).',
      );
    });

    test('die Median-Fassung nennt den Median und das Ein-Gesicht-Flag', () {
      final zusammen = AgeEstimationService.summarizeFrames([
        const AgeEstimation(estimatedAge: 30, confidence: 1, faceCount: 1),
        const AgeEstimation(estimatedAge: 20, confidence: 1, faceCount: 1),
        const AgeEstimation(estimatedAge: 25, confidence: 1, faceCount: 1),
      ]);
      expect(zusammen, isNotNull);
      expect(zusammen!.medianAge, 25);
      expect(
        zusammen.allSingleFace,
        isTrue,
        reason: 'Jeder Frame hatte genau ein Gesicht.',
      );
    });

    test('ein Frame mit zwei Gesichten merkt das Ergebnis', () {
      final zusammen = AgeEstimationService.summarizeFrames([
        const AgeEstimation(estimatedAge: 30, confidence: 1, faceCount: 1),
        const AgeEstimation(estimatedAge: 20, confidence: 1, faceCount: 2),
        const AgeEstimation(estimatedAge: 25, confidence: 1, faceCount: 1),
      ]);
      expect(zusammen, isNotNull);
      expect(
        zusammen!.allSingleFace,
        isFalse,
        reason:
            'Ein Frame mit zwei Gesichten heisst: das Alter gehoert zu '
            'niemandem - der Support muss hinschauen.',
      );
    });
  });

  group('Das Auslesen der Modell-Ausgabe', () {
    test('ein Wert ist das Alter direkt (mit voller Konfidenz)', () {
      final ergebnis = AgeEstimationService.parseAgeOutput([31.4]);
      expect(ergebnis, isNotNull);
      expect(ergebnis!.$1, 31.4);
      expect(
        ergebnis.$2,
        1.0,
        reason: 'Ein direkter Jahreswert ist voll vertraenswuerdig.',
      );
    });

    test('neun Werte sind die FairFace-Gruppen', () {
      // Die mittlere Gruppe (Index 4 = 34.5) dominiert.
      final werte = List<double>.filled(9, 0);
      werte[4] = 10;
      final ergebnis = AgeEstimationService.parseAgeOutput(werte);
      expect(ergebnis, isNotNull);
      expect(ergebnis!.$1, closeTo(34.5, 0.01));
      expect(ergebnis.$2, closeTo(1.0, 0.01));
    });

    test('beliebig viele Werte sind eine Verteilung', () {
      // Zwei Gruppen: 0 (Alter 0) und 1 (Alter 1) - Index 1 dominiert.
      final ergebnis = AgeEstimationService.parseAgeOutput([0, 10]);
      expect(ergebnis, isNotNull);
      expect(ergebnis!.$1, closeTo(1.0, 0.001));
      expect(ergebnis.$2, greaterThan(0.99));
    });

    test('eine leere Ausgabe ergibt nichts', () {
      expect(AgeEstimationService.parseAgeOutput([]), isNull);
    });

    test('die Konfidenz bleibt zwischen 0 und 1', () {
      final ergebnis = AgeEstimationService.parseAgeOutput([0, 0, 0]);
      expect(ergebnis, isNotNull);
      expect(ergebnis!.$2, inInclusiveRange(0.0, 1.0));
    });
  });

  group('Die Gesichtserkennung (NMS)', () {
    test('zwei fast gleiche Gesichter ergeben nur eines', () {
      final zeilen = AgeEstimationService.nonMaximumSuppression([
        [0.1, 0.1, 0.5, 0.5, 0.9],
        [0.11, 0.11, 0.51, 0.51, 0.8],
      ], AgeEstimationService.faceNmsIou);
      expect(
        zeilen.length,
        1,
        reason:
            'Zwei Gesichter an derselben Stelle sind EINS - sonst gaebe '
            'die Altersschaetzung zwei Werte fuer ein Gesicht.',
      );
      expect(zeilen.first.$5, closeTo(0.16, 0.01));
    });

    test('zwei weit entfernte Gesichter bleiben beide', () {
      final zeilen = AgeEstimationService.nonMaximumSuppression([
        [0.0, 0.0, 0.2, 0.2, 0.9],
        [0.7, 0.7, 0.9, 0.9, 0.8],
      ], AgeEstimationService.faceNmsIou);
      expect(zeilen.length, 2);
    });

    test('das beste Gesicht gewinnt', () {
      final zeilen = AgeEstimationService.nonMaximumSuppression([
        [0.0, 0.0, 0.2, 0.2, 0.5],
        [0.01, 0.01, 0.21, 0.21, 0.95],
      ], AgeEstimationService.faceNmsIou);
      expect(zeilen.length, 1);
      expect(
        zeilen.first.$5,
        closeTo(0.04, 0.01),
        reason: 'DasGesicht mit dem hoeheren Score bleibt.',
      );
    });

    test('die Koordinaten werden auf 0..1 geklemmt', () {
      final zeilen = AgeEstimationService.nonMaximumSuppression([
        [-0.5, -0.5, 1.5, 1.5, 0.9],
      ], AgeEstimationService.faceNmsIou);
      expect(zeilen.first.$1, 0.0);
      expect(zeilen.first.$2, 0.0);
      expect(zeilen.first.$3, 1.0);
      expect(zeilen.first.$4, 1.0);
    });

    test('eine leere Liste ergibt nichts', () {
      expect(
        AgeEstimationService.nonMaximumSuppression(
          [],
          AgeEstimationService.faceNmsIou,
        ),
        isEmpty,
      );
    });
  });

  group('Der Hash-Vergleich der Modelle', () {
    test('der gleiche Hash wird erkannt (auch in anderer Schreibweise)', () {
      expect(AgeEstimationService.isExpectedSha256('ABCDEF', 'abcdef'), isTrue);
    });

    test('ein anderer Hash wird abgelehnt', () {
      expect(
        AgeEstimationService.isExpectedSha256('abcdef', 'abcdeg'),
        isFalse,
      );
    });

    test('die erwarteten Hashes sind gesetzt', () {
      expect(
        AgeEstimationService.expectedAgeModelSha256.length,
        64,
        reason: 'Ein SHA-256 hat 64 Hex-Zeichen.',
      );
      expect(AgeEstimationService.expectedDetectorSha256.length, 64);
    });
  });
}
