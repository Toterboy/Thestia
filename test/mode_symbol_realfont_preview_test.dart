import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/widgets/mode_icons.dart';

/// Vorschau der Mode-Symbole MIT DER ECHTEN Material-Schrift.
///
/// Warum es diese Datei gibt: `test/mode_symbol_preview_test.dart`
/// zeichnet den Transit-Spark mit einem **Ersatzkaestchen** - in
/// `flutter_test` fehlt die Material-Schrift, und der TextPainter
/// findet die Glyphe nicht. Man sieht dann ein Kästchen statt eines
/// Zuges und kann das Symbol nicht beurteilen.
///
/// Mit dem FontLoader wird die echte Schrift aus dem Flutter-SDK
/// nachgeladen. Danach stimmt auch die GEOMETRIE: `Icons.train` hat
/// eine Tinte von x = 17..82 und y = 8..86 je 100er-Em, nicht die
/// geratenen Werte, mit denen der Zug vorher falsch platziert war.
///
/// Nur von Hand zu starten:
///   flutter test test/mode_symbol_realfont_preview_test.dart
///
/// Das Ergebnis liegt in:
///   %TEMP%/opencode/m133/symbole/real_*.png
///
/// Auf einem Rechner ohne Flutter-SDK-Dateien (oder ohne Schreibrecht
/// im Temp-Verzeichnis) macht der Test nichts und meldet sich gruen -
/// er ist ein WERKZEUG, kein Guard.
void main() {
  testWidgets('Vorschau mit echter Material-Schrift', (tester) async {
    // SystemTemp statt eines festen Windows-Pfads: auf einer
    // Linux-Pipeline wuerde ein fester Pfad ein Verzeichnis mit
    // Backslashes im Arbeitsverzeichnis anlegen.
    final out = Directory(
        '${Directory.systemTemp.path}/opencode/m133/symbole');
    try {
      if (!out.existsSync()) out.createSync(recursive: true);
    } catch (_) {
      debugPrint('Vorschau-Ablageort nicht nutzbar - uebersprungen.');
      return;
    }
    if (!out.existsSync()) return;

    final fontdatei = _materialFont();
    if (fontdatei == null) {
      debugPrint('Material-Schrift nicht gefunden - uebersprungen.');
      return;
    }

    // ZWEI Namen: einmal der puren Familie (fuer Text ohne package)
    // und einmal der paket-qualifizierte Familie. Der Transit-Spark
    // zeichnet mit `package: 'flutter'` - ohne den zweiten Eintrag
    // waere dort wieder das Ersatzkaestchen zu sehen.
    final bytes = Uint8List.fromList(fontdatei.readAsBytesSync());
    for (final familie in [
      'MaterialIcons',
      'packages/flutter/MaterialIcons',
    ]) {
      final loader = FontLoader(familie)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }

    const k = 240.0;
    final faelle = <String, CustomPainter Function(Color)>{
      'transit_spark': (c) => TransitSparkPainter(c),
      'find_spark': (c) => FindSparkPainter(c),
      'zufallschat': (c) => QuestionChatPainter(c),
    };

    // Zwei Groessen: 240 px zum Beurteilen der Form und 28 px in der
    // Groesse, in der das Symbol in der App wirklich steht (dann sieht
    // man, ob kleine Teile - Funken-Schweif, Punkte - noch lesbar
    // sind).
    for (final groesse in [k, 28.0]) {
      for (final eintrag in faelle.entries) {
        final key = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: const Color(0xFF6750A4),
                width: groesse,
                height: groesse,
                child: CustomPaint(
                  painter: eintrag.value(const Color(0xFFFFFFFF)),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          final randung = key.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
          if (randung == null) return;
          final bild = await randung.toImage();
          final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
          if (daten == null) return;
          final suffix = groesse > 100 ? '' : '_klein';
          final datei =
              File('${out.path}/real_${eintrag.key}$suffix.png');
          await datei.writeAsBytes(daten.buffer.asUint8List());
          debugPrint('geschrieben: ${datei.path}');
        });
        await tester.pumpAndSettle();
      }
    }
  });
}

/// Findet die Material-Schrift im Flutter-SDK.
///
/// Reihenfolge: `FLUTTER_ROOT` aus der Umgebung, danach der Weg zur
/// Dart-Executable (im Flutter-SDK liegt sie unter bin/cache/dart-sdk).
File? _materialFont() {
  const name = 'material_fonts/materialicons-regular.otf';

  final wurzel = Platform.environment['FLUTTER_ROOT'];
  if (wurzel != null && wurzel.isNotEmpty) {
    final datei = File('$wurzel/bin/cache/artifacts/$name');
    if (datei.existsSync()) return datei;
  }

  // .../flutter/bin/cache/dart-sdk/bin/dart.exe -> .../flutter
  var teile = Platform.resolvedExecutable.split(RegExp(r'[\\/]'));
  if (teile.length > 5) {
    teile = teile.sublist(0, teile.length - 5);
    final datei = File('${teile.join('/')}/bin/cache/artifacts/$name');
    if (datei.existsSync()) return datei;
  }
  return null;
}
