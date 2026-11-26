// Die Anmeldung (bisher kaum getestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte für
// lib/screens/auth/login_screen.dart 379 offene Zeilen.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * im Anmelde-Modus gibt es E-Mail und Passwort (aber kein Namens-
//     feld - das kommt erst mit der Registrierung dazu),
//   * das Passwort ist verdeckt und lässt sich zeigen,
//   * der Wechsel zur Registrierung zeigt die Zusatzfelder (Name,
//     Geburtsdatum, Geschlecht) und die Alters-Bestätigung.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/auth/login_screen.dart';

import '../support/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    // DER SPEICHER DES GERÄTS: der Auth-Client holt sich daraus die
    // Sitzung - ohne den Mock schlägt der Aufbau fehl.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Scrollt, bis das Passwort-Feld gebaut ist (die Liste baut nur die
  /// sichtbaren Einträge).
  Future<void> scrolleZumPasswort(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      final felder = tester.widgetList<TextField>(find.byType(TextField));
      if (felder.any((f) => f.obscureText)) return;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('der Bildschirm baut sich ohne Absturz', (tester) async {
    await zeigeScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('im Anmelde-Modus gibt es E-Mail und Passwort', (tester) async {
    await zeigeScreen(tester);

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text(L10n.tWithoutContext('auth.email')), findsWidgets);
    expect(find.text(L10n.tWithoutContext('auth.password')), findsWidgets);
    // Das Namensfeld gibt es erst mit der Registrierung.
    expect(find.text(L10n.tWithoutContext('auth.name')), findsNothing);
  });

  testWidgets('das Passwort laesst sich zeigen und wieder verbergen', (
    tester,
  ) async {
    await zeigeScreen(tester);
    await scrolleZumPasswort(tester);

    // Das Auge zeigt an, dass das Passwort gerade verdeckt ist.
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Nach dem Tipp ist das Passwort lesbar - und das Icon dreht sich.
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNothing);
  });

  testWidgets('die Registrierung zeigt die Zusatzfelder', (tester) async {
    await zeigeScreen(tester);

    // Auf "Konto erstellen" umschalten.
    await tester.tap(find.text(L10n.tWithoutContext('auth.toRegister')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    // Der Name, das Geburtsdatum, das Geschlecht ...
    expect(find.text(L10n.tWithoutContext('auth.name')), findsWidgets);
    expect(find.text(L10n.tWithoutContext('auth.birthDate')), findsWidgets);
    expect(find.text(L10n.tWithoutContext('auth.gender')), findsWidgets);
    // ... und die Alters-Bestätigung (Jugendschutz).
    expect(
      find.text(L10n.tWithoutContext('auth.ageConfirmTitle')),
      findsWidgets,
      reason:
          'Bei der Registrierung muss das Alter bestaetigt werden - '
          'das ist der Jugendschutz.',
    );
  });
}
