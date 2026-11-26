// Die reinen Bild-Helfer der Altersprüfung.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/services/transit/age_estimation_service.dart 193 offene Zeilen -
// darunter die reinen Helfer (Crop, Tensor, Größe, Überschneidung).
// Die Altersprüfung ist die einzige Stelle der App, die ein Gesicht
// bewertet: ein Fehler in einem dieser Helder fällt auf dem Gerät
// nicht auf, sondern fällt nur durch - die Prüfung landet dann
// grundlos bei der manuellen Kontrolle.
//
// DIE LÖSUNG: Die Helfer sind jetzt öffentlich und mit
// `@visibleForTesting` markiert (wie die Box-Namen im Chat-Dienst).
// Die App benutzt sie trotzdem nur an dieser Stelle.
//
// WAS HIER GEPRÜFT WIRD:
//   * das mittige Quadrat (der Crop, wenn kein Gesicht gefunden wird),
//   * das Klemmen des Crops auf die Bildgrenzen (nie 0 Pixel, nie
//     außerhalb),
//   * der UltraFace-Tensor: Größe, Normierung ((x-127)/128) und die
//     Reihenfolge der Ebenen (R, G, B),
//   * das Verkleinern: höchstens 640 Pixel, das Seitenverhältnis bleibt,
//   * der Alters-Tensor: NCHW, die Normierungen und der Crop-Ausschnitt,
//   * die Überschneidungsfläche (NMS des Detektors).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:thestia/services/transit/age_estimation_service.dart';

