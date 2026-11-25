// Die Einstellungen: die Schalter, die Dialoge und das Konto.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/settings/settings_screen.dart 64 offene Zeilen - die
// Schalter, die Dialoge und die Versionsangabe.
//
// DER WEG: Der Bildschirm ist eine lange Liste - der Test benutzt einen
// hohen Bildschirm (3000 px), damit alle Eintraege auf einmal gebaut
// werden. Das VerschlÃƒÂ¼sselungs-Dienst und die Versionsangaben bekommen
// ihre Ersatzteile.
//
// WAS HIER GEPRUEFT WIRD:
//   * die einzelnen Schalter werden wirklich gespeichert (nicht nur
//     angezeigt),
//   * das Erscheinungsbild und die Farbe lassen sich umstellen,
//   * die Versionsangabe steht da (der Support braucht sie),
//   * die Dialoge lassen sich abbrechen - und ein Scheitern wird
//     gemeldet, nicht verschwiegen,
//   * das LÃƒÂ¶schen des Kontos fragt erst nach,
//   * der Zwei-Faktor-Stand steht an der Kachel.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/profile/user_profile.dart';
import 'package:thestia/providers/profile/profile_provider.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/routing/app_router.dart';
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/auth/mfa_service.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/storage/local_storage.dart';
import 'package:thestia/services/storage/secure_storage.dart';
import 'package:thestia/widgets/settings/theme_picker.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM - die Einstellungen werden daraus gelesen.
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
  Future<void> remove(String key) async => _daten.remove(key);

  @override
  Future<void> saveInt(String key, int value) async =>
      _daten[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _daten[key] == null ? null : int.tryParse(_daten[key]!);
}

/// Der Keystore ohne Plugin.
class _Keystore extends SecureProfileStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

/// Der Verschluesselungs-Dienst fuer den Test.
///
/// DER GRUND: Der echte Dienst braucht die verschluesselten Hive-Boxen -
/// im Test waere das der Weg ueber die Schluesselverwaltung. Fuer die
/// Oberflaeche reicht der Code: der Dialog muss ihn anzeigen und das
/// Kopieren anbieten.
class _Verschluesselung extends EncryptionService {
  _Verschluesselung({this.scheitert = false});

  /// Liefert der Dienst keinen Code (der Fehlerfall)?
  bool scheitert;

  @override
  Future<String?> createEncryptedBackup(String password) async {
    if (scheitert) return null;
    return 'TEST_BACKUP_CODE_1234';
  }
}

