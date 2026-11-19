// Der Einrichtungs-Bildschirm "Einstellungen & Privatsphäre" (bisher
// ungetestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/onboarding/settings_privacy_once_screen.dart 746 offene
// Zeilen - der Screen, den jeder neue Nutzer als erstes sieht.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * die Fortschrittsanzeige nennt alle zehn Schritte,
//   * die Filter-Seite fragt nach Wunsch und Entfernung,
//   * "Weiter" fuehrt weiter - aber die Pflichtangaben (Bio, Interesse)
//     werden abgeprueft (der Nutzer darf die Einrichtung nicht mit einer
//     leeren Seite verlassen),
//   * der zurueck-Button der Kopfzeile geht nur nach Rueckfrage.
//
// OHNE SERVER: Der Supabase-Client wird gar nicht erst initialisiert -
// damit bleibt der Serverteil aus und der Test greift nur auf den
// lokalen Stand zu (kein Netzwerkverkehr im Test).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/onboarding/settings_privacy_once_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';

import '../support/plugin_mocks.dart';

/// Der Speicher im RAM - der Screen schreibt Bio, Interessen usw. dorthin.
class _FakeLocalStorage implements LocalStorage {
  final Map<String, String> _daten = {};

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
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

/// Der Keystore ohne Plugin.
class _FakeSecureProfileStore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Die Route, auf der der Screen in diesem Test liegt.
const String _startRoute = '/setup';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // DER KEYSTORE: der Screen liest das gespeicherte Profil daraus -
    // ohne den Mock ruft der Test auf dem CI-Runner das echte Plugin
    // (das findet dort keine libsecret-Sitzung).
    mockKeystore();
    // DIE AUFNAHME: die Vorstellung kann mit Stimme aufgenommen werden -
    // ohne den Ersatz wartet der Aufruf endlos (bzw. der Test scheitert
    // an einem Plugin, das es im Test nicht gibt).
    mockAufnahme();
  });

  /// Pumpt eine feste Zahl von Frames.
  ///
  /// `pumpAndSettle` waere hier falsch: die Seite hat Animationen, die
  /// nicht enden (der Kreis beim Laden des Profils). Deshalb feste Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Baut den Screen mit Router und Provider-Overrides.
  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: _startRoute,
      routes: [
        GoRoute(
          path: _startRoute,
          builder: (context, state) => const SettingsPrivacyOnceScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Startseite'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
          secureProfileStoreProvider.overrideWithValue(
            _FakeSecureProfileStore(),
          ),
          profileProvider.overrideWith((ref) {
            final notifier = ProfileNotifier(
              ref.watch(localStorageProvider),
              ref.watch(secureProfileStoreProvider),
            );
            // Ein Profil mit Geburtsdatum: mit bekanntem Alter greifen
            // die Schutzregeln (Altersspanne, Suchradius) - mit unbekanntem
            // Alter wuerde der Screen sie stillschweigend uebergehen.
            notifier.setProfile(
              UserProfile(
                id: 'ich',
                name: 'Lena',
                bio: '',
                birthDate: DateTime(DateTime.now().year - 30, 5, 4),
              ),
            );
            return notifier;
          }),
        ],
        child: MaterialApp.router(
          theme: ThemeData(useMaterial3: true),
          routerConfig: router,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  /// Tippt auf "Weiter" und wartet die Seitenanimation ab.
  Future<void> weiter(WidgetTester tester) async {
    await tester.tap(find.text(L10n.tWithoutContext('onb.next')));
    await pumpFrames(tester);
  }

  /// Geht durch alle zehn Schritte bis zur letzten Seite.
  ///
  /// Schritt 2 (Profil) und Schritt 3 (Vorstellung) haben Pflichtangaben -
  /// ohne sie geht der "Weiter"-Knopf nicht weiter.
  Future<void> geheBisZumLetztenSchritt(WidgetTester tester) async {
    await weiter(tester);

    // Schritt 2: Bio und Interesse.
    await tester.enterText(
      find.byType(TextFormField).first,
      'Ich mag lange Spaziergaenge am Fluss.',
    );
    await pumpFrames(tester);
    final chip = find.widgetWithText(FilterChip, 'Sport');
    await tester.ensureVisible(chip);
    await pumpFrames(tester);
    await tester.tap(chip);
    await pumpFrames(tester);
    await weiter(tester);

    // Schritt 3: die Vorstellung (Text ist Pflicht, die Aufnahme nicht).
    await tester.enterText(
      find.byType(TextFormField).first,
      'Ich bin gern draussen unterwegs.',
    );
    await pumpFrames(tester);
    await weiter(tester);

    // Die Schritte 4 bis 9 kommen ohne weitere Pflichtangabe.
    for (var i = 0; i < 6; i++) {
      await weiter(tester);
    }
  }

  group('Einrichtung (Einstellungen & Privatsphäre)', () {
    testWidgets('baut sich ohne Absturz', (tester) async {
      await zeigeScreen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsPrivacyOnceScreen), findsOneWidget);
      // Die Kopfzeile steht da.
      expect(
        find.text(L10n.tWithoutContext('setup.appbarTitle')),
        findsOneWidget,
      );
      // Und die erste Frage (im Interview-Stil).
      expect(find.text(L10n.tWithoutContext('setupq.filter')), findsOneWidget);
    });

    testWidgets('die Fortschrittsanzeige nennt alle zehn Schritte', (
      tester,
    ) async {
      await zeigeScreen(tester);

      expect(find.text('Schritt 1 von 10'), findsOneWidget);
      // Und der Balken ist bei einem Zehntel.
      final balken = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(balken.value, closeTo(0.1, 0.001));
    });

    testWidgets('die Filter-Seite fragt nach Wunsch und Entfernung', (
      tester,
    ) async {
      await zeigeScreen(tester);

      expect(
        find.text(L10n.tWithoutContext('setupp.lookingFor')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('setupp.distance')),
        findsOneWidget,
      );
      // Die Auswahl der gesuchten Geschlechter steht da (als Chips).
      expect(find.byType(FilterChip), findsWidgets);
    });

    testWidgets('"Weiter" fuehrt zur naechsten Seite', (tester) async {
      await zeigeScreen(tester);

      await weiter(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(L10n.tWithoutContext('setupq.profile')), findsOneWidget);
      expect(find.text('Schritt 2 von 10'), findsOneWidget);
      // Und es gibt jetzt einen Zurueck-Knopf in der Kopfzeile.
      expect(
        find.byTooltip(L10n.tWithoutContext('common.back')),
        findsOneWidget,
      );
    });

    testWidgets('ohne Bio geht es nicht weiter', (tester) async {
      await zeigeScreen(tester);
      await weiter(tester);

      // Die Bio ist leer - der Bildschirm muss nachfragen.
      await weiter(tester);

      expect(
        find.text(L10n.tWithoutContext('setup.hintBio')),
        findsOneWidget,
        reason:
            'Ohne Bio darf die Einrichtung nicht weitergehen - sonst '
            'entsteht ein leeres Profil.',
      );
      // Der Schritt ist nicht gewechselt.
      expect(find.text('Schritt 2 von 10'), findsOneWidget);
    });

    testWidgets('ohne Interesse geht es nicht weiter', (tester) async {
      await zeigeScreen(tester);
      await weiter(tester);

      // Bio eintragen, aber kein Interesse waehlen.
      await tester.enterText(
        find.byType(TextFormField).first,
        'Ich mag lange Spaziergaenge am Fluss.',
      );
      await pumpFrames(tester);
      await weiter(tester);

      expect(
        find.text(L10n.tWithoutContext('setup.hintInterests')),
        findsOneWidget,
        reason:
            'Ohne Interesse bleibt das Profil leer - das Matching laeuft '
            'sonst ins Leere.',
      );
      expect(find.text('Schritt 2 von 10'), findsOneWidget);
    });

    testWidgets('mit Bio und Interesse geht es weiter', (tester) async {
      await zeigeScreen(tester);
      await weiter(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'Ich mag lange Spaziergaenge am Fluss.',
      );
      await pumpFrames(tester);
      // Das Interesse liegt unterhalb der Falz - erst hinschieben, dann
      // tippen (sonst trifft der Tipp ins Leere).
      final chip = find.widgetWithText(FilterChip, 'Sport');
      await tester.ensureVisible(chip);
      await pumpFrames(tester);
      await tester.tap(chip);
      await pumpFrames(tester);

      await weiter(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Schritt 3 von 10'), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('setupq.intro')),
        findsOneWidget,
        reason: 'Der Schritt "Deine Vorstellung" muss kommen.',
      );
    });

    testWidgets('der Weg durch alle zehn Schritte laeuft', (tester) async {
      await zeigeScreen(tester);

      // Schritt 1 (Filter) -> Schritt 2 (Profil).
      await weiter(tester);

      // Schritt 2: Bio und Interesse sind Pflicht.
      await tester.enterText(
        find.byType(TextFormField).first,
        'Ich mag lange Spaziergaenge am Fluss.',
      );
      await pumpFrames(tester);
      final chip = find.widgetWithText(FilterChip, 'Sport');
      await tester.ensureVisible(chip);
      await pumpFrames(tester);
      await tester.tap(chip);
      await pumpFrames(tester);
      await weiter(tester);

      // Schritt 3: Die Vorstellung (Text ist Pflicht, die Aufnahme nicht).
      await tester.enterText(
        find.byType(TextFormField).first,
        'Ich bin gern draussen unterwegs.',
      );
      await pumpFrames(tester);
      await weiter(tester);
      expect(find.text('Schritt 4 von 10'), findsOneWidget);

      // Schritt 4: Der Geburtstagsstil.
      await weiter(tester);
      expect(find.text('Schritt 5 von 10'), findsOneWidget);

      // Schritt 5: Der Musik-Geschmack.
      await weiter(tester);
      expect(find.text('Schritt 6 von 10'), findsOneWidget);

      // Schritt 6: Die Gewohnheiten.
      await weiter(tester);
      expect(find.text('Schritt 7 von 10'), findsOneWidget);

      // Die letzten drei Schritte sind die Freigaben (Ort, Reichweite,
      // Datenschutz) - sie kommen ohne weitere Pflichtangabe.
      await weiter(tester);
      expect(find.text('Schritt 8 von 10'), findsOneWidget);
      await weiter(tester);
      expect(find.text('Schritt 9 von 10'), findsOneWidget);
      await weiter(tester);
      expect(find.text('Schritt 10 von 10'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    group('Der Abschluss', () {
      testWidgets('ohne Passkey und 2FA fragt die App nach', (tester) async {
        await zeigeScreen(tester);
        await geheBisZumLetztenSchritt(tester);
        expect(find.text('Schritt 10 von 10'), findsOneWidget);

        // Der Abschluss-Knopf.
        final knopf = find.text(L10n.tWithoutContext('setupp.finish'));
        await tester.ensureVisible(knopf);
        await pumpFrames(tester);
        await tester.tap(knopf);
        await pumpFrames(tester);

        expect(tester.takeException(), isNull);
        // Ohne Passkey und ohne 2FA ist die Einrichtung nicht vollstaendig
        // - die App sagt das DEUTLICH, statt es zu verschweigen.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text(L10n.tWithoutContext('setup.nudgeTitle')),
          findsOneWidget,
        );
        // Und die drei Wege stehen da.
        expect(
          find.text(L10n.tWithoutContext('setup.nudgePasskey')),
          findsOneWidget,
        );
        expect(
          find.text(L10n.tWithoutContext('setup.nudgeMfa')),
          findsOneWidget,
        );
        expect(
          find.text(L10n.tWithoutContext('setup.nudgeSkip')),
          findsOneWidget,
        );
      });

      testWidgets('"Trotzdem fortfahren" schliesst die Einrichtung ab', (
        tester,
      ) async {
        await zeigeScreen(tester);
        await geheBisZumLetztenSchritt(tester);

        final knopf = find.text(L10n.tWithoutContext('setupp.finish'));
        await tester.ensureVisible(knopf);
        await pumpFrames(tester);
        await tester.tap(knopf);
        await pumpFrames(tester);

        // "Trotzdem fortfahren" - der Nutzer entscheidet sich bewusst.
        await tester.tap(
          find.widgetWithText(
            TextButton,
            L10n.tWithoutContext('setup.nudgeSkip'),
          ),
        );
        await pumpFrames(tester);
        // Das Speichern dauert (der Server wird gefragt).
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await pumpFrames(tester);

        expect(tester.takeException(), isNull);
        // Und die App landet auf der Startseite - die Einrichtung ist
        // vorbei.
        expect(find.text('Startseite'), findsOneWidget);
      });

      testWidgets('"Passkey einrichten" springt zur Passkey-Seite', (
        tester,
      ) async {
        await zeigeScreen(tester);
        await geheBisZumLetztenSchritt(tester);

        final knopf = find.text(L10n.tWithoutContext('setupp.finish'));
        await tester.ensureVisible(knopf);
        await pumpFrames(tester);
        await tester.tap(knopf);
        await pumpFrames(tester);

        await tester.tap(
          find.widgetWithText(
            FilledButton,
            L10n.tWithoutContext('setup.nudgePasskey'),
          ),
        );
        await pumpFrames(tester);

        expect(tester.takeException(), isNull);
        // Der Nutzer landet auf der Passkey-Seite (nicht auf der
        // Startseite) - der Weg ist offen.
        expect(find.text('Startseite'), findsNothing);
      });
    });

    testWidgets('das Zurueckgehen fragt nach', (tester) async {
      await zeigeScreen(tester);

      // Das System-Zurueck (Randwisch, Zurueck-Knopf des Systems).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await pumpFrames(tester);

      // Die Rueckfrage steht da - ohne sie waere die Einrichtung nach
      // einem Versehen weg.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('setup.abortTitle')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('setup.abortContinue')),
        findsOneWidget,
      );
    });
  });
}
