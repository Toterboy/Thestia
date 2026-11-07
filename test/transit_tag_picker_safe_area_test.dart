// Der Test prueft den ECHTEN Weg der App: die Merkmals-Auswahl von
// Transit Spark wird so geoeffnet, wie die App es tut - mit
// `useSafeArea: true`. Keine Nachbildung: eine Nachbildung wuerde nur
// zeigen, dass Flutter das kann, nicht dass die App es tut.
//
// BEFUND (06.11.2026, Betreiber): "Bei Transit Spark mit 'Wie siehst
// du aus' hat die Ueberschrift in der Statusleiste gesteckt."
// BEFUND (07.11.2026, Betreiber): "Aktuell ist bei Transit Spark bei
// der Aussehen auswahl die Schrift noch immer in der Statusleiste."
// Die zweite Meldung kam nicht vom Code - die getestete Datei war
// Build 33 vom 06.11. 19:00, also vor dem Fix. Dieser Test haelt
// beides fest: der Code muss stimmen, und der Weg muss der der App
// sein.
//
// Wie misst man das? Der Test setzt eine Bildschirmhoehe und einen
// Statusleisten-Einzug (padding.top). Danach wird die Position der
// Ueberschrift gemessen. Sie muss UNTERHALB der Statusleiste liegen -
// also y >= Statusleiste, und nicht etwa y = 0 (ganz oben im Bild).
//
// Der Bildschirm ist absichtlich klein (400 x 600), damit das Sheet
// hoeher ist als der Bildschirm - genau der Fall, in dem der Titel
// vorher in der Statusleiste lag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/screens/swipe/transit_radar_screen.dart';

/// Bildschirmhoehe im Test (klein, damit das Sheet darueber
/// hinausragt).
const double kBildschirmHoehe = 600;

/// Breite im Test.
const double kBildschirmBreite = 400;

/// Einzug der Statusleiste im Test.
const double kStatusleiste = 28;

/// Baut eine Test-App mit einer simulierten Statusleiste.
Widget _app(void Function(BuildContext) start) {
  return MaterialApp(
    // Der Builder liegt UEBER dem Navigator - so erben auch die
    // Routen (das Bottom-Sheet) den simulierten Einzug.
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: const Size(kBildschirmBreite, kBildschirmHoehe),
          padding: const EdgeInsets.only(top: kStatusleiste),
          viewPadding: const EdgeInsets.only(top: kStatusleiste),
        ),
        child: child!,
      );
    },
    home: Scaffold(
      body: Builder(
        builder: (context) {
          // Wird beim ersten Frame geoeffnet.
          WidgetsBinding.instance.addPostFrameCallback((_) => start(context));
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Die Ueberschrift der Merkmals-Auswahl liegt unterhalb der Statusleiste',
    (tester) async {
      await tester.pumpWidget(
        _app((context) {
          showTransitTagPickerSheet(
            context,
            titleKey: 'transit.self.title',
            hintKey: 'transit.self.hint',
            requireSelection: true,
          );
        }),
      );
      await tester.pumpAndSettle();

      // Das Sheet muss ueberhaupt offen sein.
      expect(
        find.text('Wie siehst du gerade aus?'),
        findsOneWidget,
        reason: 'die Merkmals-Auswahl wurde nicht geoeffnet',
      );

      // Wo liegt die Ueberschrift?
      final oben = tester.getTopLeft(find.text('Wie siehst du gerade aus?')).dy;

      // Die Statusleiste endet bei kStatusleiste. Der Titel muss
      // DARUNTER liegen - nicht in ihr.
      expect(
        oben,
        greaterThanOrEqualTo(kStatusleiste),
        reason:
            'die Ueberschrift liegt bei y=$oben, die Statusleiste endet '
            'bei y=$kStatusleiste - der Text liegt in der Statusleiste',
      );

      // Und er darf nicht ausserhalb des Bildschirms liegen.
      expect(
        oben,
        lessThan(kBildschirmHoehe),
        reason: 'die Ueberschrift liegt ausserhalb des Bildschirms',
      );
    },
  );

  testWidgets(
    'Das Sheet ist hoeher als der Bildschirm - nur so konnte es klemmen',
    (tester) async {
      await tester.pumpWidget(
        _app((context) {
          showTransitTagPickerSheet(
            context,
            titleKey: 'transit.self.title',
            hintKey: 'transit.self.hint',
            requireSelection: true,
          );
        }),
      );
      await tester.pumpAndSettle();

      // Der Merkmalskatalog ist lang; das Sheet ragt ueber den
      // Bildschirm hinaus. Genau deshalb war der Titel vorher oben
      // im Bild.
      //
      // Gesucht wird das unterste Sheet-Element (das Blatt selbst),
      // nicht irgendein ScrollView - im Sheet gibt es mehrere.
      final blatt = find.byType(BottomSheet);
      expect(blatt, findsWidgets, reason: 'das Sheet wurde nicht gefunden');
      final blattOben = tester.getTopLeft(blatt.first).dy;

      expect(
        blattOben,
        lessThanOrEqualTo(kStatusleiste),
        reason:
            'das Sheet beginnt erst bei y=$blattOben - dann waere es nie '
            'in der Statusleiste gelandet und der Test pruefte nichts',
      );
    },
  );
}
