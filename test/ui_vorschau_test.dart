import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:thestia/screens/core/main_navigation.dart';
import 'package:thestia/widgets/pill_tab_bar.dart';

/// VORAB-RENDERING der geaenderten Oberflaechen (27.10.2026).
///
/// Nur von Hand zu starten:
///   flutter test test/ui_vorschau_test.dart
///
/// Schreibt PNGs nach .../Temp/opencode/m133/ui/, damit die Aenderungen
/// angesehen werden koennen, ohne die App auf einem Geraet zu oeffnen.
///
/// Warum das Werkzeug es gibt: bei den Mode-Symbolen hat der erste
/// Entwurf den Zug zerschnitten, und das fiel erst auf dem Geraet auf.
/// Ein CustomPainter, den niemand gesehen hat, ist geraten statt
/// gezeichnet.
void main() {
  testWidgets('UI-Vorschau schreiben', (tester) async {
    final out = Directory(r'C:\Users\Thoralf\AppData\Local\Temp\opencode'
        r'\m133\ui');
    try {
      if (!out.existsSync()) out.createSync(recursive: true);
    } catch (_) {
      debugPrint('Vorschau-Ablageort nicht nutzbar - uebersprungen.');
      return;
    }
    if (!out.existsSync()) return;

    Future<void> schreibe(String name, Widget widget) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: const Color(0xFFF7F5F8),
            body: Center(child: widget),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final randung = key.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (randung == null) {
          debugPrint('KEINE RANDUNG fuer $name');
          return;
        }
        final bild = await randung.toImage();
        final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
        if (daten == null) return;
        await File('${out.path}/$name.png')
            .writeAsBytes(daten.buffer.asUint8List());
        debugPrint('geschrieben: $name.png');
      });
      await tester.pumpAndSettle();
    }

    // 1) Die Pillen-Leiste, wie sie im Interessen-Screen jetzt steht.
    final controller = TabController(length: 3, vsync: tester);
    addTearDown(controller.dispose);
    await schreibe(
      'pillen_leiste',
      SizedBox(
        width: 420,
        child: PillTabBar(
          controller: controller,
          tabs: const [
            PillTab(label: 'Gesendet', icon: Icons.outgoing_mail),
            PillTab(label: 'Erhalten', icon: Icons.call_received),
            PillTab(label: 'Funken', icon: Icons.flash_on, count: 3),
          ],
        ),
      ),
    );

    // 2) Die neue Bottom-Navigation (NUTZERWUNSCH 27.10.2026: der
    //    aktive Reiter soll mehr sein als ein farbiges Logo).
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const MainNavigation(
            child: Scaffold(body: Center(child: Text('Aktuelles'))),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    final navKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: navKey,
        child: ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFC4236C),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final randung = navKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (randung == null) {
        debugPrint('KEINE RANDUNG fuer bottom_navigation');
        return;
      }
      final bild = await randung.toImage();
      final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
      if (daten == null) return;
      await File('${out.path}/bottom_navigation.png')
          .writeAsBytes(daten.buffer.asUint8List());
      debugPrint('geschrieben: bottom_navigation.png');
    });

    // 3) Die Interessen-Seite: Pillen-Leiste ueber dem Inhalt, Stift
    //    nur rechts oben.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Interessen'),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {},
            ),
          ],
        ),
        body: Column(
          children: [
            PillTabBar(
              controller: controller,
              tabs: const [
                PillTab(label: 'Gesendet', icon: Icons.outgoing_mail),
                PillTab(label: 'Erhalten', icon: Icons.call_received),
                PillTab(label: 'Funken', icon: Icons.flash_on, count: 3),
              ],
            ),
            const Expanded(
              child: Center(child: Text('Inhalt des Reiters')),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Interessen'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {},
              ),
            ],
          ),
          body: Column(
            children: [
              PillTabBar(
                controller: controller,
                tabs: const [
                  PillTab(label: 'Gesendet', icon: Icons.outgoing_mail),
                  PillTab(label: 'Erhalten', icon: Icons.call_received),
                  PillTab(label: 'Funken', icon: Icons.flash_on, count: 3),
                ],
              ),
              const Expanded(
                child: Center(child: Text('Inhalt des Reiters')),
              ),
            ],
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
      await File('${out.path}/interessen_screen.png')
          .writeAsBytes(daten.buffer.asUint8List());
      debugPrint('geschrieben: interessen_screen.png');
    });
  });
}
