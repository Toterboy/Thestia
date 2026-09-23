import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

/// Ergebnis der lokalen Altersschätzung (On-Device, v0.9.1).
class AgeEstimation {
  const AgeEstimation({
    required this.estimatedAge,
    required this.confidence,
    required this.faceCount,
  });

  /// Geschätztes Alter in Jahren.
  final double estimatedAge;

  /// Konfidenz 0..1 (1.0 bei direkter Jahreszahl-Ausgabe).
  final double confidence;

  /// Anzahl gefundener Gesichter (1 = Idealfall).
  final int faceCount;
}

/// Lokale Altersschätzung für die Video-Verifizierung (v0.9.1).
///
/// Kette: Kamerabild -> Gesichtserkennung (optional) -> Altersmodell.
/// Beide Modelle sind ONNX und laufen vollständig auf dem Gerät - kein
/// Bild verlässt dafür das Gerät.
///
/// Unterstützte Modelle (Details: assets/models/README.md):
///   - Detektor `assets/models/face_detector.onnx` (OPTIONAL):
///     UltraFace RFB/slim-320 (Linzaer, MIT): Input [1,3,240,320]
///     (Höhe 240, Breite 320), Preprocessing (x-127)/128. Outputs
///     `scores` [1,4420,2] + `boxes` [1,4420,4] (bereits dekodiert,
///     normiert) - inkl. NMS hier. Alternativ generisch: einzelner
///     Output [N,>=5] mit (x1,y1,x2,y2,score).
///     Fehlt das Modell, wird `faceCount = -1` (unbekannt) gemeldet und
///     der Aufrufer behandelt den Fall als manuelle Prüfung.
///   - Alter `assets/models/age_estimator.onnx` (PFLICHT für
///     Verfügbarkeit): Input [1,3,224,224], Normierung siehe
///     [ageInputNorm]. Output [1,1] (Jahre direkt), [1,9] (FairFace-
///     Altersgruppen -> Gruppenmitten) oder [1,N] (Erwartungswert
///     über 0..N-1).
///
/// 2-Jahre-Regel (reine Funktion, testbar): Abweichung > 2 Jahre oder
/// nicht genau 1 Gesicht -> manuelle Prüfung durch den Support.
///
/// Robustheit (v0.9.0): Geschätzt wird nicht mehr aus einem einzigen
/// Selfie, sondern aus bis zu 6 Frames (5 über den Videoclip verteilte
/// Frames + 1 Selfie) - der Median ([summarizeFrames]) schluckt
/// Einzelbild-Ausreißer. Weiterhin genau EIN Modell (kein Zweitmodell,
/// kein Fallback-Modell): Scheitert die Schätzung, ist die manuelle
/// Prüfung durch den Support der Fallback.
class AgeEstimationService {
  AgeEstimationService._();

  static final AgeEstimationService instance = AgeEstimationService._();

  static const String _detectorAsset = 'assets/models/face_detector.onnx';
  static const String _ageAsset = 'assets/models/age_estimator.onnx';

  /// Erwartete SHA-256-Hashes der gebündelten Modelle (v0.9.0,
  /// Manipulationsschutz): Stimmt der Hash der Asset-Bytes nicht,
  /// wurde die Modelldatei ausgetauscht – die Schätzung gilt als
  /// nicht vertrauenswürdig und der Fall geht fail-closed in die
  /// manuelle Prüfung. Bei jedem Modellwechsel hier aktualisieren.
  static const String expectedAgeModelSha256 =
      '9c8c47d437cd310538d233f2465f9ed0524cb7fb51882a37f74e8bc22437fdbf';
  static const String expectedDetectorSha256 =
      'faf6740b495e8b9508e6fda11e8c0368bbdde01143e8f0a3e511d0892c4d794e';

  /// Reiner Hash-Vergleich (testbar, v0.9.0).
  static bool isExpectedSha256(String actualHex, String expectedHex) =>
      actualHex.toLowerCase() == expectedHex.toLowerCase();

  /// UltraFace-Eingabe (Breite x Höhe, offizielles detect-Skript).
  static const int _detectWidth = 320;
  static const int _detectHeight = 240;
  static const int _ageSize = 224;

  /// Eingangs-Normierung des Altersmodells: '01' (x/255),
  /// 'imagenet' ((x/255-mean)/std, FairFace-Standard) oder
  /// 'minus11' (x/127.5-1). Vor Bündelung passend setzen.
  static const String ageInputNorm = 'imagenet';

