import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/age_estimation_service.dart';

void main() {
  group('2-Jahre-Regel (v0.9.1)', () {
    test('Abweichung bis 2 Jahre mit genau einem Gesicht ist ok', () {
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 22.0,
          statedAge: 22,
          faceCount: 1,
        ),
        isFalse,
      );
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 24.0,
          statedAge: 22,
          faceCount: 1,
        ),
        isFalse,
      );
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 20.0,
          statedAge: 22,
          faceCount: 1,
        ),
        isFalse,
      );
    });

    test('Abweichung über 2 Jahre braucht manuelle Prüfung', () {
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 24.1,
          statedAge: 22,
          faceCount: 1,
        ),
        isTrue,
      );
      // Der 80-als-22-Fall aus dem Beta-Test.
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: 80.0,
          statedAge: 22,
          faceCount: 1,
        ),
        isTrue,
      );
    });

    test('kein oder mehrere Gesichter brauchen manuelle Prüfung', () {
      for (final faces in [-1, 0, 2, 5]) {
        expect(
          AgeEstimationService.needsManualReview(
            estimatedAge: 22.0,
            statedAge: 22,
            faceCount: faces,
          ),
          isTrue,
          reason: 'faceCount=$faces',
        );
      }
    });
  });

  group('FairFace-Gruppen (v0.9.1)', () {
    test('[1,1] gibt Jahre direkt zurück', () {
      final parsed = AgeEstimationService.parseAgeOutput([34.0]);
      expect(parsed, isNotNull);
      expect(parsed!.$1, 34.0);
      expect(parsed.$2, 1.0);
    });

    test('[1,9] nutzt Gruppenmitten (20-29 -> ~24.5)', () {
      // Klare 20-29-Antwort (Index 3).
      final logits = [0.0, 0.0, 0.0, 10.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final parsed = AgeEstimationService.parseAgeOutput(logits);
      expect(parsed, isNotNull);
      expect(parsed!.$1, closeTo(24.5, 0.5));
      // 80-als-22-Fall: 70+ dominant -> ~75.
      final old = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0];
      final parsedOld = AgeEstimationService.parseAgeOutput(old);
      expect(parsedOld!.$1, closeTo(75.0, 0.5));
      expect(
        AgeEstimationService.needsManualReview(
          estimatedAge: parsedOld.$1,
          statedAge: 22,
          faceCount: 1,
        ),
        isTrue,
      );
    });

    test('leerer Output ist ungültig', () {
      expect(AgeEstimationService.parseAgeOutput([]), isNull);
    });
  });

  group('Mehrframe-Median (v0.9.0)', () {
    test('Median bei ungerader Zahl ist der mittlere Wert', () {
      expect(AgeEstimationService.medianAge([27.0, 19.0, 21.0]), 21.0);
    });

    test('Median schluckt Einzelbild-Ausreißer (27 statt 18)', () {
      // Der gemeldete Fall: ein Frame sagt 27, vier sagen ~18-20.
      expect(
        AgeEstimationService.medianAge([27.0, 18.5, 19.0, 18.0, 20.0]),
        19.0,
      );
    });

    test('Median bei gerader Zahl mittelt die Mitte', () {
      expect(AgeEstimationService.medianAge([18.0, 22.0]), 20.0);
    });

    test('leere Liste gibt null', () {
      expect(AgeEstimationService.medianAge([]), isNull);
    });

    AgeEstimation est(double age, int faces) =>
        AgeEstimation(estimatedAge: age, confidence: 1.0, faceCount: faces);

    test('summarizeFrames: Median + alle ein Gesicht', () {
      final summary = AgeEstimationService.summarizeFrames([
        est(27.0, 1),
        est(18.5, 1),
        est(19.0, 1),
      ]);
      expect(summary, isNotNull);
      expect(summary!.medianAge, 19.0);
      expect(summary.allSingleFace, isTrue);
    });

    test('summarizeFrames: fremdes Gesicht in einem Frame -> manuell', () {
      final summary = AgeEstimationService.summarizeFrames([
        est(19.0, 1),
        est(22.0, 2),
        est(18.5, 1),
      ]);
      expect(summary, isNotNull);
      expect(summary!.allSingleFace, isFalse);
    });

    test('summarizeFrames: unter 3 Frames -> null (manuelle Prüfung)', () {
      expect(
        AgeEstimationService.summarizeFrames([est(19.0, 1), est(20.0, 1)]),
        isNull,
      );
      expect(AgeEstimationService.summarizeFrames([]), isNull);
    });
  });

  group('Modell-Integrität (v0.9.0)', () {
    test('gleicher Hash (case-insensitiv) gilt', () {
      expect(AgeEstimationService.isExpectedSha256('ABC123', 'abc123'), isTrue);
    });

    test('ausgetauschtes Modell (falscher Hash) fällt durch', () {
      expect(
        AgeEstimationService.isExpectedSha256(
          '00' * 32,
          AgeEstimationService.expectedAgeModelSha256,
        ),
        isFalse,
      );
    });

    test('erwartete Hashes sind gültige SHA-256-Hexstrings', () {
      final hex = RegExp(r'^[0-9a-f]{64}$');
      expect(hex.hasMatch(AgeEstimationService.expectedAgeModelSha256), isTrue);
      expect(hex.hasMatch(AgeEstimationService.expectedDetectorSha256), isTrue);
    });
  });

  group('UltraFace-NMS (v0.9.1)', () {
    test('stark überlappende Box, schwächere fliegt raus', () {
      final rows = [
        [0.1, 0.1, 0.5, 0.5, 0.9],
        [0.12, 0.12, 0.52, 0.52, 0.7],
        [0.7, 0.7, 0.9, 0.9, 0.8],
      ];
      final kept = AgeEstimationService.nonMaximumSuppression(rows, 0.4);
      expect(kept.length, 2);
      // Stärkste zuerst.
      expect(kept.first.$5, greaterThan(kept.last.$5));
    });

    test('disjunkte Boxen bleiben alle', () {
      final rows = [
        [0.0, 0.0, 0.2, 0.2, 0.9],
        [0.4, 0.4, 0.6, 0.6, 0.8],
        [0.7, 0.7, 0.9, 0.9, 0.7],
      ];
      expect(AgeEstimationService.nonMaximumSuppression(rows, 0.4).length, 3);
    });
  });
}
