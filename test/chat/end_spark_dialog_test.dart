// Der Dialog "Funke beenden" (bisher ungetestet - 0 %).
//
// ANLASS (15.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/chat/end_spark_dialog.dart 0 % - und die Absage-Texte sind
// nutzersichtbar: sie werden an die andere Person geschickt.
//
// WAS HIER GEPRÜFT WIRD:
//   * es gibt genau vier vorbereitete Absage-Texte (nicht drei, nicht
//     fünf - der Dialog und die Texte müssen zusammenpassen),
//   * "Ruhig enden lassen" ist die Voreinstellung (ohne Nachricht),
//   * ein gewählter Absage-Text wird zurückgegeben,
//   * "Abbrechen" gibt nichts zurück (kein Funke wird gekühlt),
//   * der Text zur Auswahl wird richtig zugeteilt (und zu keinem bei
//     "silent" oder einer erfundenen Auswahl).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/chat/end_spark_dialog.dart';

void main() {
  /// Öffnet den Dialog, fährt die [aktion] aus und liefert, was der
  /// Dialog zurückgegeben hat.
  Future<String?> dialogMit(
    WidgetTester tester,
    Future<void> Function() aktion,
  ) async {
    String? ergebnis;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                ergebnis = await showEndSparkDialog(context);
              },
              child: const Text('oeffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('oeffnen'));
    await tester.pumpAndSettle();
    await aktion();
    await tester.pumpAndSettle();
    return ergebnis;
  }

  group('Der Dialog "Funke beenden"', () {
    test('es gibt genau vier Absage-Texte', () {
      // DER WEG: Der Dialog baut genau so viele Auswahlzeilen, wie es
      // Texte gibt. Stimmt die Zahl nicht, fehlt im Dialog eine Zeile -
      // oder er zeigt eine ohne Text.
      expect(goodbyeCount, 4);
    });

    testWidgets('der Dialog steht da mit allen Zeilen', (tester) async {
      await dialogMit(tester, () async {
        // nichts tun - nur ansehen
      });

      expect(
        find.text(L10n.tWithoutContext('chat.endSparkTitle')),
        findsOneWidget,
      );
      expect(find.text(L10n.tWithoutContext('chat.endSilent')), findsOneWidget);
      // Und alle vier Absage-Texte sind wählbar.
      for (var i = 1; i <= goodbyeCount; i++) {
        expect(
          find.text(L10n.tWithoutContext('chat.goodbye.$i')),
          findsOneWidget,
          reason: 'Der Absage-Text $i muss im Dialog stehen.',
        );
      }
    });

    testWidgets('"Ruhig enden lassen" ist die Voreinstellung', (tester) async {
      final ergebnis = await dialogMit(tester, () async {
        await tester.tap(find.text(L10n.tWithoutContext('chat.coolSpark')));
      });

      // Ohne Auswahl: der Funke endet ruhig, ohne Nachricht.
      expect(ergebnis, 'silent');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('ein gewaehlter Absage-Text wird zurueckgegeben', (
      tester,
    ) async {
      final ergebnis = await dialogMit(tester, () async {
        // Den zweiten Absage-Text wählen.
        await tester.tap(find.text(L10n.tWithoutContext('chat.goodbye.2')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(L10n.tWithoutContext('chat.coolSpark')));
      });

      expect(ergebnis, 'msg_1');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('"Abbrechen" gibt nichts zurueck', (tester) async {
      final ergebnis = await dialogMit(tester, () async {
        await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      });

      // Nichts zurück: es wird kein Funke gekühlt.
      expect(ergebnis, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('der Text zur Auswahl wird richtig zugeteilt', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Die Auswahl kommt als 'msg_0'..'msg_3' zurück - der Text dazu
      // ist der mit dem Index.
      for (var i = 0; i < goodbyeCount; i++) {
        expect(
          goodbyeTextForChoice(ctx, 'msg_$i'),
          L10n.tWithoutContext('chat.goodbye.${i + 1}'),
          reason: 'Die Auswahl msg_$i muss zum Text ${i + 1} passen.',
        );
      }
    });

    testWidgets('ohne Auswahl gibt es keinen Text', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // "Ruhig enden" heißt: ohne Nachricht. Und eine erfundene
      // Auswahl darf keinen Text erzeugen (sonst schickt die App einen
      // leeren oder fremden Text).
      expect(goodbyeTextForChoice(ctx, 'silent'), isNull);
      expect(goodbyeTextForChoice(ctx, ''), isNull);
      expect(goodbyeTextForChoice(ctx, 'msg_4'), isNull);
      expect(goodbyeTextForChoice(ctx, 'msg_x'), isNull);
      expect(goodbyeTextForChoice(ctx, 'sonstwas'), isNull);
    });
  });
}
