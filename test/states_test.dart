// Tests fuer die Leer- und Fehlerzustaende.
//
// ANLASS: [EmptyState] und [ErrorState] stehen ueberall dort, wo nichts
// zu sehen ist. Zwei Dinge sind dort leicht falsch:
//
//   1. Der Leerzustand ohne Aktion: dann steht der Nutzer vor einer
//      Wand. Der Knopf darf nur erscheinen, wenn es auch etwas zu
//      tun gibt.
//   2. Der Fehlerzustand ohne "Erneut versuchen": dann ist der
//      Nutzer auf eine neue App-Start angewiesen, weil der Bildschirm
//      sich selbst nicht erholen kann.
//
// Geprueft wird deshalb beides: dass die Inhalte da sind UND dass die
// Knopfe genau dann auftauchen, wenn sie etwas tun koennen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/widgets/states.dart';

Widget _huelle(Widget kind, {double scale = 1.0}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: kind,
      ),
    ),
  );
}

void main() {
  group('EmptyState', () {
    testWidgets('zeigt Symbol, Titel und Text', (tester) async {
      await tester.pumpWidget(
        _huelle(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Noch keine Funken',
            message: 'Sobald dich jemand mag, erscheint es hier.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('Noch keine Funken'), findsOneWidget);
      expect(
        find.text('Sobald dich jemand mag, erscheint es hier.'),
        findsOneWidget,
      );
    });

    testWidgets('ohne Aktion gibt es keinen Knopf', (tester) async {
      // Ein Knopf ohne Funktion waere eine Sackgasse.
      await tester.pumpWidget(
        _huelle(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Noch keine Funken',
            message: 'Sobald dich jemand mag, erscheint es hier.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('mit Aktion erscheint der Knopf und meldet den Tipp', (
      tester,
    ) async {
      var tipps = 0;
      await tester.pumpWidget(
        _huelle(
          EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Noch keine Funken',
            message: 'Sobald dich jemand mag, erscheint es hier.',
            actionLabel: 'Entdecken',
            onAction: () => tipps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Entdecken'), findsOneWidget);

      await tester.tap(find.text('Entdecken'));
      await tester.pumpAndSettle();

      expect(tipps, 1);
    });

    testWidgets('ueberlebt grosse Schrift ohne Overflow', (tester) async {
      // 1,5-fache Schrift ist die grosste Android-Einstellung, die
      // viele Nutzer tatsaechlich benutzen.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _huelle(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Noch keine Funken',
            message: 'Sobald dich jemand mag, erscheint es hier.',
            actionLabel: 'Entdecken',
          ),
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('ueberlebt auch die Android-Maximalstufe (3,2x)', (
      tester,
    ) async {
      // BEFUND (13.11.2026, gefunden von diesem Test und BEHOBEN): Bei
      // 3,2x lief der Leerzustand ueber - er hatte keinen eigenen
      // Scrollbereich. Die App verspricht aber, bis 3,2x benutzbar zu
      // bleiben (ROADMAP, Accessibility-Durchlauf).
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _huelle(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Noch keine Funken',
            message: 'Sobald dich jemand mag, erscheint es hier.',
            actionLabel: 'Entdecken',
          ),
          scale: 3.2,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Und der Text ist noch da - er wird nicht abgeschnitten.
      expect(find.text('Noch keine Funken'), findsOneWidget);
    });
  });

  group('ErrorState', () {
    testWidgets('zeigt die Fehlermeldung', (tester) async {
      await tester.pumpWidget(
        _huelle(const ErrorState(message: 'Der Server antwortet nicht.')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Der Server antwortet nicht.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('ohne Wiederholung gibt es keinen Knopf', (tester) async {
      await tester.pumpWidget(
        _huelle(const ErrorState(message: 'Der Server antwortet nicht.')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('mit Wiederholung erscheint der Knopf und meldet den Tipp', (
      tester,
    ) async {
      var tipps = 0;
      await tester.pumpWidget(
        _huelle(
          ErrorState(
            message: 'Der Server antwortet nicht.',
            onRetry: () => tipps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Erneut versuchen'), findsOneWidget);

      await tester.tap(find.text('Erneut versuchen'));
      await tester.pumpAndSettle();

      expect(tipps, 1);
    });

    testWidgets('ueberlebt grosse Schrift ohne Overflow', (tester) async {
      // 1,5-fache Schrift ist die grosste Android-Einstellung, die
      // viele Nutzer tatsaechlich benutzen.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _huelle(
          const ErrorState(
            message:
                'Der Server antwortet gerade nicht. Bitte versuche '
                'es noch einmal.',
          ),
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('ueberlebt auch die Android-Maximalstufe (3,2x)', (
      tester,
    ) async {
      // BEFUND (13.11.2026, gefunden von diesem Test und BEHOBEN): Bei
      // 3,2x lief der Fehlerzustand ebenfalls ueber - er hat zwar
      // weniger Inhalt, passt dann aber auch nicht mehr in den
      // Bildschirm.
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _huelle(
          const ErrorState(
            message:
                'Der Server antwortet gerade nicht. Bitte versuche '
                'es noch einmal.',
          ),
          scale: 3.2,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Der Server antwortet'), findsOneWidget);
    });
  });
}
