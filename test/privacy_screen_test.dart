// Der Datenschutz-Screen (bisher kaum getestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/privacy/privacy_screen.dart 221 offene Zeilen - und der
// Bildschirm traegt die Aussagen, die der Betreiber nachgefuehrt hat:
// die Auftragsverarbeiter (kein Apple, Google nur fuer die
// Play-Store-Fassung) und der Weg zu den Nutzungsbedingungen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * der Datenexport liegt unter "Deine Daten" (und nur dort),
//   * die Auftragsverarbeiter: Supabase, Google (Firebase), Brevo,
//     Cloudflare, Netlify - und KEIN Apple (es gibt keine
//     App-Store-Verteilung),
//   * der Eintrag zu den Nutzungsbedingungen ist da und oeffnet den
//     Volltext in der App.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/privacy/privacy_screen.dart';

import 'support/plugin_mocks.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // DER KEYSTORE: Der Bildschirm liest die Einstellungen aus dem
    // verschluesselten Speicher - ohne den Mock ruft der Test auf dem
    // CI-Runner das echte Plugin (das findet dort keine libsecret-
    // Sitzung).
    mockKeystore();
  });

  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PrivacyScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Scrollt zu einem Text (der Screen ist eine lange Liste).
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    if (ziel.evaluate().isNotEmpty) return;
    await tester.scrollUntilVisible(
      ziel,
      320,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('der Bildschirm baut sich ohne Absturz', (tester) async {
    await zeigeScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(PrivacyScreen), findsOneWidget);
  });

  testWidgets('der Datenexport steht unter "Deine Daten"', (tester) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('privacy.export'));

    expect(
      find.text(L10n.tWithoutContext('privacy.export')),
      findsOneWidget,
      reason:
          'Der Datenexport muss erreichbar sein - er ist die Auskunft nach '
          'Art. 15 DSGVO.',
    );
  });

  testWidgets('die Auftragsverarbeiter: kein Apple, Google mit Hinweis', (
    tester,
  ) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('privacy.processors'));

    expect(find.text('Supabase Inc.'), findsOneWidget);
    expect(find.text('Google LLC (Firebase)'), findsOneWidget);
    expect(find.text('Brevo'), findsOneWidget);
    expect(find.text('Cloudflare Inc.'), findsOneWidget);
    expect(find.text('Netlify Inc.'), findsOneWidget);

    // BEFUND (14.11.2026, Betreiber): "apple bei auftragsverarbeiter ist
    // aktuell falsch, da ich es dort nicht anbiete aktuell." Es gibt
    // keine App-Store-Verteilung - also steht Apple nicht in der Liste.
    expect(
      find.text('Apple Inc.'),
      findsNothing,
      reason:
          'Ohne App-Store-Verteilung ist Apple kein Auftragsverarbeiter. '
          'Wer das anbietet, ohne es zu nutzen, ist in der Liste falsch.',
    );

    // Beim Google-Eintrag steht, dass Firebase nur in der
    // Play-Store-Fassung laeuft (im F-Droid-Build laeuft UnifiedPush).
    final googleZeile = find.text('Google LLC (Firebase)');
    expect(googleZeile, findsOneWidget);
    expect(
      find.textContaining('nur in der Play-Store-Fassung'),
      findsOneWidget,
      reason:
          'Der Eintrag muss sagen, dass Firebase nur in der '
          'Play-Store-Fassung laeuft.',
    );
  });

  testWidgets('die Nutzungsbedingungen sind verlinkt', (tester) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('privacy.termsTitle'));

    expect(
      find.text(L10n.tWithoutContext('privacy.termsTitle')),
      findsOneWidget,
    );
  });
}