  /// FairFace-Altersgruppen (dchen236, 9 Klassen) -> Gruppenmitten.
  /// Nur für Outputs der Länge 9 verwendet.
  static const List<double> fairfaceAgeMidpoints = [
    1.0,
    6.0,
    14.5,
    24.5,
    34.5,
    44.5,
    54.5,
    64.5,
    75.0,
  ];

  /// Schwellwert für Gesichts-Scores des Detektors (Offiziell 0.7;
  /// 0.5 für Selfie-Nahaufnahmen mit genau einem erwarteten Gesicht).
  static const double faceScoreThreshold = 0.5;

  /// IoU für Non-Maximum Suppression der Detektor-Boxen.
  static const double faceNmsIou = 0.4;

  /// Maximale Abweichung (Jahre), bis zu der die KI-Triage als
  /// unauffällig gilt. Darüber: manuelle Prüfung (Pflicht).
  static const double maxAutoDeviationYears = 2.0;

  /// Mindestzahl gültiger Frames für den Mehrframe-Median (v0.9.0):
  /// Weniger verwertbare Frames -> keine belastbare Schätzung, der
  /// Fall geht in die manuelle Prüfung (sichere Richtung).
  static const int minFramesForMedian = 3;

  /// Zeitstempel (ms) für die Frame-Entnahme aus dem aufgenommenen
  /// Verifizierungsvideo (v0.9.0): über den Clip verteilt, damit
  /// Pose, Mimik und Licht variieren und Einzelbild-Ausreißer
  /// (z. B. 27 statt 18 durch einen ungünstigen Winkel) im Median
  /// untergehen. Kürzere Clips liefern Duplikate - unschädlich.
  static const List<int> verificationFrameTimeMs = [
    500,
    3000,
    5500,
    8000,
    11000,
  ];

  OrtSession? _detector;
  OrtSession? _ageSession;
  List<String> _ageInputNames = const [];
  List<String> _detectInputNames = const [];
  Future<bool>? _initFuture;

  /// Ob die Schätzung verfügbar ist (Altersmodell gebündelt + ladbar).
  bool get isAvailable => _ageSession != null;

  /// Ob zusätzlich ein Gesichtsdetektor bereitsteht.
  bool get hasFaceDetector => _detector != null;

  /// Reine Entscheidungsregel (v0.9.1): true = manuelle Prüfung nötig.
  static bool needsManualReview({
    required double estimatedAge,
    required int statedAge,
    required int faceCount,
  }) {
    if (faceCount != 1) return true;
    return (estimatedAge - statedAge).abs() > maxAutoDeviationYears;
  }

