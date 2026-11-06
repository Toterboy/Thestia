import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

/// Ergebnis der lokalen Bild-Sicherheitsprüfung (On-Device, v0.8.0).
class ImageSafetyResult {
  const ImageSafetyResult({
    required this.nsfl,
    required this.nsfw,
    required this.sfw,
  });

  /// Wahrscheinlichkeit für Gore/gewaltsame Inhalte (0..1).
  final double nsfl;

  /// Wahrscheinlichkeit für sexuelle Inhalte (0..1).
  final double nsfw;

  /// Wahrscheinlichkeit für unbedenkliche Inhalte (0..1).
  final double sfw;

  /// Schwellwert aus dem Meldedialog: Ab 0.65 gilt ein Bild als
  /// potenziell anstößig (NSFW oder NSFL).
  static const double flagThreshold = 0.65;

  bool get isFlagged => nsfw > flagThreshold || nsfl > flagThreshold;

  /// Wahrscheinlichkeit der kritischsten Klasse (max von NSFW/NSFL).
  double get criticalScore => nsfw > nsfl ? nsfw : nsfl;

  /// Klassenlabel mit dem höchsten Wert.
  String get topLabel {
    if (nsfw >= nsfl && nsfw >= sfw) return 'NSFW';
    if (nsfl >= nsfw && nsfl >= sfw) return 'NSFL';
    return 'SFW';
  }
}

/// Lokale On-Device-Bildmoderation (v0.8.0) mit dem Modell
/// `image-safety-classifier-xs.onnx` (OwenElliott/image-safety-classifier-xs,
/// Hugging Face) via ONNX Runtime.
///
/// ARCHITEKTUR-REGELN:
///  - Die Analyse läuft AUSSCHLIESSLICH nach einer manuellen Bild-Meldung
///    (Human-in-the-Loop). Niemals beim Senden oder Empfangen - das würde
///    die Ende-zu-Ende-Verschlüsselung untergraben.
///  - Das Bild verlässt bei der lokalen Prüfung das Gerät nicht. Erst die
///    aktive Bestätigung des Meldenden stößt die Übertragung an.
///  - Kein automatisches Sperren: Der Score dient ausschließlich der
///    Transparenz für den Meldenden und als Hinweis für das manuelle
///    Moderations-Team.
///
/// LEBENSZYKLUS: `OrtEnv` und `OrtSession` werden beim ersten Bedarf
/// (Lazy Loading) einmalig erzeugt und anschließend wiederverwendet.
/// Das Modell wird als Buffer direkt an ONNX Runtime übergeben
/// ([OrtSession.fromBuffer]) - keine temporaere Datei nötig.
class ImageSafetyService {
  ImageSafetyService._();

  static final ImageSafetyService instance = ImageSafetyService._();

  static const String _assetPath =
      'assets/models/image-safety-classifier-xs.onnx';
  static const int _inputSize = 224;

  OrtSession? _session;
  List<String> _inputNames = const [];
  Future<bool>? _initFuture;

  /// Ist die lokale Prüfung verfügbar (Modell gebündelt und Session
  /// erfolgreich geladen)?
  bool get isAvailable => _session != null;

  /// Lädt das Modell lazy (Asset-Bytes -> ONNX-Session) und gibt zurück,
  /// ob danach klassifiziert werden kann. Mehrfache Aufrufe teilen sich
  /// denselben Ladevorgang.
  Future<bool> ensureSession() async {
    if (_session != null) return true;
    _initFuture ??= _initInternal();
    return _initFuture!;
  }

  Future<bool> _initInternal() async {
    try {
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      OrtEnv.instance.init();
      final session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
      _session = session;
      _inputNames = session.inputNames;
      debugPrint(
        '[ImageSafety] Modell geladen. Inputs: $_inputNames, '
        'Outputs: ${session.outputNames}',
      );
      return true;
    } catch (e) {
      debugPrint(
        '[ImageSafety] Modell konnte nicht geladen werden '
        '(lokale Prüfung deaktiviert): $e',
      );
      _session = null;
      return false;
    }
  }

