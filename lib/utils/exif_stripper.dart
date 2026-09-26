/// Audit M-21: Explizites EXIF-/Metadaten-Scrubbing vor Upload/Versand.
///
/// Bisher war das Strippen nur eine implizite Folge der Re-Encoding-
/// Parameter von image_picker/image_cropper. Ein Plugin-Update oder ein
/// neuer Codepfad hätte GPS-Koordinaten, Geräteinfos und Zeitstempel
/// aus den Original-Bildern an Matches/Bug-Reports durchgereicht.
///
/// Diese Funktion dekodiert das Bild und encodiert es NEU - dabei gehen
/// sämtliche Metadaten verloren. Rückgabe `null` = nicht dekodierbar
/// (fail-closed: Der Aufrufer sendet dann NICHTS statt der Originalbytes).
///
/// FREEZE-FIX (v0.8.1): Decode + Encode eines Vollbild-Fotos im pure-Dart
/// `image`-Package dauert auf dem Handy MEHRERE SEKUNDEN. Bisher lief das
/// synchron im UI-Thread (App "hängt sich auf", Android-ANR beim
/// Chat-Bild-Versand/Profilbild-Pick). Jetzt läuft die komplette
/// Verarbeitung in einem Hintergrund-Isolate.
///
/// SICHERHEIT (Audit 2026-09-26): Die Bytes stammen aus E2E-entschlüsselten
/// Chat-Bildern eines Gegenübers - also aus dem Internet. Vor dem Decode wird
/// deshalb ein Budget geprüft: eine winzige Datei mit riesiger Bildgröße
/// (Decompression-Bomb) würde sonst den kompletten Bitmap-Speicher des
/// Isolates belegen. `image` 4.10.x ist zudem deutlich robuster gegen
/// fehlerhafte EXIF-Sub-IFDs (RangeError → Isolate-Tod).
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Maximale Eingabegröße für das Scrubbing (24 MB).
///
/// Legt die Obergrenze für den dekodierten Speicher fest: RGBA braucht
/// 4 Byte/Pixel, ein 24-MB-JPEG kann auf ~150 MP entpacken (>600 MB).
const int kMaxScrubBytes = 24 * 1024 * 1024;

/// Maximale Kantenlänge des dekodierten Bildes.
const int kMaxScrubDimension = 8192;

/// Maximale Pixelzahl (Punktzahl) des dekodierten Bildes.
///
/// 24 MP reicht für jedes Profilfoto/Chat-Bild und begrenzt den Bitmap auf
/// ~96 MB RGBA. Bewusst großzügig, damit keine legitimen Fotos abgewiesen
/// werden.
const int kMaxScrubPixels = 24 * 1000 * 1000;

Future<Uint8List?> stripImageMetadata(
  Uint8List bytes, {
  int jpegQuality = 88,
}) {
  // Byte-Limit VOR allem anderen: der Aufrufer soll ein klares `null`
  // bekommen und nicht in einen OOM des Isolates laufen.
  if (bytes.isEmpty || bytes.length > kMaxScrubBytes) {
    return Future<Uint8List?>.value();
  }
  return compute(_stripSync, (bytes, jpegQuality));
}

/// Reine (isolate-sichere) Arbeitsfunktion ohne Flutter-Bezug.
Uint8List? _stripSync((Uint8List, int) args) {
  final (bytes, jpegQuality) = args;
  try {
    if (bytes.isEmpty || bytes.length > kMaxScrubBytes) {
      return null;
    }

    final decoder = img.findDecoderForData(bytes);
    if (decoder == null) {
      return null; // Kein bekanntes Bildformat - verweigere Verarbeitung.
    }

    // Bounding-Box VOR dem vollständigen Decode lesen (der Decoder
    // allokiert bei `decode` sofort die Bitmap). Steht kein
    // `startDecode` zur Verfügung, greift der Größen-Check danach.
    final dimensions = _probeDimensions(decoder, bytes);
    if (!_withinBudget(dimensions)) {
      return null;
    }

    final image = decoder.decode(bytes);
    if (image == null) {
      return null; // Dekodierung fehlgeschlagen - verweigere Verarbeitung.
    }

    // Nach dem Decode nochmals prüfen: Manche Formate liefern erst hier
    // die echten Dimensionen.
    if (!_withinBudget((image.width, image.height))) {
      return null;
    }

    // Format beibehalten: JPEG bleibt JPEG (Fotos), alles andere PNG.
    final isJpegSource = bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;

    final encoded = isJpegSource
        ? img.encodeJpg(image, quality: jpegQuality)
        : img.encodePng(image);

    return Uint8List.fromList(encoded);
  } catch (e) {
    // Ein Decoder-Absturz (RangeError bei kaputten EXIF-Sub-IFDs) darf den
    // Isolate nicht töten - fail-closed, es wird nichts Originales gesendet.
    return null;
  }
}

/// Liest (wenn der Decoder es anbietet) die Bildgröße, ohne die Bitmap zu
/// allokieren. Gibt `(0, 0)` zurück, wenn der Decoder das nicht kann.
(int, int) _probeDimensions(img.Decoder decoder, Uint8List bytes) {
  try {
    final start = decoder.startDecode(bytes);
    if (start != null) {
      return (start.width, start.height);
    }
  } catch (_) {
    // Manche Formate werfen hier; dann greift der Check nach dem Decode.
  }
  return (0, 0);
}

bool _withinBudget((int, int) dims) {
  final (width, height) = dims;
  if (width <= 0 || height <= 0) {
    // Unbekannt: nach dem Decode wird nochmals geprüft.
    return true;
  }
  if (width > kMaxScrubDimension || height > kMaxScrubDimension) {
    return false;
  }
  return width * height <= kMaxScrubPixels;
}
