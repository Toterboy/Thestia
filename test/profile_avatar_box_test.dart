// Tests fuer den gemeinsamen Profilbild-Baustein.
//
// BEFUND (07.11.2026, Betreiber):
//   * "doppeltes Profilbild"
//   * "Die Profilvorschau soll dem entsprechen, was auch andere wirklich
//     sehen koennen."
//
// WARUM ueberhaupt ein Baustein: Das Profilbild wurde an mehreren
// Stellen nachgebaut. Die eine zeichnete einen Kreis (112 px), die
// andere ein abgerundetes Rechteck (118 x 152) - die Vorschau sah also
// anders aus als das Original. Zwei getrennte Nachbauten sind der
// Grund fuer solche Abweichungen: sie laufen auseinander, sobald eine
// Stelle geaendert wird.
//
// Dieser Test haelt beide Eigenschaften fest:
//   1. Das Bild hat IMMER dieselbe Form (nicht "mal Kreis, mal
//      Rechteck").
//   2. Der Geburtstagsrahmen erscheint genau dann, wenn heute
//      Geburtstag ist - und nur dann.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/widgets/profile_avatar_box.dart';

/// Ein kleines echtes PNG (1x1, transparent) - genug, damit
/// Image.memory etwas zu dekodieren hat.
Uint8List miniPng() => Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x00, 0x00, 0x00,
      0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

Widget rahmen(Widget kind) => MaterialApp(
      home: Scaffold(body: Center(child: kind)),
    );

void main() {
  group('Der gemeinsame Profilbild-Baustein', () {
    testWidgets('zeigt das Bild in der abgerundeten Form', (tester) async {
      await tester.pumpWidget(
        rahmen(ProfileAvatarBox(bytes: miniPng())),
      );
      await tester.pump();

      final bild = tester.widget<Image>(find.byType(Image));
      expect(bild.fit, BoxFit.cover);
      // Die Form: ein Rechteck, KEIN Kreis. Genau das war der
      // Unterschied zwischen Vorschau und echtem Profil.
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('ohne Bild erscheint das Platzhalter-Symbol', (tester) async {
      await tester.pumpWidget(
        rahmen(
          ProfileAvatarBox(bytes: null, placeholderIcon: Icons.person),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('am Geburtstag kommt der Rahmen dazu', (tester) async {
      await tester.pumpWidget(
        rahmen(
          ProfileAvatarBox(
            bytes: miniPng(),
            birthdayStyle: 'midnight',
            isBirthday: true,
          ),
        ),
      );
      await tester.pump();

      // Der Rahmen ist ein Container mit Verlauf - ohne Geburtstag
      // gibt es ihn nicht.
      final mitRahmen = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) => (c.decoration as BoxDecoration).gradient != null)
          .length;
      expect(mitRahmen, greaterThan(0));
    });

    testWidgets('ohne Geburtstag gibt es keinen Rahmen', (tester) async {
      await tester.pumpWidget(
        rahmen(
          ProfileAvatarBox(
            bytes: miniPng(),
            birthdayStyle: 'midnight',
            isBirthday: false,
          ),
        ),
      );
      await tester.pump();

      final mitRahmen = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .where((c) => (c.decoration as BoxDecoration).gradient != null)
          .length;
      expect(mitRahmen, 0);
    });

    testWidgets('die Groesse ist immer dieselbe', (tester) async {
      await tester.pumpWidget(
        rahmen(ProfileAvatarBox(bytes: miniPng())),
      );
      await tester.pump();

      final box = tester.getSize(find.byType(ProfileAvatarBox));
      expect(box.width, 118);
      expect(box.height, 152);
    });
  });
}
