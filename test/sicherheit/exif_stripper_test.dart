// Das Entfernen der Bild-Metadaten (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte fuer
// lib/utils/exif_stripper.dart 0 %.
//
// WARUM DAS WICHTIG IST: Der Aufrufer verschickt NUR das Ergebnis - die
// Originalbytes gehen nicht raus. Das ist die Zusage, dass keine
// GPS-Koordinaten, Geräteinfos oder Zeitstempel aus dem Foto beim
// anderen landen. Ein Fehler hier waere ein Datenleck.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Metadaten verschwinden (an einem Bild mit eingebautem
//     Metadatenblock nachgewiesen),
//   * was kein Bild ist, wird ABGELEHNT (fail-closed: es werden nicht
//     die Originalbytes geschickt),
//   * leere Bytes werden abgelehnt,
//   * zu grosse Eingaben werden abgelehnt (Decompression-Bomb),
//   * ein JPEG bleibt ein JPEG, ein PNG bleibt ein PNG.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:thestia/utils/exif_stripper.dart';

/// Das Kennzeichen, das im Metadatenblock steckt.
const String _kennzeichen = 'SecretGPS';

/// Ein kleines PNG (8x8, rot).
Uint8List pngBytes() {
  final bild = img.Image(width: 8, height: 8);
  img.fill(bild, color: img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodePng(bild));
}

/// Ein kleines JPEG (8x8).
Uint8List jpegBytes() {
  final bild = img.Image(width: 8, height: 8);
  img.fill(bild, color: img.ColorRgb8(0, 0, 255));
  return Uint8List.fromList(img.encodeJpg(bild));
}

/// Haengt einen Metadatenblock (JPEG-Kommentar) in ein JPEG.
///
/// So baut der Test ein Bild, in dem wirklich Metadaten stehen - ohne
/// eine Datei aus dem Netz zu brauchen.
Uint8List jpegMitMetadaten() {
  final jpeg = jpegBytes();
  final text = _kennzeichen.codeUnits;
  final block = <int>[
    0xFF, 0xFE, // COM (Kommentar)
    (text.length + 2) >> 8,
    (text.length + 2) & 0xFF, // Laenge
    ...text,
  ];
  // Direkt nach dem SOI-Marker (FFE8) einhaengen.
  return Uint8List.fromList([
    ...jpeg.sublist(0, 2),
    ...block,
    ...jpeg.sublist(2),
  ]);
}

/// Steht der Text in den Bytes?
bool enthaelt(Uint8List bytes, String text) {
  final muster = text.codeUnits;
  for (var i = 0; i + muster.length <= bytes.length; i++) {
    var passt = true;
    for (var j = 0; j < muster.length; j++) {
      if (bytes[i + j] != muster[j]) {
        passt = false;
        break;
      }
    }
    if (passt) return true;
  }
  return false;
}

void main() {
  group('Das Entfernen der Bild-Metadaten', () {
    test('ein PNG kommt als Bild zurueck', () async {
      final ergebnis = await stripImageMetadata(pngBytes());

      expect(ergebnis, isNotNull);
      final dekodiert = img.decodeImage(ergebnis!);
      expect(dekodiert, isNotNull);
      expect(dekodiert!.width, 8);
      expect(dekodiert.height, 8);
    });

    test('ein JPEG bleibt ein JPEG', () async {
      final ergebnis = await stripImageMetadata(jpegBytes());

      expect(ergebnis, isNotNull);
      // JPEG-Magic: FFD8 am Anfang.
      expect(ergebnis![0], 0xFF);
      expect(ergebnis[1], 0xD8);
      // Und es ist wieder ein Bild.
      expect(img.decodeImage(ergebnis), isNotNull);
    });

    test('die Metadaten verschwinden', () async {
      final eingabe = jpegMitMetadaten();
      // Der Ausgangstest traegt die Metadaten wirklich.
      expect(enthaelt(eingabe, _kennzeichen), isTrue);

      final ergebnis = await stripImageMetadata(eingabe);

      expect(ergebnis, isNotNull);
      expect(
        enthaelt(ergebnis!, _kennzeichen),
        isFalse,
        reason:
            'Das Ergebnis ist neu kodiert - die Metadaten des Originals '
            'duerfen nicht mitgeschickt werden.',
      );
      // Und es ist immer noch ein Bild.
      expect(img.decodeImage(ergebnis), isNotNull);
    });

    test('was kein Bild ist, wird abgelehnt', () async {
      // KEIN Original zurueckgeben: sonst gingen die Rohbytes (mit
      // allem, was drin steckt) an den Empfaenger.
      final ergebnis = await stripImageMetadata(
        Uint8List.fromList(List<int>.filled(500, 7)),
      );

      expect(ergebnis, isNull);
    });

    test('leere Bytes werden abgelehnt', () async {
      expect(await stripImageMetadata(Uint8List(0)), isNull);
    });

    test('zu grosse Eingaben werden abgelehnt', () async {
      // Obergrenze + 1 Byte: muss ABGELEHNT werden, ohne dass der
      // Decoder ueberhaupt anfaengt (eine winzige Datei mit riesiger
      // Bildgroesse waere eine Speicherbombe).
      final zuGross = Uint8List(kMaxScrubBytes + 1);
      expect(await stripImageMetadata(zuGross), isNull);
    });

    test('die Grenzen sind so, wie sie in der Zusage stehen', () {
      // 24 MB Eingabe, 8192 px Kante, 24 MP Pixel - an diesen Werten
      // haengt das Versprechen "keine Metadaten, keine Speicherbombe".
      expect(kMaxScrubBytes, 24 * 1024 * 1024);
      expect(kMaxScrubDimension, 8192);
      expect(kMaxScrubPixels, 24 * 1000 * 1000);
    });
  });
}
