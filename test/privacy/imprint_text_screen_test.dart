// Das Impressum IN der App (BEFUND 20.11.2026, Betreiber: "Das
// Impressum in der App funktioniert nicht").
//
// DIE URSACHE: Die App verlinkte auf https://thestia.de/impressum.
// Diese Domain ist ein VERIFIZIERTER APP-LINK (assetlinks.json +
// android:autoVerify im Manifest) - Android oeffnet einen solchen Link
// in der App selbst, nicht im Browser. Die App bekam ihren eigenen Link
// und zeigte nichts.
//
// Wie bei den Nutzungsbedingungen (14.11.2026) steht der Text jetzt im
// Binary. Und: die App oeffnet thestia.de grundsatzlich nicht mehr -
// der Test am Ende sichert das ab.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/generated/imprint_de.dart';
import 'package:thestia/generated/imprint_en.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/privacy/imprint_text_screen.dart';
import 'package:thestia/screens/privacy/privacy_screen.dart';

/// Die Anschrift muss in der App stehen - sie ist der Pflichtteil der
/// Anbieterkennzeichnung nach Par. 5 DDG.
const _anschrift = 'Im Schlade 10, 28844 Weyhe';

void main() {
  testWidgets('der Bildschirm zeigt den Volltext des Impressums', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ImprintTextScreen())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Impressum'), findsWidgets);
    expect(
      find.textContaining(_anschrift),
      findsOneWidget,
      reason: 'Die ladungsfaehige Anschrift muss in der App stehen.',
    );
  });

  testWidgets('der ganze Text steht drin (nicht nur die ersten Zeilen)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ImprintTextScreen())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Der letzte Abschnitt steht weit unten - er wird sichtbar, wenn man
    // scrollt.
    final lizenz = find.textContaining('AGPL-3.0');
    for (var i = 0; i < 12 && lizenz.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      lizenz,
      findsOneWidget,
      reason:
          'Alle Abschnitte muessen in der App stehen - auch die am Ende. '
          'Sonst ist die Fassung in der App unvollstaendig.',
    );
  });

  testWidgets('die Kachel in den Datenschutz-Einstellungen oeffnet den Text', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.privacy,
      routes: [
        GoRoute(
          path: AppRoutes.privacy,
          builder: (context, state) => const PrivacyScreen(),
        ),
        GoRoute(
          path: AppRoutes.imprint,
          builder: (context, state) => const ImprintTextScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Die Kachel steht nicht ganz oben - der Test muss scrollen.
    final kachel = find.text('Impressum');
    for (var i = 0; i < 12 && kachel.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(kachel, findsOneWidget);

    await tester.tap(kachel);
    await tester.pumpAndSettle();

    // Der Bildschirm mit dem Text steht jetzt da - nicht der Browser.
    expect(find.byType(ImprintTextScreen), findsOneWidget);
    expect(find.textContaining(_anschrift), findsOneWidget);
  });

  test('beide Sprachfassungen sind vollstaendig', () {
    expect(kImprintDe, isNotEmpty);
    expect(kImprintEn, isNotEmpty);
    // Beide Fassungen muessen gleich lang sein - sonst fehlt in einer
    // Sprache ein Abschnitt.
    expect(kImprintDe.length, kImprintEn.length);
    expect(kImprintDe.any((b) => b.text.contains(_anschrift)), isTrue);
    expect(kImprintEn.any((b) => b.text.contains(_anschrift)), isTrue);
    // Die Kontaktadressen stehen drin.
    expect(
      kImprintDe.any((b) => b.text.contains('datenschutz@thestia.de')),
      isTrue,
    );
  });

  test('die App oeffnet thestia.de nicht - das waere die App selbst', () {
    // DER BEFUND: thestia.de ist ein verifizierter App-Link. Jeder Link
    // auf diese Domain, den die App oeffnet, landet in der App statt in
    // einem Browser - der Nutzer sieht nichts. Die Webfassung laeuft
    // deshalb ueber auth.thestia.de.
    final treffer = <String>[];
    final dateien = Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>();
    for (final datei in dateien) {
      if (!datei.path.endsWith('.dart')) continue;
      final inhalt = datei.readAsStringSync();
      // Jede Stelle, an der eine URL entsteht (Uri.parse, launchUrl),
      // mit dem Textfenster dahinter: dort stehen auch die URLs, die
      // ein Bedingungsausdruck waehlt.
      for (final muster in [RegExp(r'Uri\.parse\('), RegExp(r'launchUrl\(')]) {
        var pos = 0;
        while (true) {
          final trefferMuster = muster.firstMatch(inhalt.substring(pos));
          if (trefferMuster == null) break;
          final start = pos + trefferMuster.start;
          final fenster = inhalt.substring(
            start,
            start + 300 > inhalt.length ? inhalt.length : start + 300,
          );
          for (final literal in RegExp(r"'([^']*)'").allMatches(fenster)) {
            final url = literal.group(1) ?? '';
            if (!url.startsWith('http')) continue;
            final ohneSchema = url.replaceFirst(RegExp(r'^https?://'), '');
            final host = ohneSchema.split('/').first.toLowerCase();
            if (host == 'thestia.de' || host == 'www.thestia.de') {
              treffer.add('${datei.path}: $url');
            }
          }
          pos = start + muster.pattern.length;
        }
      }
    }

    expect(
      treffer,
      isEmpty,
      reason:
          'Diese Links oeffnen die App selbst (App-Link) statt der Seite:\n'
          '${treffer.join('\n')}',
    );
  });
}
