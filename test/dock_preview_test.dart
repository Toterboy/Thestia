import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/widgets/dock_tab_bar.dart';

/// VORBEVORLAGUNG des neuen Docks (28.10.2026).
///
/// Nur von Hand zu starten:
///   flutter test test/dock_preview_test.dart
///
/// Schreibt PNGs nach %TEMP%/opencode/m133/dock/. Zweck: eine
/// Reiterleiste, die man nie gesehen hat, ist geraten statt gezeichnet.
void main() {
  testWidgets('Dock-Vorschau schreiben', (tester) async {
    final out = Directory(
        '${Directory.systemTemp.path}/opencode/m133/dock');
    try {
      if (!out.existsSync()) out.createSync(recursive: true);
    } catch (_) {
      debugPrint('Ablageort nicht nutzbar - uebersprungen.');
      return;
    }
    if (!out.existsSync()) return;

    // Die echten Schriften nachladen: ohne sie malt der Test das
    // Ersatzkaestchen (Ahem) statt Text und Icons - man kann das Dock
    // dann nicht beurteilen.
    final sdk = r'C:\Users\Thoralf\Flutter_SDK\flutter\bin\cache\artifacts'
        r'\material_fonts';
    for (final datei in ['materialicons-regular.otf', 'roboto-regular.ttf']) {
      final f = File('$sdk\\$datei');
      if (!f.existsSync()) continue;
      final bytes = f.readAsBytesSync();
      final loader = FontLoader(
        datei.startsWith('material') ? 'MaterialIcons' : 'Roboto',
      )..addFont(
          Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
      await loader.load();
    }
    final loader2 = FontLoader('packages/flutter/MaterialIcons')
      ..addFont(Future.value(ByteData.view(
          Uint8List.fromList(
              File('$sdk\\materialicons-regular.otf').readAsBytesSync()).buffer)));
    await loader2.load();

    final tabs = [
      const DockTab(
          route: '/', icon: Icons.newspaper, labelKey: 'nav.home'),
      const DockTab(
          route: '/entdecken',
          icon: Icons.favorite,
          labelKey: 'nav.discover'),
      const DockTab(
          route: '/interessen', icon: Icons.people, labelKey: 'nav.interests'),
      const DockTab(
          route: '/profil', icon: Icons.person, labelKey: 'nav.profile'),
    ];

    for (final index in [0, 1, 2, 3]) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE9457B)),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFFF7F7FB),
              width: 400,
              height: 120,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFEDF4),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: const Color(0xFFCAC4D0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 26,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Material(
                        type: MaterialType.transparency,
                        child: DockTabBar(
                          index: index,
                          tabs: tabs,
                          onSelected: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
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
        final datei = File('${out.path}/dock_$index.png');
        await datei.writeAsBytes(daten.buffer.asUint8List());
        debugPrint('geschrieben: ${datei.path}');
      });
      await tester.pumpAndSettle();
    }
  });
}
