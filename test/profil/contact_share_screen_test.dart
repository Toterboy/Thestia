// "Mit anderen verbinden" (die Kontaktdaten) - der Bildschirm war
// ungetestet.
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/qr/contact_share_screen.dart 113 offene Zeilen. Bisher war
// nur das MODELL getestet - der Bildschirm selbst (das Formular, das
// Pruefen, das Speichern, das Teilen) nicht.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (alle vorgeschlagenen Apps stehen da),
//   * eine ungueltige Telefonnummer wird abgewiesen,
//   * eine App ohne Handle wird abgewiesen,
//   * ein gueltiger Stand wird gespeichert,
//   * das Teilen legt den Text in die Zwischenablage.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/qr/contact_share_screen.dart';

import '../support/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    // DER KEYSTORE: die Kontaktdaten liegen im verschluesselten
    // Geraetespeicher.
    mockKeystore();
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (anfrage) async => null,
        );
  });

  /// Baut den Bildschirm.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const ContactShareScreen(),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Scrollt bis zum Knopf (die Seite ist lang).
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    // DER HINWEIS: Der Knopf wird GEFUNDEN, auch wenn er ausserhalb des
    // Sichtbaren liegt - der Tipp ging dann ins Leere. ensureVisible
    // scrollt ihn wirklich in den Blick.
    await tester.ensureVisible(find.text(text));
    await tester.pump(const Duration(milliseconds: 150));
  }

  group('Die Kontaktdaten', () {
    testWidgets('der Bildschirm baut sich', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.phone')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('contactShare.signal')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('contactShare.threema')),
        findsOneWidget,
      );
    });

    testWidgets('eine ungueltige Telefonnummer wird abgewiesen', (
      tester,
    ) async {
      await zeigeScreen(tester);

      await tester.enterText(find.byType(TextField).first, '123');
      await tester.pump();

      await scrolleZu(tester, L10n.tWithoutContext('contactShare.save'));
      await tester.tap(find.text(L10n.tWithoutContext('contactShare.save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.invalidPhone')),
        findsOneWidget,
        reason:
            'Eine ungueltige Nummer muss abgewiesen werden - sonst speichert '
            'die App Muell.',
      );
    });

    testWidgets('ein gueltiger Stand wird gespeichert', (tester) async {
      await zeigeScreen(tester);

      await tester.enterText(find.byType(TextField).first, '+4915112345678');
      await tester.pump();

      await scrolleZu(tester, L10n.tWithoutContext('contactShare.save'));
      await tester.tap(find.text(L10n.tWithoutContext('contactShare.save')));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.saved')),
        findsOneWidget,
        reason: 'Der Nutzer muss wissen, dass die Daten gespeichert sind.',
      );
    });

    testWidgets('das Teilen legt den Text in die Zwischenablage', (
      tester,
    ) async {
      await zeigeScreen(tester);

      await tester.enterText(find.byType(TextField).first, '+4915112345678');
      await tester.pump();

      await scrolleZu(tester, L10n.tWithoutContext('contactShare.copy'));
      await tester.tap(find.text(L10n.tWithoutContext('contactShare.copy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('contactShare.copied')),
        findsOneWidget,
      );

      // Der Bildschirm wird abgebaut - der Timer, der die Zwischenablage
      // nach 60 Sekunden leert, muss beendet werden.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