  /// Klassifiziert Bildbytes LOKAL. Liefert `null`, wenn die lokale
  /// Prüfung nicht verfügbar ist (Modell fehlt/Fehler) - der Aufrufer
  /// fällt dann auf den serverseitigen Fallback zurück.
  ///
  /// Vorverarbeitung: Resize auf 224x224 RGB, NCHW-Float32-Tensor,
  /// Pixelwerte normalisiert auf 0..1.
  Future<ImageSafetyResult?> classifyImage(Uint8List bytes) async {
    if (!await ensureSession()) return null;
    final session = _session;
    if (session == null) return null;
    try {
      // FREEZE-FIX (v0.8.1): Decode + Resize eines 2048px-Fotos im
      // pure-Dart image-Package dauert Sekunden - im Hintergrund-Isolate
      // statt auf dem UI-Thread.
      final tensor = await compute(_preprocessSync, bytes);
      final inputName = _inputNames.isNotEmpty ? _inputNames.first : 'input';
      final inputOrt = OrtValueTensor.createTensorWithDataList(tensor, [
        1,
        3,
        _inputSize,
        _inputSize,
      ]);

      final outputs = session.run(OrtRunOptions(), {inputName: inputOrt});

      final first = outputs.isNotEmpty ? outputs.first : null;
      if (first == null) return null;
      final value = first.value;
      if (value is! List) return null;

      // Batch-Dimension entfernen: Der Output-Tensor ist [1, N]
      // ([[p0, p1, ...]]) - wir brauchen die innere Liste.
      var rows = value;
      if (rows.isNotEmpty && rows.first is List) {
        rows = rows.first as List;
      }
      var probs = rows.map((e) => (e as num).toDouble()).toList();
      if (probs.length < 3) return null;
      probs = probs.sublist(0, 3);

      // Falls Logits (Summe deutlich != 1): numerisch stabile Softmax.
      final sum = probs.fold<double>(0, (a, b) => a + b);
      if ((sum - 1.0).abs() > 0.05) {
        final maxV = probs.reduce((a, b) => a > b ? a : b);
        final exps = probs.map((v) => math.exp(v - maxV)).toList();
        final expSum = exps.fold<double>(0, (a, b) => a + b);
        probs = [exps[0] / expSum, exps[1] / expSum, exps[2] / expSum];
      }

      return ImageSafetyResult(nsfl: probs[0], nsfw: probs[1], sfw: probs[2]);
    } catch (e) {
      debugPrint('[ImageSafety] Lokale Inferenz fehlgeschlagen: $e');
      return null;
    }
  }

  /// Dekodiert, resampled und normalisiert die Bildbytes zu einem
  /// [1, 3, 224, 224]-Float32-Tensor (NCHW, 0..255 - Normalisierung ist
  /// im Graphen eingebacken).
  ///
  /// Läuft im Hintergrund-Isolate (rein, kein Flutter-Bezug) - siehe
  /// [classifyImage].
  static Float32List _preprocessSync(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Bild konnte nicht dekodiert werden.');
    }
    final resized = img.copyResize(
      decoded,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final planeSize = _inputSize * _inputSize;
    final tensor = Float32List(3 * planeSize);
    var r = 0;
    var g = planeSize;
    var b = planeSize * 2;
    // WICHTIG (Model-Doku OwenElliott): Farbnorm + Softmax sind IM
    // GRAPHEN eingebacken - die Pixel muessen als 0..255 uebergeben
    // werden, NICHT als 0..1.
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final p = resized.getPixel(x, y);
        tensor[r++] = p.r.toDouble();
        tensor[g++] = p.g.toDouble();
        tensor[b++] = p.b.toDouble();
      }
    }
    return tensor;
  }
}
