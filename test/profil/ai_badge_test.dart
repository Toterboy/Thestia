// Render-Tests fuer das KI-Herkunfts-Abzeichen.
//
// ANLASS (Nutzerwunsch Transparenz): Das Abzeichen unterscheidet
// lokale KI (On-Device - nichts verlaesst das Geraet) von Cloud-KI
// (Daten gehen an einen Drittanbieter). Wer die beiden verwechselt,
// sagt den Nutzern das Falsche ueber ihre Daten - deshalb wird hier
// mehr als "es steht irgendwas da" geprueft: Text, Symbol UND Farbe.
//
// Die Farbe ist wichtig: In einem Dialog-Titel sitzt der Badge neben
// dem Text, und das Auge trennt die beiden Sorten an der Flaeche, nicht
// an der Beschriftung.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/widgets/ai_badge.dart';

/// Huelle fuer den Badge.
///
/// Der [L10nScope] steht ueber dem [MaterialApp]: `L10n.t` sucht ihn
/// ueber den Kontext. Ohne ihn liefert der Badge immer Deutsch - auch
/// dann, wenn die App auf Englisch steht.
Widget _huelle(Widget kind, {Locale? sprache, double scale = 1.0}) {
  return ProviderScope(
    overrides: [
      localeProvider.overrideWith((ref) => sprache ?? const Locale('de')),
    ],
    child: L10nScope(
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: kind,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Die Farbe des Badge-Rahmens (der einzige Container im Badge).
BoxDecoration _deko(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(of: find.byType(AiBadge), matching: find.byType(Container)),
  );
  return container.decoration as BoxDecoration;
}

void main() {
  group('AiBadge', () {
    testWidgets('lokale KI nennt sich On-Device-KI', (tester) async {
      await tester.pumpWidget(_huelle(const AiBadge.local()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('On-Device-KI'), findsOneWidget);
      expect(find.byIcon(Icons.memory_outlined), findsOneWidget);
    });

    testWidgets('Cloud-KI nennt sich auch so', (tester) async {
      await tester.pumpWidget(_huelle(const AiBadge.cloud()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cloud-KI'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    });

    testWidgets('die zwei Sorten sehen unterschiedlich aus', (tester) async {
      // Gegenprobe: Wenn beide Sorten gleich aussaehen, traegt die
      // Farbe die Unterscheidung nicht - und das Auge kann sie nicht
      // mehr herleiten.
      await tester.pumpWidget(_huelle(const AiBadge.local()));
      await tester.pumpAndSettle();
      final lokal = _deko(tester);

      await tester.pumpWidget(_huelle(const AiBadge.cloud()));
      await tester.pumpAndSettle();
      final cloud = _deko(tester);

      expect(lokal.color, isNot(cloud.color));
      // Die Cloud-Variante hat zusaetzlich einen Rahmen, die lokale
      // nicht - das ist der zweite Unterschied neben der Farbe.
      expect(lokal.border, isNull);
      expect(cloud.border, isNotNull);
    });

    testWidgets('der Badge folgt der Sprache der App', (tester) async {
      await tester.pumpWidget(
        _huelle(const AiBadge.local(), sprache: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('On-device AI'), findsOneWidget);
    });

    testWidgets('ein ausdruecklicher Sprachcode schlaegt die App-Sprache', (
      tester,
    ) async {
      // Der Dialog-Titel braucht einen Badge in einer bestimmten
      // Sprache, unabhaengig davon, was die App gerade eingestellt hat.
      await tester.pumpWidget(
        _huelle(const AiBadge(languageCode: 'en'), sprache: const Locale('de')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('On-device AI'), findsOneWidget);
      expect(find.text('On-Device-KI'), findsNothing);
    });

    testWidgets('die kompakte Form ist kleiner', (tester) async {
      await tester.pumpWidget(_huelle(const AiBadge.local()));
      await tester.pumpAndSettle();
      final normal = tester.getSize(find.byType(AiBadge));

      await tester.pumpWidget(_huelle(const AiBadge.localCompact()));
      await tester.pumpAndSettle();
      final kompakt = tester.getSize(find.byType(AiBadge));

      expect(kompakt.height, lessThan(normal.height));
      expect(kompakt.width, lessThan(normal.width));
    });

    testWidgets('die kompakte Form traegt denselben Text', (tester) async {
      // Kompakt heisst "kleiner", nicht "anderes": die Aussage muss
      // dieselbe bleiben.
      await tester.pumpWidget(_huelle(const AiBadge.cloudCompact()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cloud-KI'), findsOneWidget);
    });

    testWidgets('ueberlebt grosse Schrift ohne Overflow', (tester) async {
      await tester.pumpWidget(_huelle(const AiBadge.local(), scale: 3.2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('On-Device-KI'), findsOneWidget);
    });
  });
}
