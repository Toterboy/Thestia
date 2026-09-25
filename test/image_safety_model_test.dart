// Verifiziert das echte NSFW-Modell: Asset vorhanden, ONNX-Header mit der
// gepatchten IR-Version (9 - die gebündelte Runtime unterstützt max. 9)
// und - wenn die native Runtime verfügbar ist - eine echte Inferenz.
//
// Der Inferenz-Teil benötigt die native onnxruntime-Bibliothek. In der
// App ist sie über das Plugin gebündelt (Android/iOS/Desktop-Builds);
// der CI-Workflow installiert sie vor `flutter test`. Fehlt sie in einer
// Umgebung trotzdem, werden NUR die Asset-/Header-Checks übersprungen -
// der Test bleibt grün, ohne die Regression Blind zu stellen.
import 'package:flutter/services.dart' show Uint8List, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:thestia/services/image_safety_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NSFW-Modell: Asset, IR-Header und Inferenz', () async {
    // 1) Asset gebündelt und nicht leer.
    final data =
        await rootBundle.load('assets/models/image-safety-classifier-xs.onnx');
    final modelBytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    // ignore: avoid_print
    print('Asset-Größe: ${modelBytes.length} Bytes');
    expect(modelBytes.length, greaterThan(1000000),
        reason: 'Modell muss gebündelt sein (~12 MB) - sonst deaktiviert '
            'sich der NSFW-Check still.');

    // 2) ONNX-Header: ModelProto beginnt mit Feld 1 (ir_version). Das
    // Original-Modell kam mit IR 10 (Runtime max. 9 = stiller Total-
    // ausfall) - der Patch auf 9 ist die eigentliche Regression.
    // ignore: avoid_print
    print('ONNX-Header: ir_version=${modelBytes[1]}');
    expect(modelBytes[0], 0x08,
        reason: 'ModelProto muss mit dem ir_version-Feld beginnen');
    expect(modelBytes[1], 9,
        reason: 'ir_version muss 9 sein (Runtime-Support-Grenze) - '
            'IR 10 lässt die Runtime still scheitern.');

    // 3) Echte Inferenz - nur mit verfügbarer nativer Runtime.
    final available = await ImageSafetyService.instance.ensureSession();
    // ignore: avoid_print
    print('ensureSession -> $available');
    if (!available) {
      // Native Bibliothek fehlt (z. B. Test-Umgebung ohne onnxruntime).
      // Die kritischen Checks (1 + 2) sind oben bereits durch.
      // ignore: avoid_print
      print('SKIP Inferenz: native onnxruntime in dieser Umgebung nicht '
          'verfügbar (Asset + IR-Header wurden geprüft).');
      return;
    }

    // Testbild: farbiger Verlauf (kein NSFW-Inhalt).
    final im = img.Image(width: 300, height: 300);
    for (var y = 0; y < 300; y++) {
      for (var x = 0; x < 300; x++) {
        im.setPixelRgba(x, y, x % 256, y % 256, (x + y) % 256, 255);
      }
    }
    final imageBytes = Uint8List.fromList(img.encodeJpg(im, quality: 90));

    final result = await ImageSafetyService.instance.classifyImage(imageBytes);
    expect(result, isNotNull,
        reason: 'Inferenz muss funktionieren - null bedeutet stiller '
            'Fallback ohne Dialog.');
    // ignore: avoid_print
    print('nsfl=${result!.nsfl.toStringAsFixed(3)} '
        'nsfw=${result.nsfw.toStringAsFixed(3)} '
        'sfw=${result.sfw.toStringAsFixed(3)} top=${result.topLabel}');
    expect(result.sfw, greaterThan(result.nsfw),
        reason: 'Ein harmloses Verlaufsbild muss als SFW erkannt werden.');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