  /// Median über mehrere Frames (reine Funktion, testbar, v0.9.0).
  /// Leere Liste -> null.
  static double? medianAge(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Fasst die Einzelschätzungen mehrerer Videoframes zu einer
  /// Schätzung zusammen (reine Funktion, testbar, v0.9.0): Median
  /// über die Alterswerte. Null, wenn weniger als
  /// [minFramesForMedian] verwertbare Schätzungen vorliegen.
  /// [allSingleFace] ist genau dann true, wenn jeder Frame genau
  /// ein Gesicht enthielt.
  static ({double medianAge, bool allSingleFace})? summarizeFrames(
    List<AgeEstimation> estimations,
  ) {
    if (estimations.length < minFramesForMedian) return null;
    final median = medianAge([for (final e in estimations) e.estimatedAge]);
    if (median == null) return null;
    return (
      medianAge: median,
      allSingleFace: estimations.every((e) => e.faceCount == 1),
    );
  }

  /// Lädt die Modelle lazy (Asset-Bytes -> ONNX-Sessions). Gibt zurück,
  /// ob danach geschätzt werden kann. Fehlt das Altersmodell, bleibt der
  /// Service dauerhaft unverfügbar (Aufrufer: manuelle Queue). Modelle
  /// werden NUR bei einer Verifizierung geladen, sonst nie (Akku/Speicher).
  Future<bool> ensureLoaded() async {
    if (_ageSession != null) return true;
    _initFuture ??= _initInternal();
    return _initFuture!;
  }

  /// Gibt die nativen Modell-Sessions wieder frei (v0.9.1: ca. 82 MB).
  /// Nach jeder Verifizierung aufrufen - der nächste Lauf lädt bei Bedarf
  /// neu.
  void release() {
    _initFuture = null;
    try {
      _detector?.release();
    } catch (_) {}
    try {
      _ageSession?.release();
    } catch (_) {}
    _detector = null;
    _ageSession = null;
    _detectInputNames = const [];
    _ageInputNames = const [];
  }

  Future<bool> _initInternal() async {
    try {
      OrtEnv.instance.init();
    } catch (e) {
      debugPrint('[AgeEstimation] OrtEnv-Init fehlgeschlagen: $e');
      return false;
    }
    // Detektor ist optional (Best-Effort).
    try {
      final data = await rootBundle.load(_detectorAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (!isExpectedSha256(
        sha256.convert(bytes).toString(),
        expectedDetectorSha256,
      )) {
        debugPrint(
          '[AgeEstimation] Detektor-Hash weicht ab (Modell '
          'ausgetauscht?) - Detektor deaktiviert, manuelle Prüfung.',
        );
        _detector = null;
      } else {
        final session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
        _detector = session;
        _detectInputNames = session.inputNames;
      }
    } catch (e) {
      debugPrint(
        '[AgeEstimation] Kein Gesichtsdetektor gebündelt '
        '(manueller Fallback bei faceCount): $e',
      );
      _detector = null;
    }
    // Altersmodell ist Pflicht.
    try {
      final data = await rootBundle.load(_ageAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (!isExpectedSha256(
        sha256.convert(bytes).toString(),
        expectedAgeModelSha256,
      )) {
        debugPrint(
          '[AgeEstimation] Altersmodell-Hash weicht ab (Modell '
          'ausgetauscht?) - Schätzung deaktiviert, manuelle Prüfung.',
        );
        _ageSession = null;
        return false;
      }
      final session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
      _ageSession = session;
      _ageInputNames = session.inputNames;
      debugPrint(
        '[AgeEstimation] Altersmodell geladen. '
        'Detektor: ${hasFaceDetector ? "ja" : "nein"}',
      );
      return true;
    } catch (e) {
      debugPrint(
        '[AgeEstimation] Altersmodell fehlt/deaktiviert '
        '(manuelle Queue): $e',
      );
      _ageSession = null;
      return false;
    }
  }

  /// Schätzt das Alter aus JPEG/PNG-Bytes. Liefert null, wenn keine
  /// Schätzung möglich ist (kein Modell, Dekodierfehler) - der Aufrufer
  /// reiht dann in die manuelle Prüfung ein.
  ///
  /// Isolate-Disziplin: Über `compute` laufen nur primitive Daten
  /// (Bytes, Ints, Listen) - keine Bild-Objekte (nicht übertragbar).
  /// Die ONNX-Sessions laufen auf dem aufrufenden Thread.
  Future<AgeEstimation?> estimateAge(Uint8List bytes) async {
    if (!await ensureLoaded()) return null;
    final ageSession = _ageSession;
    if (ageSession == null) return null;
    try {
      // 1) Dekodieren + auf max. 640 px verkleinern (Isolate, kein Jank).
      //    Rückgabe: [Breite, Höhe, RGB-Bytes].
      final small = await compute(_decodeDownscaleSync, bytes);
      if (small == null) return null;
      final baseW = small[0] as int;
      final baseH = small[1] as int;
      final rgb = small[2] as Uint8List;

      // 2) Gesichter zählen (falls Detektor vorhanden). UltraFace:
      //    fest 320x240, (x-127)/128. Boxen sind normiert.
      var faceCount = -1;
      var crop = _centerSquare(baseW, baseH);
      final detector = _detector;
      if (detector != null) {
        final detTensor = _tensorFromRgbUltraFace(rgb, baseW, baseH);
        final boxes = _detectFaces(detector, detTensor);
        faceCount = boxes.length;
        if (boxes.isNotEmpty) {
          // Größte Box (normiert -> Originalkoordinaten).
          boxes.sort((a, b) => b.$5.compareTo(a.$5));
          final b = boxes.first;
          crop = _clampCrop(
            (b.$1 * baseW).toInt(),
            (b.$2 * baseH).toInt(),
            (b.$3 * baseW).toInt(),
            (b.$4 * baseH).toInt(),
            baseW,
            baseH,
          );
        }
      }

      // 3) Crop aufbereiten (Isolate, Norm siehe [ageInputNorm]).
      final tensor = await compute(_cropResizeFromRgbSync, {
        'rgb': rgb,
        'w': baseW,
        'h': baseH,
        'crop': crop,
        'size': _ageSize,
        'norm': ageInputNorm,
      });
      final inputName = _ageInputNames.isNotEmpty
          ? _ageInputNames.first
          : 'input';
      final inputOrt = OrtValueTensor.createTensorWithDataList(tensor, [
        1,
        3,
        _ageSize,
        _ageSize,
      ]);
      final outputs = ageSession.run(OrtRunOptions(), {inputName: inputOrt});
      // Alters-Kopf anhand der Form wählen (verifiziert: FairFace liefert
      // race[?,7] + gender[?,2] + age[?,9] - die Reihenfolge ist nicht
      // garantiert, deshalb NICHT outputs.first nehmen).
      List<double>? nums;
      List<double>? fallback;
      for (final o in outputs) {
        final v = o?.value;
        if (v is! List || v.isEmpty) continue;
        var row = v;
        if (row.first is List) row = row.first as List;
        if (row.isEmpty || row.first is! num) continue;
        final parsed = row.map((e) => (e as num).toDouble()).toList();
        if (parsed.length == 1 ||
            parsed.length == fairfaceAgeMidpoints.length) {
          nums = parsed;
          break;
        }
        fallback ??= parsed;
      }
      nums ??= fallback;
      if (nums == null || nums.isEmpty) return null;

      final parsed = parseAgeOutput(nums);
      if (parsed == null) return null;
      final years = parsed.$1;
      final confidence = parsed.$2;
      if (!years.isFinite || years < 0 || years > 120) return null;
      return AgeEstimation(
        estimatedAge: years,
        confidence: confidence.clamp(0.0, 1.0),
        faceCount: faceCount,
      );
    } catch (e) {
      debugPrint('[AgeEstimation] Inferenz fehlgeschlagen: $e');
      return null;
    }
  }

  /// Führt den Detektor aus. Versteht zwei Formate:
  ///   a) UltraFace (Linzaer): Outputs `scores` [1,4420,2] + `boxes`
  ///      [1,4420,4] (bereits dekodiert, normiert) + NMS.
  ///   b) Generisch: einzelner Output [N,>=5] mit (x1,y1,x2,y2,score).
  /// Rückgabe: (x1,y1,x2,y2,Fläche) normiert, nur Scores
  /// >= [faceScoreThreshold], NMS-gefiltert.
  List<(double, double, double, double, double)> _detectFaces(
    OrtSession detector,
    Float32List tensor,
  ) {
    final inputName = _detectInputNames.isNotEmpty
        ? _detectInputNames.first
        : 'input';
    final inputOrt = OrtValueTensor.createTensorWithDataList(tensor, [
      1,
      3,
      _detectHeight,
      _detectWidth,
    ]);
    final outputs = detector.run(OrtRunOptions(), {inputName: inputOrt});
    final rows = <List<double>>[];
    if (outputs.length >= 2) {
      // UltraFace-Paar anhand der letzten Dimension erkennen.
      List<dynamic>? scores;
      List<dynamic>? boxes;
      for (final o in outputs) {
        final v = o?.value;
        if (v is! List || v.isEmpty) continue;
        var row = v;
        if (row.first is List) row = row.first as List;
        if (row.isEmpty || row.first is! List) continue;
        final cols = (row.first as List).length;
        if (cols == 2) {
          scores = row.cast<List<dynamic>>();
        } else if (cols == 4) {
          boxes = row.cast<List<dynamic>>();
        }
      }
      if (scores != null && boxes != null) {
        final n = math.min(scores.length, boxes.length);
        for (var i = 0; i < n; i++) {
          final s = (scores[i][1] as num).toDouble();
          if (s < faceScoreThreshold) continue;
          final b = (boxes[i] as List)
              .map((e) => (e as num).toDouble())
              .toList();
          rows.add([b[0], b[1], b[2], b[3], s]);
        }
        return nonMaximumSuppression(rows, faceNmsIou);
      }
    }
    // Generischer Fallback: [N,>=5].
    for (final o in outputs) {
      final v = o?.value;
      if (v is! List) continue;
      var list = v;
      if (list.isNotEmpty && list.first is List) {
        // Batch-Dimension entfernen, falls vorhanden.
        final maybeBatch = list.first as List;
        if (maybeBatch.isNotEmpty && maybeBatch.first is! num) {
          list = maybeBatch;
        }
      }
      for (final row in list) {
        if (row is! List || row.length < 5) continue;
        final nums = row.map((e) => (e as num).toDouble()).toList();
        if (nums[4] < faceScoreThreshold) continue;
        rows.add([nums[0], nums[1], nums[2], nums[3], nums[4]]);
      }
    }
    return nonMaximumSuppression(rows, faceNmsIou);
  }

  /// Non-Maximum Suppression (reine Funktion, testbar).
  /// [rows]: [x1,y1,x2,y2,score], Koordinaten beliebig skaliert.
  static List<(double, double, double, double, double)> nonMaximumSuppression(
    List<List<double>> rows,
    double iouThreshold,
  ) {
    final indexed = <int>[for (var i = 0; i < rows.length; i++) i]
      ..sort((a, b) => rows[b][4].compareTo(rows[a][4]));
    final kept = <int>[];
    final suppressed = List<bool>.filled(rows.length, false);
    for (final i in indexed) {
      if (suppressed[i]) continue;
      kept.add(i);
      for (final j in indexed) {
        if (j == i || suppressed[j]) continue;
        if (_iou(rows[i], rows[j]) > iouThreshold) suppressed[j] = true;
      }
    }
    return [
      for (final i in kept)
        (
          rows[i][0].clamp(0.0, 1.0),
          rows[i][1].clamp(0.0, 1.0),
          rows[i][2].clamp(0.0, 1.0),
          rows[i][3].clamp(0.0, 1.0),
          (rows[i][2] - rows[i][0]) * (rows[i][3] - rows[i][1]),
        ),
    ];
  }

  static double _iou(List<double> a, List<double> b) {
    final x1 = math.max(a[0], b[0]);
    final y1 = math.max(a[1], b[1]);
    final x2 = math.min(a[2], b[2]);
    final y2 = math.min(a[3], b[3]);
    final inter = math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
    if (inter <= 0) return 0.0;
    final areaA = math.max(0.0, a[2] - a[0]) * math.max(0.0, a[3] - a[1]);
    final areaB = math.max(0.0, b[2] - b[0]) * math.max(0.0, b[3] - b[1]);
    final union = areaA + areaB - inter;
    return union <= 0 ? 0.0 : inter / union;
  }

  /// Parst Alters-Outputs (reine Funktion, testbar):
  /// [1,1] -> Jahre direkt; [1,9] -> FairFace-Gruppenmitten;
  /// [1,N] -> Erwartungswert über 0..N-1. Rückgabe (Jahre, Konfidenz).
  static (double, double)? parseAgeOutput(List<double> nums) {
    if (nums.isEmpty) return null;
    if (nums.length == 1) {
      return (nums.first, 1.0);
    }
    final maxV = nums.reduce(math.max);
    final exps = nums.map((v) => math.exp(v - maxV)).toList();
    final sum = exps.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return null;
    final useFairface = nums.length == fairfaceAgeMidpoints.length;
    var expected = 0.0;
    var best = 0.0;
    for (var i = 0; i < exps.length; i++) {
      final p = exps[i] / sum;
      expected += (useFairface ? fairfaceAgeMidpoints[i] : i.toDouble()) * p;
      if (p > best) best = p;
    }
    return (expected, best.clamp(0.0, 1.0));
  }

  /// Mittiges Quadrat (x1,y1,x2,y2) als Fallback-Crop.
  List<int> _centerSquare(int w, int h) {
    final side = w < h ? w : h;
    final x = (w - side) ~/ 2;
    final y = (h - side) ~/ 2;
    return [x, y, x + side, y + side];
  }

  /// Crop auf Bildgrenzen klemmen (mind. 1 px groß).
  List<int> _clampCrop(int x1, int y1, int x2, int y2, int w, int h) {
    final a = x1.clamp(0, w - 1);
    final b = y1.clamp(0, h - 1);
    final c = x2.clamp(a + 1, w);
    final d = y2.clamp(b + 1, h);
    return [a, b, c, d];
  }

  /// RGB-Bytes -> UltraFace-Tensor [1,3,240,320] mit (x-127)/128
  /// (offizielles detect-Skript, Linzaer). Hauptthread, klein und schnell.
  Float32List _tensorFromRgbUltraFace(Uint8List rgb, int srcW, int srcH) {
    const dstW = _detectWidth;
    const dstH = _detectHeight;
    final planeSize = dstW * dstH;
    final tensor = Float32List(3 * planeSize);
    var r = 0;
    var g = planeSize;
    var b = planeSize * 2;
    for (var y = 0; y < dstH; y++) {
      final sy = (y * srcH / dstH).floor().clamp(0, srcH - 1);
      for (var x = 0; x < dstW; x++) {
        final sx = (x * srcW / dstW).floor().clamp(0, srcW - 1);
        final o = (sy * srcW + sx) * 3;
        tensor[r++] = (rgb[o] - 127) / 128.0;
        tensor[g++] = (rgb[o + 1] - 127) / 128.0;
        tensor[b++] = (rgb[o + 2] - 127) / 128.0;
      }
    }
    return tensor;
  }

  /// Dekodiert + verkleinert (längste Seite max. 640) im Isolate.
  /// Rückgabe [Breite, Höhe, RGB-Bytes] oder null.
  static List<dynamic>? _decodeDownscaleSync(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // EXIF-Orientation in die Pixel-Daten baken (Fix "KI-Triage immer
    // manuell"): Frontkamera-Selfies tragen meist eine EXIF-Rotation.
    // Ohne bakeOrientation wird das Bild SEITLICH dekodiert, der
    // Gesichts-Detektor findet kein aufrechtes Gesicht (faceCount 0)
    // und die Automatik fiel dadurch ständig in die manuelle Prüfung.
    final oriented = img.bakeOrientation(decoded);
    const maxSide = 640;
    final scale = math.min(
      1.0,
      maxSide / math.max(oriented.width, oriented.height),
    );
    final w = math.max(1, (oriented.width * scale).round());
    final h = math.max(1, (oriented.height * scale).round());
    final resized = img.copyResize(
      oriented,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
    final rgb = Uint8List(w * h * 3);
    var o = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = resized.getPixel(x, y);
        rgb[o++] = p.r.toInt().clamp(0, 255);
        rgb[o++] = p.g.toInt().clamp(0, 255);
        rgb[o++] = p.b.toInt().clamp(0, 255);
      }
    }
    return [w, h, rgb];
  }
}

/// Crop + Resize + Normalisierung im Isolate.
/// Params: rgb, w, h, crop [x1,y1,x2,y2], size, norm
/// ('01' | 'imagenet' | 'minus11') -> NCHW-Float32.
Float32List _cropResizeFromRgbSync(Map<String, dynamic> params) {
  final rgb = params['rgb'] as Uint8List;
  final w = params['w'] as int;
  final h = params['h'] as int;
  final crop = (params['crop'] as List).map((e) => (e as num).toInt()).toList();
  final size = params['size'] as int;
  final norm = params['norm'] as String? ?? '01';
  final planeSize = size * size;
  final tensor = Float32List(3 * planeSize);
  var r = 0;
  var g = planeSize;
  var b = planeSize * 2;
  final cw = (crop[2] - crop[0]).clamp(1, w);
  final ch = (crop[3] - crop[1]).clamp(1, h);
  for (var y = 0; y < size; y++) {
    final sy = (crop[1] + y * ch / size).floor().clamp(0, h - 1);
    for (var x = 0; x < size; x++) {
      final sx = (crop[0] + x * cw / size).floor().clamp(0, w - 1);
      final o = (sy * w + sx) * 3;
      tensor[r++] = _normChannel(rgb[o].toDouble(), 0, norm);
      tensor[g++] = _normChannel(rgb[o + 1].toDouble(), 1, norm);
      tensor[b++] = _normChannel(rgb[o + 2].toDouble(), 2, norm);
    }
  }
  return tensor;
}

/// Kanal-Normierung ('01' | 'imagenet' | 'minus11').
double _normChannel(double v, int channel, String norm) {
  if (norm == 'imagenet') {
    const means = [0.485, 0.456, 0.406];
    const stds = [0.229, 0.224, 0.225];
    return (v / 255.0 - means[channel]) / stds[channel];
  }
  if (norm == 'minus11') return v / 127.5 - 1.0;
  return v / 255.0;
}

/// Provider für den [AgeEstimationService] (Singleton-Instanz).
final ageEstimationServiceProvider = Provider<AgeEstimationService>((ref) {
  return AgeEstimationService.instance;
});