void main() {
  /// Ein einfarbiges Bild (rot) in der angegebenen Größe.
  Uint8List bildBytes(int breite, int hoehe) {
    final bild = img.Image(width: breite, height: hoehe);
    img.fill(bild, color: img.ColorRgb8(255, 0, 0));
    return Uint8List.fromList(img.encodePng(bild));
  }

  /// Ein RGB-Puffer (rote Pixel).
  Uint8List rgbPuffer(int breite, int hoehe) {
    final puffer = Uint8List(breite * hoehe * 3);
    for (var i = 0; i < breite * hoehe; i++) {
      puffer[i * 3] = 255;
      puffer[i * 3 + 1] = 0;
      puffer[i * 3 + 2] = 0;
    }
    return puffer;
  }

  group('Das mittige Quadrat', () {
    test('es ist so gross wie die kleinere Seite', () {
      final quadrat = AgeEstimationService.centerSquare(100, 60);

      expect(quadrat, [20, 0, 80, 60]);
      expect(quadrat[2] - quadrat[0], 60);
      expect(quadrat[3] - quadrat[1], 60);
    });

    test('bei einem quadratischen Bild liegt es ueberall', () {
      expect(AgeEstimationService.centerSquare(80, 80), [0, 0, 80, 80]);
    });

    test('es bleibt im Bild', () {
      final quadrat = AgeEstimationService.centerSquare(37, 91);

      expect(quadrat[0], greaterThanOrEqualTo(0));
      expect(quadrat[1], greaterThanOrEqualTo(0));
      expect(quadrat[2], lessThanOrEqualTo(37));
      expect(quadrat[3], lessThanOrEqualTo(91));
    });
  });

  group('Das Klemmen des Crops', () {
    test('ein Crop ausserhalb wird auf die Bildgrenze geholt', () {
      final crop = AgeEstimationService.clampCrop(-20, -5, 500, 400, 100, 80);

      expect(crop[0], 0);
      expect(crop[1], 0);
      expect(crop[2], 100);
      expect(crop[3], 80);
    });

    test('der Crop ist nie leer', () {
      final crop = AgeEstimationService.clampCrop(50, 50, 50, 50, 100, 80);

      expect(crop[2] - crop[0], greaterThanOrEqualTo(1));
      expect(crop[3] - crop[1], greaterThanOrEqualTo(1));
      expect(
        crop[2],
        greaterThan(crop[0]),
        reason:
            'Ein leerer Crop wuerde das Modell mit nichts fuettern - der '
            'Fehler faellt auf dem Geraet nicht auf, sondern nur als '
            '"manuelle Pruefung".',
      );
      expect(crop[3], greaterThan(crop[1]));
    });

    test('ein Crop innerhalb bleibt unveraendert', () {
      expect(AgeEstimationService.clampCrop(10, 20, 60, 70, 100, 80), [
        10,
        20,
        60,
        70,
      ]);
    });
  });

  group('Der UltraFace-Tensor', () {
    test('er hat die erwartete Groesse und Reihenfolge', () {
      final tensor = AgeEstimationService.tensorFromRgbUltraFace(
        rgbPuffer(4, 4),
        4,
        4,
      );

      // [1,3,240,320] -> 3 Ebenen mit je 240*320 Werten.
      expect(tensor.length, 3 * 240 * 320);
      // Das Bild ist rot: die erste Ebene ist rot, die beiden anderen
      // sind schwarz. Verwechselt man die Ebenen, findet der Detektor
      // kein Gesicht.
      expect(tensor[0], closeTo((255 - 127) / 128.0, 0.0001));
      expect(tensor[240 * 320], closeTo((0 - 127) / 128.0, 0.0001));
      expect(tensor[2 * 240 * 320], closeTo((0 - 127) / 128.0, 0.0001));
    });

    test('die Werte liegen zwischen -1 und 1', () {
      final tensor = AgeEstimationService.tensorFromRgbUltraFace(
        rgbPuffer(8, 8),
        8,
        8,
      );

      for (final wert in tensor) {
        expect(wert, greaterThanOrEqualTo(-1.0001));
        expect(wert, lessThanOrEqualTo(1.0001));
      }
    });
  });

  group('Das Verkleinern', () {
    test('ein Bild bleibt in der Groesse (nichts zu tun)', () {
      final klein = AgeEstimationService.decodeDownscaleSync(
        bildBytes(100, 50),
      );

      expect(klein, isNotNull);
      expect(klein![0], 100);
      expect(klein[1], 50);
    });

    test('die laengste Seite wird auf 640 begrenzt', () {
      final klein = AgeEstimationService.decodeDownscaleSync(
        bildBytes(1280, 720),
      );

      expect(klein, isNotNull);
      expect(klein![0], lessThanOrEqualTo(640));
      expect(klein[1], lessThanOrEqualTo(640));
      // Das Seitenverhältnis bleibt erhalten (1280x720 -> 640x360).
      expect(klein[0], 640);
      expect(klein[1], 360);
    });

    test('die RGB-Bytes passen zur Bildgroesse', () {
      final klein = AgeEstimationService.decodeDownscaleSync(bildBytes(10, 20));

      expect(klein, isNotNull);
      final rgb = klein![2] as Uint8List;
      expect(rgb.length, (klein[0] as int) * (klein[1] as int) * 3);
      // Das Bild ist rot.
      expect(rgb[0], 255);
      expect(rgb[1], 0);
    });

    test('kein Bild ist null (kein Absturz)', () {
      expect(
        AgeEstimationService.decodeDownscaleSync(
          Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
        isNull,
        reason:
            'Kaputte Bytes sind kein Grund fuer einen Absturz - der Dienst '
            'meldet dann "keine Pruefung" und der Fall geht an den Support.',
      );
    });
  });

  group('Der Alters-Tensor', () {
    test('er hat die erwartete Groesse (NCHW)', () {
      final tensor = cropResizeFromRgbSync(<String, dynamic>{
        'rgb': rgbPuffer(8, 8),
        'w': 8,
        'h': 8,
        'crop': <int>[0, 0, 8, 8],
        'size': 4,
        'norm': '01',
      });

      expect(tensor.length, 3 * 4 * 4);
      // Rot -> 1.0 bei der Normierung 0..1.
      expect(tensor[0], closeTo(1.0, 0.0001));
      expect(tensor[16], closeTo(0.0, 0.0001));
      expect(tensor[32], closeTo(0.0, 0.0001));
    });

    test('die Normierung minus11 liefert -1 bis 1', () {
      final tensor = cropResizeFromRgbSync(<String, dynamic>{
        'rgb': rgbPuffer(4, 4),
        'w': 4,
        'h': 4,
        'crop': <int>[0, 0, 4, 4],
        'size': 2,
        'norm': 'minus11',
      });

      expect(tensor[0], closeTo(255 / 127.5 - 1.0, 0.0001));
    });

    test('die Normierung imagenet nutzt Mittelwert und Streuung', () {
      final tensor = cropResizeFromRgbSync(<String, dynamic>{
        'rgb': rgbPuffer(4, 4),
        'w': 4,
        'h': 4,
        'crop': <int>[0, 0, 4, 4],
        'size': 2,
        'norm': 'imagenet',
      });

      expect(tensor[0], closeTo((1.0 - 0.485) / 0.229, 0.0001));
    });

    test('nur der Crop wird uebernommen', () {
      // Der Crop nimmt die linke Hälfte - dort ist das Bild rot.
      final tensor = cropResizeFromRgbSync(<String, dynamic>{
        'rgb': rgbPuffer(4, 4),
        'w': 4,
        'h': 4,
        'crop': <int>[0, 0, 2, 4],
        'size': 2,
        'norm': '01',
      });

      expect(tensor[0], closeTo(1.0, 0.0001));
    });
  });

  group('Die Ueberschneidungsflaeche', () {
    test('zwei gleiche Rechtecke ueberlappen vollstaendig', () {
      expect(
        AgeEstimationService.iou(
          <double>[0, 0, 10, 10],
          <double>[0, 0, 10, 10],
        ),
        closeTo(1.0, 0.0001),
      );
    });

    test('zwei getrennte Rechtecke ueberlappen sich nicht', () {
      expect(
        AgeEstimationService.iou(
          <double>[0, 0, 10, 10],
          <double>[20, 20, 30, 30],
        ),
        0.0,
      );
    });

    test('die Haelfte zaehlt halb', () {
      // Zwei 10x10-Rechtecke, die sich auf 5 Pixel Breite überlappen:
      // die Schnittfläche ist 50, die Vereinigung 150 -> 1/3.
      expect(
        AgeEstimationService.iou(
          <double>[0, 0, 10, 10],
          <double>[5, 0, 15, 10],
        ),
        closeTo(50 / 150, 0.0001),
      );
    });
  });
}
