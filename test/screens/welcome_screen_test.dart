// Der Willkommens-Screen (die Einfuehrung) - bisher ungetestet (1,2 %).
//
// ANLASS (18.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/welcome/welcome_screen.dart 82 offene Zeilen bei 83 Zeilen
// gesamt. Der Screen erklaert das Grundprinzip der App - und markiert
// die Einfuehrung als gesehen (der Flag darf danach nie wieder kommen).
//
// WAS HIER GEPRUEFT WIRD:
//   * die drei Seiten stehen da (mit Text, nicht nur mit Logo),
//   * die Einfuehrung gilt ab dem ANZEIGEN als gesehen (sonst sieht der
//     Nutzer sie nach jedem Neustart wieder),
//   * "Weiter" blattert, "Zurueck" geht zurueck,
//   * am Ende und beim Ueberspringen kommt der Login.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/welcome/welcome_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

/// Der Speicher im RAM.
class _Speicher implements LocalStorage {
  final Map<String, String> _daten = <String, String>{};

  @override
  Future<void> saveString(String key, String value) async =>
      _daten[key] = value;

  @override
  Future<String?> getString(String key) async => _daten[key];

  @override
  Future<void> saveBool(String key, bool value) async =>
      _daten[key] = value.toString();

  @override
  Future<bool?> getBool(String key) async =>
      _daten[key] == null ? null : _daten[key] == 'true';

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);

  @override
  Future<void> remove(String key) async => _daten.remove(key);
}

void main() {
  /// Der Speicher (dort steht der Flag "Einfuehrung gesehen").
  late _Speicher speicher;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    speicher = _Speicher();
  });

  /// Baut den Screen.
  Future<void> zeigeScreen(WidgetTester tester) async {
    // DER TESTRAHMEN: 1200 px hoch. Die Testschrift (Ahem) ist rund
    // 1,7-mal breiter als Roboto - der lange Erklaerungstext laeuft
    // sonst ueber den Rand. Das ist ein Artefakt der Testschrift, kein
    // Fehler des Bildschirms (mit der echten Schrift passt es).
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: AppRoutes.welcome,
      routes: [
        GoRoute(
          path: AppRoutes.welcome,
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Anmeldung'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[localStorageProvider.overrideWithValue(speicher)],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    // DAS LOGO: Das Bild wird von der Platte gelesen - das braucht die
    // echte Schleife (mit der Test-Uhr wuerde der Bildschirm leer
    // bleiben).
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Der Willkommens-Screen', () {
    testWidgets('die erste Seite steht da', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('welcome.t1')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('welcome.b1')), findsOneWidget);
      // Das Ueberspringen steht oben.
      expect(find.text(L10n.tWithoutContext('common.skip')), findsOneWidget);
      // Und es geht erst mit "Weiter" weiter.
      expect(
        find.text(L10n.tWithoutContext('common.continue')),
        findsOneWidget,
      );
    });

    testWidgets('die Einfuehrung gilt als gesehen, sobald sie erscheint', (
      tester,
    ) async {
      await zeigeScreen(tester);

      // DER FLAG: Er wird beim ANZEIGEN gesetzt - sonst sieht der
      // Nutzer die Einfuehrung nach jedem Neustart wieder.
      expect(
        speicher._daten.values.any((v) => v.contains('introSeen')),
        isTrue,
        reason:
            'Die Einfuehrung muss als gesehen gemerkt werden - sonst '
            'erscheint sie nach jedem Neustart wieder.',
      );
    });

    testWidgets('"Weiter" blaettert weiter', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(find.text(L10n.tWithoutContext('common.continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('welcome.t2')), findsOneWidget);
      // Und jetzt gibt es ein "Zurueck".
      expect(find.text(L10n.tWithoutContext('common.back')), findsOneWidget);
    });

    testWidgets('am Ende geht es zum Login', (tester) async {
      await zeigeScreen(tester);

      // Zweite Seite.
      await tester.tap(find.text(L10n.tWithoutContext('common.continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Dritte Seite (die letzte).
      await tester.tap(find.text(L10n.tWithoutContext('common.continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('welcome.start')), findsOneWidget);

      await tester.tap(find.text(L10n.tWithoutContext('welcome.start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Anmeldung'), findsOneWidget);
    });

    testWidgets('das Ueberspringen geht auch zum Login', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(find.text(L10n.tWithoutContext('common.skip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Anmeldung'), findsOneWidget);
    });
  });
}
