// Tests fuer den Startbildschirm.
//
// ANLASS: Der Bildschirm ist die ERSTE Seite, die jeder Nutzer sieht -
// und die einzige, die man nicht wegklicken kann. Er wird genau dann
// gezeigt, wenn die App noch ihre Start-Checks macht (Auth-Status,
// Einstellungen, Server-Sync).
//
// Er muss deshalb zwei Dinge gleichzeitig sein: unscheinbar (weiss wie
// der Splash, damit der Uebergang nicht auffaellt) und eindeutig
// ("die App arbeitet gerade"). Der drehende Ring ist das zweite.
//
// Geprueft wird: Logo, Ladeindikator, Hintergrund in hell und dunkel
// und kein Render-Overflow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/screens/core/loading_screen.dart';
import 'package:thestia/widgets/app_logo.dart';

Widget _huelle(Widget kind, {required Brightness helligkeit}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: helligkeit),
    home: kind,
  );
}

void main() {
  group('LoadingScreen', () {
    testWidgets('zeigt das Logo und den Ladeindikator', (tester) async {
      await tester.pumpWidget(
        _huelle(const LoadingScreen(), helligkeit: Brightness.light),
      );
      // KEIN pumpAndSettle: der Ladering dreht sich endlos - er kommt
      // nie zur Ruhe.
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(AppLogo), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('der Hintergrund ist im hellen Modus weiss', (tester) async {
      await tester.pumpWidget(
        _huelle(const LoadingScreen(), helligkeit: Brightness.light),
      );
      await tester.pump();

      final geruest = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        geruest.backgroundColor,
        Colors.white,
        reason:
            'Der Bildschirm muss wie der Splash aussehen - sonst gibt es '
            'einen sichtbaren Sprung beim Start.',
      );
    });

    testWidgets('der Hintergrund ist im dunklen Modus dunkel', (tester) async {
      await tester.pumpWidget(
        _huelle(const LoadingScreen(), helligkeit: Brightness.dark),
      );
      await tester.pump();

      final geruest = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(geruest.backgroundColor, const Color(0xFF121212));
    });

    testWidgets('der Ladeindikator ist im dunklen Modus hell', (tester) async {
      // Im dunklen Modus waere der Standard-Kringel (Farbe "primary")
      // auf schwarzem Grund schwer zu sehen.
      await tester.pumpWidget(
        _huelle(const LoadingScreen(), helligkeit: Brightness.dark),
      );
      await tester.pump();

      final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(ring.color, Colors.white70);
    });

    testWidgets('das Logo steht mittig ueber dem Ladeindikator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _huelle(const LoadingScreen(), helligkeit: Brightness.light),
      );
      await tester.pump();

      final bildschirm = tester.getRect(find.byType(Scaffold));
      final logo = tester.getRect(find.byType(AppLogo));

      expect(logo.width, closeTo(92, 1));
      expect(logo.center.dx, closeTo(bildschirm.center.dx, 1));
      // Das Logo sitzt UEBER dem Ring, nicht daneben: der Ring ist
      // darunter (deshalb ist der Mittelpunkt des Logos hoeher als
      // der Mittelpunkt des Bildschirms).
      expect(logo.center.dy, lessThan(bildschirm.center.dy));
    });

    testWidgets('rendert auch auf einem kleinen Bildschirm', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _huelle(const LoadingScreen(), helligkeit: Brightness.light),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(AppLogo), findsOneWidget);
    });
  });
}
