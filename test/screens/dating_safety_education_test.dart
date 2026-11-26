// Die Sicherheits-Aufklärung nach der E-Mail-Bestätigung.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/screens/onboarding/dating_safety_education_screen.dart 66 offene
// Zeilen. Der Screen ist die Pflichtstation vor dem Setup - er muss
// den Nutzer durch die Aufklärung führen, den Fortschritt merken und
// nach fünf Minuten Schluss machen.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Bestätigungsseite steht da,
//   * wer schon eine Dating-App benutzt hat, kommt zur zweiten Frage,
//   * wer keine benutzt hat, bekommt die fünfseitige Aufklärung,
//   * die Aufklärung hat fünf Seiten (und am Ende geht es weiter),
//   * der Fortschritt wird gespeichert und beim nächsten Mal
//     wiederhergestellt,
//   * ein kaputter Fortschritt startet von vorn (und wird entfernt),
//   * nach fünf Minuten ist Schluss (die Uhr läuft auch nach einem
//     Neustart weiter),
//   * der Abschluss wird gemerkt (der Router erzwingt die Aufklärung
//     danach nie wieder).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/onboarding/dating_safety_education_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/router_harness.dart';

/// Der Schlüssel, unter dem der Fortschritt liegt.
const String _fortschrittKey = 'dating_safety_education_v1';

