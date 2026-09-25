// tool/generate_splash_images.dart
//
// Erzeugt die Splash-Bilder fuer flutter_native_splash aus dem
// Basis-Logo (assets/images/thestia_icon_base.png):
//
//  1) thestia_splash.png            - regulierter Splash (Android < 12):
//        Logo verkleinert (~47 %) auf transparenter 1024er-Leinwand.
//        Ohne diese Verkleinerung rendert flutter_native_splash das
//        920-px-Logo in Vollgroesse zentriert = "reingezoomt".
//  2) thestia_splash_android12.png  - Android 12+ Splash:
//        1152er-Leinwand, Logo auf ~55 % zentriert. Das System maskiert
//        kreisfoermig (sichtbarer Kreis-Durchmesser ~768 px) - bei der
//        Vollgroesse wurde die "Thestia"-Schrift unten abgeschnitten.
//
// Ausfuehren:  dart run tool/generate_splash_images.dart
// Danach:      dart run flutter_native_splash:create
//
// (Bewusst ein Dart-Skript: das `image`-Paket ist bereits Dependency.)

import 'dart:io';

import 'package:image/image.dart' as img;

const String _sourcePath = 'assets/images/thestia_icon_base.png';

Future<void> main() async {
  final File sourceFile = File(_sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Basis-Logo nicht gefunden: $_sourcePath');
    exit(1);
  }

  final img.Image? source = img.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Basis-Logo konnte nicht dekodiert werden.');
    exit(1);
  }

  void generate({
    required int canvasSize,
    required double logoScale,
    required String outputPath,
  }) {
    final int logoSize = (canvasSize * logoScale).round();
    final img.Image resized = img.copyResize(
      source,
      width: logoSize,
      height: logoSize,
      interpolation: img.Interpolation.cubic,
    );

    // Transparente Leinwand (Image-4.x-Konstruktor initialisiert alle
    // Pixel mit 0 = voll transparent), Logo exakt zentriert.
    final img.Image canvas = img.Image(width: canvasSize, height: canvasSize);

    final int offsetX = (canvasSize - logoSize) ~/ 2;
    final int offsetY = (canvasSize - logoSize) ~/ 2;
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    File(outputPath).writeAsBytesSync(img.encodePng(canvas));
    stdout.writeln('OK: $outputPath ($canvasSize x $canvasSize, '
        'Logo $logoSize px)');
  }

  // 1) Regulaerer Splash (Android < 12): Logo ~47 % der Leinwand.
  generate(
    canvasSize: 1024,
    logoScale: 0.47,
    outputPath: 'assets/images/thestia_splash.png',
  );

  // 2) Android 12+: Kreis-Maske (~768 px sichtbar) - Logo 55 %, damit die
  //    Schrift sicher innerhalb des Kreises liegt.
  generate(
    canvasSize: 1152,
    logoScale: 0.55,
    outputPath: 'assets/images/thestia_splash_android12.png',
  );

  stdout.writeln('Fertig. Jetzt: dart run flutter_native_splash:create');
}