void main() {
  late _Speicher speicher;
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // DIE VERSIONSANGABEN: Ohne den Ersatz wartet der Aufruf im Test
    // endlos - der Bildschirm bleibt beim Lade-Spinner.
    mockPackageInfo(version: '0.10.2', build: '58');
    // DIE VERSIONSANGABE VORAB: Der Bildschirm fragt sie ueber den
    // Plattform-Kanal ab. Holt man sie erst beim Aufbau, kommt die
    // Antwort im Test erst danach - und die Versionszeile fehlt.
    await PackageInfo.fromPlatform();
    // HIVE: der Abschnitt "Ende-zu-Ende-Verschluesselung" liest die
    // gesicherten Schluessel aus einer Hive-Box.
    final tempDir = await Directory.systemTemp.createTemp('thesia_settings2');
    Hive.init(tempDir.path);

    final server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    speicher = _Speicher();
  });

  tearDown(() {
    container.dispose();
  });

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Baut den Einstellungs-Bildschirm.
  ///
  /// [mitRouter] baut ihn in einem Router mit einer Startseite - so
  /// laesst sich der Zurueck-Knopf pruefen.
  Future<ProviderContainer> zeigeScreen(
    WidgetTester tester, {
    bool mitRouter = false,
    _Verschluesselung? verschluesselung,
    MfaStatus? mfa,
  }) async {
    // GROSSER Bildschirm: der Abschnitt "Ende-zu-Ende-Verschluesselung"
    // liegt weit unten. Mit einem hohen Bildschirm baut die Liste mehr
    // Eintraege auf einmal - das Scrollen durch die lange Liste waere
    // im Test zaeh und fehleranfaellig.
    await tester.binding.setSurfaceSize(const Size(390, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final secure = _Keystore();
    container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(speicher),
        secureProfileStoreProvider.overrideWithValue(secure),
        encryptionServiceProvider.overrideWithValue(
          verschluesselung ?? _Verschluesselung(),
        ),
        if (mfa != null) mfaStatusProvider.overrideWith((ref) => mfa),
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(speicher, secure);
          notifier.setProfile(
            const UserProfile(id: 'ich', name: 'Lena', bio: ''),
          );
          return notifier;
        }),
      ],
    );

    if (mitRouter) {
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => context.push(AppRoutes.settings),
                  child: const Text('Startseite'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.login,
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Login'))),
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
      await tester.pump(const Duration(milliseconds: 400));
      // DER WEG ZU DEN EINSTELLUNGEN:
      await tester.tap(find.text('Startseite'));
      await pumpFrames(tester);
      return container;
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  /// Scrollt zu einem Text (die Liste baut nur die sichtbaren Eintraege).
  ///
  /// DER HINWEIS: "timedDrag" statt "drag". Ein einfacher Zug kommt
  /// erstaunlich wenig weiter - bei ueber 7000 Pixel Liste waere der
  /// Eintrag am Ende nie erreicht worden.
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    for (var i = 0; i < 60 && ziel.evaluate().isEmpty; i++) {
      await tester.timedDrag(
        find.byType(Scrollable).first,
        const Offset(0, -300),
        const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Wartet, bis der entprellte Server-Sync der UI-Einstellungen durch ist.
  ///
  /// DER HINWEIS: Das Schreiben zum Server ist entprellt (1,5 s). Ohne
  /// diese Wartezeit bleibt am Ende des Tests ein Timer uebrig - der
  /// Test waere dann rot, obwohl die App richtig arbeitet.
  Future<void> warteAufSync(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1600));
    await pumpFrames(tester);
  }

  /// Tippt auf einen Schalter (an seinem Titel).
  Future<void> tippeSchalter(WidgetTester tester, String titel) async {
    await scrolleZu(tester, titel);
    final schalter = find.ancestor(
      of: find.text(titel),
      matching: find.byType(SwitchListTile),
    );
    expect(
      schalter,
      findsOneWidget,
      reason: 'Der Schalter $titel muss da sein.',
    );
    await tester.ensureVisible(schalter);
    await tester.pump();
    // DER SCHALTER SELBST: Der Titel kann am Rand liegen - der Schalter
    // ist das sichere Tippziel.
    final knopf = find.descendant(of: schalter, matching: find.byType(Switch));
    expect(knopf, findsOneWidget, reason: 'Der Schalter $titel muss da sein.');
    await tester.tap(knopf);
    await pumpFrames(tester);
    await warteAufSync(tester);
  }

  /// Oeffnet den Backup-Dialog (das Backup der Ende-zu-Ende-Identitaet).
  Future<void> oeffneBackupDialog(WidgetTester tester) async {
    await scrolleZu(tester, L10n.tWithoutContext('settings.keyBackup'));
    final knopf = find.byIcon(Icons.download_outlined);
    expect(knopf, findsOneWidget, reason: 'Der Backup-Knopf muss da sein.');
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await pumpFrames(tester);
  }

  /// Fuellt das Passwort (zweimal) und bestaetigt den Dialog.
  Future<void> backupErstellen(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).first,
      'ein-sehr-langes-passwort',
    );
    await tester.enterText(
      find.byType(TextFormField).last,
      'ein-sehr-langes-passwort',
    );
    await pumpFrames(tester);
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        L10n.tWithoutContext('settings.backupCreateBtn'),
      ),
    );
    await pumpFrames(tester);
  }

  // DIESE GRUPPE STEHT VORN (25.11.2026): Die Versionsangaben kommen
  // ueber den Plattform-Kanal - die Antwort kommt erst nach dem
  // Bildaufbau. Der Bildschirm fragt sie nur EINMAL (der Wert aendert
  // sich waehrend der Sitzung nicht). Steht dieser Test nicht an
  // erster Stelle, ist die Abfrage schon im ersten Test gelaufen und
  // die Antwort kommt dann nicht mehr an.
  group('Die Versionsangabe', () {
    testWidgets('die Version und der Build stehen da', (tester) async {
      await zeigeScreen(tester);

      // DIE VERSION STEHT GANZ UNTEN: Der Bildschirm ist sehr lang,
      // also wird Stueck fuer Stueck gescrollt.
      for (var i = 0; i < 40; i++) {
        if (find.textContaining('Version 0.10.2').evaluate().isNotEmpty) break;
        await tester.timedDrag(
          find.byType(Scrollable).first,
          const Offset(0, -600),
          const Duration(milliseconds: 200),
        );
        await tester.pump(const Duration(milliseconds: 120));
      }
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Version 0.10.2'),
        findsOneWidget,
        reason:
            'Ohne die Versionsangabe kann der Support nicht sagen, welche '
            'Fassung der Nutzer hat.',
      );
    });
  });

  group('Die Schalter', () {
    testWidgets('der Schalter fuer Nachrichten wird gespeichert', (
      tester,
    ) async {
      await zeigeScreen(tester);

      final vorher = container.read(settingsProvider).notifyMessages;
      await tippeSchalter(
        tester,
        L10n.tWithoutContext('settings.notifyMessages'),
      );

      expect(
        container.read(settingsProvider).notifyMessages,
        isNot(vorher),
        reason:
            'Der Schalter muss das Speichern ausloesen - sonst glaubt der '
            'Nutzer, die Benachrichtigungen waeren aus, und sie kommen '
            'trotzdem.',
      );
    });

    testWidgets('der Schalter fuer die Dating Hour wird gespeichert', (
      tester,
    ) async {
      await zeigeScreen(tester);

      final vorher = container.read(settingsProvider).notifyDatingHour;
      await tippeSchalter(
        tester,
        L10n.tWithoutContext('settings.notifyDatingHour'),
      );

      expect(container.read(settingsProvider).notifyDatingHour, isNot(vorher));
    });

    testWidgets('der Schalter fuer unscharfe Bilder wird gespeichert', (
      tester,
    ) async {
      await zeigeScreen(tester);

      final vorher = container.read(settingsProvider).blurChatImages;
      await tippeSchalter(tester, L10n.tWithoutContext('settings.blur'));

      expect(container.read(settingsProvider).blurChatImages, isNot(vorher));
    });
  });

  group('Das Erscheinungsbild', () {
    testWidgets('"Hell" stellt das Erscheinungsbild um', (tester) async {
      await zeigeScreen(tester);

      await scrolleZu(tester, L10n.tWithoutContext('settings.appearance'));

      // DER KNOPF "HELL": Das Symbol des hellen Modus.
      final symbol = find.byIcon(Icons.light_mode_outlined);
      expect(symbol, findsOneWidget, reason: 'Der Modus "Hell" muss da sein.');
      final segment = find.ancestor(of: symbol, matching: find.byType(InkWell));
      await tester.ensureVisible(segment);
      await tester.pump();
      await tester.tap(segment);
      await pumpFrames(tester);
      await warteAufSync(tester);

      expect(
        container.read(settingsProvider).useDarkMode,
        isFalse,
        reason:
            'Der Nutzer will ein helles Bild - das muss gespeichert '
            'werden, sonst ist es beim naechsten Start weg.',
      );
    });

    testWidgets('die Farbe laesst sich waehlen', (tester) async {
      await zeigeScreen(tester);

      await scrolleZu(tester, L10n.tWithoutContext('settings.colors'));

      // DIE FARBFELDER: Der zweite Kreis ist eine andere Farbe.
      final circles = find.descendant(
        of: find.byType(ThemePicker),
        matching: find.byType(InkWell),
      );
      expect(circles, findsWidgets, reason: 'Die Farben muessen da sein.');
      await tester.ensureVisible(circles.at(1));
      await tester.pump();
      await tester.tap(circles.at(1));
      await pumpFrames(tester);

      expect(
        container.read(settingsProvider).themeName,
        isNot('classic'),
        reason: 'Die gewaehlte Farbe muss gespeichert werden.',
      );
    });
  });

  group('Die Dialoge', () {
    testWidgets('der Backup-Dialog laesst sich abbrechen', (tester) async {
      await zeigeScreen(tester);
      await oeffneBackupDialog(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'Der Abbruch muss den Dialog schliessen.',
      );
      expect(find.text('TEST_BACKUP_CODE_1234'), findsNothing);
    });

    testWidgets('scheitert das Backup, wird es gesagt', (tester) async {
      await zeigeScreen(
        tester,
        verschluesselung: _Verschluesselung(scheitert: true),
      );
      await oeffneBackupDialog(tester);
      await backupErstellen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('settings.backupCreateFailed')),
        findsOneWidget,
        reason:
            'Ein stilles Scheitern waere das Schlimmste - der Nutzer '
            'wuerde denken, er haette ein Backup, und haette keines.',
      );
    });

    testWidgets('der Code-Dialog laesst sich schliessen', (tester) async {
      await zeigeScreen(tester);
      await oeffneBackupDialog(tester);
      await backupErstellen(tester);

      expect(find.text('TEST_BACKUP_CODE_1234'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, L10n.tWithoutContext('common.done')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('TEST_BACKUP_CODE_1234'),
        findsNothing,
        reason: 'Der Dialog muss sich schliessen lassen.',
      );
    });

    testWidgets('das Wiederherstellen fragt erst nach', (tester) async {
      await zeigeScreen(tester);

      await scrolleZu(tester, L10n.tWithoutContext('settings.keyBackup'));
      final knopf = find.byIcon(Icons.restore);
      expect(
        knopf,
        findsOneWidget,
        reason: 'Der Wiederherstellen-Knopf muss da sein.',
      );
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await pumpFrames(tester);

      expect(
        find.text(L10n.tWithoutContext('settings.restoreConfirmTitle')),
        findsOneWidget,
        reason:
            'Das Wiederherstellen ueberschreibt die Identitaet - der Nutzer '
            'muss vorher zustimmen.',
      );

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('common.continue'),
        ),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('settings.restoreEnterTitle')),
        findsOneWidget,
        reason:
            'Nach der Zusage fragt der Dialog nach dem Code und dem '
            'Passwort - sonst waere die Zusage sinnlos.',
      );
    });
  });

  group('Das Konto', () {
    testWidgets('das Loeschen fragt erst nach', (tester) async {
      await zeigeScreen(tester);

      await scrolleZu(tester, L10n.tWithoutContext('privacy.dangerZone'));
      final eintrag = find.text(L10n.tWithoutContext('privacy.deleteAccount'));
      expect(eintrag, findsOneWidget);
      await tester.ensureVisible(eintrag);
      await tester.pump();
      await tester.tap(eintrag);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('privacy.deleteTitle')),
        findsOneWidget,
        reason:
            'Das Konto loeschen ist nicht rueckgaengig zu machen - der '
            'Nutzer muss bestaetigen.',
      );

      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await pumpFrames(tester);
      expect(
        find.text(L10n.tWithoutContext('privacy.deleteTitle')),
        findsNothing,
      );
    });
  });

  group('Der Zwei-Faktor', () {
    testWidgets('die Kachel sagt, dass er aktiv ist', (tester) async {
      await zeigeScreen(
        tester,
        mfa: const MfaStatus(
          currentAal: 'aal2',
          hasVerifiedFactors: true,
          hasAnyFactor: true,
          loaded: true,
        ),
      );

      expect(
        find.text(L10n.tWithoutContext('settings.twoFactorActive')),
        findsOneWidget,
        reason:
            'Nach dem Einrichten muss die Kachel den Stand zeigen - sonst '
            'wuerde der Nutzer denken, es sei nichts passiert.',
      );
    });
  });

  group('Das Zurueck', () {
    testWidgets('der Zurueck-Knopf geht zurueck', (tester) async {
      await zeigeScreen(tester, mitRouter: true);

      expect(tester.takeException(), isNull);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.byTooltip(L10n.tWithoutContext('common.back')));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Startseite'),
        findsOneWidget,
        reason:
            'Der Zurueck-Knopf muss zum aufrufenden Screen zurueck - sonst '
            'ist der Nutzer im Bildschirm gefangen.',
      );
    });
  });
}