void main() {
  /// Der Speicher (enthält auch die Einstellungen).
  late TestSpeicher speicher;

  /// Der Container (für die Einstellungen).
  late ProviderContainer container;

  /// Baut den Screen.
  ///
  /// [fortschritt] legt einen gespeicherten Fortschritt in den Speicher
  /// (so testet man das Wiederherstellen).
  Future<void> zeigeScreen(WidgetTester tester, {String? fortschritt}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    speicher = TestSpeicher();
    if (fortschritt != null) {
      await speicher.saveString(_fortschrittKey, fortschritt);
    }

    container = ProviderContainer(
      overrides: <Override>[localStorageProvider.overrideWithValue(speicher)],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: AppRoutes.datingSafetyEducation,
      routes: [
        GoRoute(
          path: AppRoutes.datingSafetyEducation,
          builder: (context, state) => const DatingSafetyEducationScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('SEITE-HOME'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // DER SCREEN WIRD ABGEBAUT: Die Aufkläung hat eine laufende Uhr -
    // ohne das bleibt ein Timer am Ende des Tests stehen.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  group('Die Bestaetigung', () {
    testWidgets('die Bestaetigungsseite steht da', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackTitle')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackButton')),
        findsOneWidget,
      );
    });

    testWidgets('der Schritt wird gespeichert', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackButton')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final roh = await speicher.getString(_fortschrittKey);
      expect(roh, isNotNull);
      final stand = jsonDecode(roh!) as Map<String, dynamic>;
      expect(
        stand['step'],
        'usedBefore',
        reason:
            'Der Fortschritt muss gespeichert sein - sonst beginnt die '
            'Aufklaeung nach einem Neustart wieder von vorn.',
      );
    });
  });

  group('Die Fragen', () {
    testWidgets('wer schon eine App benutzt hat, kommt zur zweiten Frage', (
      tester,
    ) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackButton')),
      );
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('safetyOnboarding.yes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.q2Title')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.q1Title')),
        findsNothing,
      );
    });

    testWidgets('wer keine App benutzt hat, bekommt die Aufklaeung', (
      tester,
    ) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackButton')),
      );
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('safetyOnboarding.no')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.educationTitle')),
        findsOneWidget,
      );
      expect(
        find.text(
          L10n.tWithoutContext(
            'safetyOnboarding.progress',
          ).replaceAll('{current}', '1').replaceAll('{total}', '5'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('von der zweiten Frage geht es zurueck', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackButton')),
      );
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('safetyOnboarding.yes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.back')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.q1Title')),
        findsOneWidget,
        reason:
            'Der Nutzer muss zurueck koennen - sonst kann er eine falsche '
            'Antwort nicht korrigieren.',
      );
    });

    testWidgets('wer die Gefahren kennt, kommt zum Setup', (tester) async {
      await zeigeScreen(tester);

      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackButton')),
      );
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('safetyOnboarding.yes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(L10n.tWithoutContext('safetyOnboarding.yes')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-HOME'), findsOneWidget);
      expect(
        container.read(settingsProvider).datingSafetyEducationCompleted,
        isTrue,
        reason:
            'Der Abschluss wird gemerkt - sonst muesste der Nutzer die '
            'Aufklaerung bei jedem Start erneut lesen.',
      );
    });
  });

  group('Die Aufklaeung', () {
    /// Startet die Aufklärung (Antwort: "Nein" auf die erste Frage).
    Future<void> starteAufklaeung(WidgetTester tester) async {
      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackButton')),
      );
      await tester.pump();
      await tester.tap(find.text(L10n.tWithoutContext('safetyOnboarding.no')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('sie hat fuenf Seiten', (tester) async {
      await zeigeScreen(tester);
      await starteAufklaeung(tester);

      for (var seite = 2; seite <= 5; seite++) {
        await tester.tap(
          find.text(L10n.tWithoutContext('safetyOnboarding.next')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text(
            L10n.tWithoutContext(
              'safetyOnboarding.progress',
            ).replaceAll('{current}', '$seite').replaceAll('{total}', '5'),
          ),
          findsOneWidget,
          reason: 'Die Seite $seite muss zu sehen sein.',
        );
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.finish')),
        findsOneWidget,
        reason: 'Auf der letzten Seite steht "Fertig".',
      );
    });

    testWidgets('auf der letzten Seite geht es weiter', (tester) async {
      await zeigeScreen(tester);
      await starteAufklaeung(tester);

      for (var i = 0; i < 4; i++) {
        await tester.tap(
          find.text(L10n.tWithoutContext('safetyOnboarding.next')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.finish')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text('SEITE-HOME'), findsOneWidget);
    });

    testWidgets('die ausfuehrliche Fassung laesst sich oeffnen', (
      tester,
    ) async {
      await zeigeScreen(tester);
      await starteAufklaeung(tester);

      // Der Browser lässt sich im Test nicht öffnen - der Weg darf
      // daran aber nicht scheitern (die Aufkläung läuft weiter).
      await tester.tap(
        find.text(L10n.tWithoutContext('safetyOnboarding.moreInfo')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.educationTitle')),
        findsOneWidget,
      );
    });
  });

  group('Der Fortschritt', () {
    testWidgets('ein gespeicherter Fortschritt wird wiederhergestellt', (
      tester,
    ) async {
      await zeigeScreen(
        tester,
        fortschritt: jsonEncode(<String, dynamic>{
          'version': 1,
          'step': 'education',
          'page': 2,
          'startedAtMs': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(
          L10n.tWithoutContext(
            'safetyOnboarding.progress',
          ).replaceAll('{current}', '3').replaceAll('{total}', '5'),
        ),
        findsOneWidget,
        reason:
            'Der Nutzer soll dort weitermachen, wo er aufgehoert hat - '
            'nicht wieder bei Seite 1.',
      );
    });

    testWidgets('ein kaputter Fortschritt startet von vorn', (tester) async {
      await zeigeScreen(tester, fortschritt: 'kein json');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('safetyOnboarding.ackTitle')),
        findsOneWidget,
      );
      expect(
        await speicher.getString(_fortschrittKey),
        isNull,
        reason:
            'Der kaputte Eintrag wird entfernt - sonst scheitert die '
            'Wiederherstellung bei jedem Start erneut.',
      );
    });

    testWidgets('nach fuenf Minuten ist Schluss', (tester) async {
      // DIE UHR IST ABGELAUFEN: Der Fortschritt liegt sechs Minuten
      // zurück - die Aufklärung ist damit vorbei.
      await zeigeScreen(
        tester,
        fortschritt: jsonEncode(<String, dynamic>{
          'version': 1,
          'step': 'education',
          'page': 1,
          'startedAtMs': DateTime.now().millisecondsSinceEpoch - 6 * 60 * 1000,
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text('SEITE-HOME'),
        findsOneWidget,
        reason:
            'Die Aufklaerung dauert hoechstens fuenf Minuten - danach geht '
            'es weiter, auch wenn der Nutzer sie nicht fertig gelesen hat.',
      );
    });
  });
}
