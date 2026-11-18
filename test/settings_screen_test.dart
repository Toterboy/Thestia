// Die Einstellungen (bisher kaum getestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/settings/settings_screen.dart 449 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * die Abschnitte stehen da (Sicherheit, Benachrichtigungen,
//     Darstellung, Datenschutz & Account),
//   * ein Schalter laesst sich umstellen und der Stand wird gespeichert.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/profile_provider.dart';
import 'package:thestia/providers/settings_provider.dart';
import 'package:thestia/screens/settings/settings_screen.dart';
import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/local_storage.dart';
import 'package:thestia/services/secure_storage.dart';

import 'support/plugin_mocks.dart';

/// Der Speicher im RAM - die Einstellungen werden daraus gelesen.
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

/// Der Verschluesselungs-Dienst mit einem fertigen Backup-Code.
///
/// DER GRUND: Der echte Dienst braucht die verschluesselten Hive-Boxen -
/// im Test waere das der Weg ueber die Schluesselverwaltung. Fuer die
/// Oberflaeche reicht der Code: der Dialog muss ihn anzeigen und das
/// Kopieren anbieten.
class _FakeEncryptionService extends EncryptionService {
  @override
  Future<String?> createEncryptedBackup(String password) async =>
      'TEST_BACKUP_CODE_1234';
}

void main() {
  late _FakeLocalStorage storage;
  late ProviderContainer container;

  setUpAll(() async {
    // DER SPEICHER DES GERAETS: der Auth-Client holt sich daraus die
    // Sitzung - ohne den Mock schlaegt der Aufbau fehl.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Der Supabase-Client: die Eltern-Aufsicht liest ihn. Ohne die drei
    // Optionen (kein Timer, kein Speicher, kein Deeplink-Observer)
    // scheitert der Aufbau auf dem CI-Runner.
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
    // HIVE: der Abschnitt "Ende-zu-Ende-Verschluesselung" liest die
    // gesicherten Schluessel aus einer Hive-Box. Ohne einen
    // initialisierten Hive scheitert der Aufbau.
    final tempDir = await Directory.systemTemp.createTemp('thesia_settings');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = _FakeLocalStorage();
    // DER KEYSTORE: die Einstellungen liegen im verschluesselten
    // Speicher - ohne den Mock ruft der Test auf dem CI-Runner das
    // echte Plugin (das findet dort keine libsecret-Sitzung).
    mockKeystore();
  });

  tearDown(() {
    container.dispose();
  });

  Future<void> zeigeScreen(WidgetTester tester, {double hoehe = 844}) async {
    await tester.binding.setSurfaceSize(Size(390, hoehe));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final secure = _FakeSecureProfileStore();
    container = ProviderContainer(
      overrides: [
        localStorageProvider.overrideWithValue(storage),
        secureProfileStoreProvider.overrideWithValue(secure),
        // DER VERSCHLUESSELUNGS-DIENST: Der echte braucht die
        // verschluesselten Boxen - im Test liefert der Ersatz den
        // Backup-Code direkt.
        encryptionServiceProvider.overrideWithValue(_FakeEncryptionService()),
        profileProvider.overrideWith((ref) {
          final notifier = ProfileNotifier(storage, secure);
          notifier.setProfile(
            const UserProfile(id: 'ich', name: 'Lena', bio: ''),
          );
          return notifier;
        }),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Pumpt eine feste Zahl von Frames.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Scrollt zu einem Text (der Bildschirm ist eine lange Liste).
  ///
  /// DER HINWEIS: Die Liste baut nur die sichtbaren Eintraege - der Text
  /// muss also erst herangescrollt werden. Es wird NICHT danach noch
  /// "sichtbar gemacht": Das wuerde die Liste weiter verschieben und die
  /// Tests stoeren, die mehrere Abschnitte gleichzeitig sehen wollen.
  Future<void> scrolleZu(WidgetTester tester, String text) async {
    final ziel = find.text(text);
    // Der Bildschirm ist sehr lang (die Liste baut nur die sichtbaren
    // Eintraege) - also wird in kleinen Schritten gescrollt, bis der
    // Text da ist.
    //
    // DER WEG: "timedDrag" statt "drag". Ein einfacher Zug kommt
    // erstaunlich wenig weiter (rund ein Drittel der Strecke) - bei
    // ueber 7000 Pixel Liste waere der Eintrag am Ende nie erreicht
    // worden. Der langsame Zug folgt dem Finger genau.
    for (var i = 0; i < 60 && ziel.evaluate().isEmpty; i++) {
      await tester.timedDrag(
        find.byType(Scrollable).first,
        const Offset(0, -300),
        const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('der Bildschirm baut sich ohne Absturz', (tester) async {
    await zeigeScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('die Abschnitte stehen da', (tester) async {
    await zeigeScreen(tester);

    for (final abschnitt in [
      'settings.communitySafety',
      'settings.notifications',
      'settings.appearance',
    ]) {
      await scrolleZu(tester, L10n.tWithoutContext(abschnitt));
      expect(
        find.text(L10n.tWithoutContext(abschnitt)),
        findsWidgets,
        reason: 'Der Abschnitt $abschnitt muss stehen.',
      );
    }
  });

  testWidgets('der Schalter fuer unscharfe Bilder steht da', (tester) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('settings.blur'));

    final schalter = find.ancestor(
      of: find.text(L10n.tWithoutContext('settings.blur')),
      matching: find.byType(SwitchListTile),
    );
    expect(
      schalter,
      findsOneWidget,
      reason:
          'Der Schalter fuer unscharfe Bilder muss erreichbar sein - er ist '
          'der Schutz, dass ein geteiltes Bild nicht unerklaerbar ist.',
    );
  });

  testWidgets('das Erscheinungsbild laesst sich umstellen', (tester) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('appearance.dark'));

    // "Dunkel" waehlen. ensureVisible: der Abschnitt liegt unterhalb
    // der Falz - ohne das landet der Tipp ins Leere.
    final dunkel = find.text(L10n.tWithoutContext('appearance.dark'));
    await tester.ensureVisible(dunkel);
    await pumpFrames(tester);
    await tester.tap(dunkel);
    await pumpFrames(tester);
    // Der Server-Sync ist entprellt (1,5 s) - der Timer muss abgelaufen
    // sein, sonst meldet der Test am Ende "Timer is still pending".
    await tester.pump(const Duration(milliseconds: 2000));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(
      container.read(settingsProvider).useDarkMode,
      isTrue,
      reason: 'Der Nutzer hat "Dunkel" gewaehlt - das muss gespeichert sein.',
    );
  });

  testWidgets('"System" heisst: die App folgt dem Geraet', (tester) async {
    await zeigeScreen(tester);

    await scrolleZu(tester, L10n.tWithoutContext('appearance.system'));

    final system = find.text(L10n.tWithoutContext('appearance.system'));
    await tester.ensureVisible(system);
    await pumpFrames(tester);
    await tester.tap(system);
    await pumpFrames(tester);
    // Der Server-Sync ist entprellt (1,5 s) - der Timer muss abgelaufen
    // sein, sonst meldet der Test am Ende "Timer is still pending".
    await tester.pump(const Duration(milliseconds: 2000));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    // null heisst: "es entscheidet das Geraet" - true/false waere eine
    // feste Entscheidung und damit etwas anderes.
    expect(container.read(settingsProvider).useDarkMode, isNull);
  });

  group('Das Wiederherstellen der Identitaet', () {
    testWidgets('es fragt erst nach', (tester) async {
      await zeigeScreen(tester);

      await scrolleZu(tester, L10n.tWithoutContext('settings.backupRestore'));
      // Der Eintrag liegt unterhalb der Falz - ohne das landet der Tipp
      // ins Leere.
      await tester.ensureVisible(
        find.text(L10n.tWithoutContext('settings.backupRestore')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(
        find.text(L10n.tWithoutContext('settings.backupRestore')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Ohne Rueckfrage wuerde die Identitaet ueberschrieben - das muss
      // der Nutzer bestaetigen.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('settings.restoreConfirmTitle')),
        findsOneWidget,
      );

      // "Abbrechen" - es passiert nichts.
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await pumpFrames(tester);

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Der lokal gespeicherte Chat-Verlauf', () {
    testWidgets('die Auswahl steht da und wird gespeichert', (tester) async {
      // GROSSER Bildschirm: der Dialog mit den drei Auswahlmoeglichkeiten
      // braucht Platz (sonst liegt die dritte Auswahl ausserhalb des
      // Fensters - und der Tipp ginge ins Leere).
      await zeigeScreen(tester, hoehe: 3000);

      // Der Eintrag steht weit unten in der Liste.
      await scrolleZu(tester, L10n.tWithoutContext('chathist.tileTitle'));
      await tester.ensureVisible(
        find.text(L10n.tWithoutContext('chathist.tileTitle')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text(L10n.tWithoutContext('chathist.tileTitle')));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Die drei Moeglichkeiten stehen da.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chathist.off.title')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('chathist.cap200.title')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('chathist.all.title')),
        findsOneWidget,
      );

      // "Gar nichts" waehlen - der Verlauf soll nicht mehr gespeichert
      // werden.
      await tester.ensureVisible(
        find.text(L10n.tWithoutContext('chathist.off.title')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text(L10n.tWithoutContext('chathist.off.title')));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Entscheid ist gespeichert - sonst waere er nach dem
      // Neustart wieder weg.
      expect(await storage.getBool('chat_history_local'), isFalse);
      expect(await storage.getBool('chat_history_all'), isFalse);
    });

    testWidgets('"200 Nachrichten pro Chat" speichert begrenzt', (
      tester,
    ) async {
      await zeigeScreen(tester, hoehe: 3000);

      await scrolleZu(tester, L10n.tWithoutContext('chathist.tileTitle'));
      await tester.ensureVisible(
        find.text(L10n.tWithoutContext('chathist.tileTitle')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text(L10n.tWithoutContext('chathist.tileTitle')));
      await pumpFrames(tester);

      // Die Auswahl kann tiefer im Dialog liegen - erst dorthin scrollen,
      // sonst trifft der Tipp ins Leere.
      //
      // DER HINWEIS: "Kompletter Verlauf" ist die VORGABE - da waere
      // nichts geaendert worden (und nichts gespeichert). Der Test
      // nimmt deshalb die begrenzte Variante.
      await tester.ensureVisible(
        find.text(L10n.tWithoutContext('chathist.cap200.title')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(
        find.text(L10n.tWithoutContext('chathist.cap200.title')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Verlauf wird gespeichert - aber nicht komplett.
      expect(await storage.getBool('chat_history_local'), isTrue);
      expect(await storage.getBool('chat_history_all'), isFalse);
    });
  });

  group('Das Backup der Ende-zu-Ende-Identitaet', () {
    /// Oeffnet den Dialog fuer das Backup-Passwort.
    Future<void> oeffneBackupDialog(WidgetTester tester) async {
      // GROSSER Bildschirm: der Abschnitt "Ende-zu-Ende-Verschluesselung"
      // liegt weit unten. Mit einem hohen Bildschirm baut die Liste
      // mehr Eintraege auf einmal - das Scrollen durch die lange Liste
      // waere im Test zaeh und fehleranfaellig.
      await zeigeScreen(tester, hoehe: 3000);

      // Der Abschnitt liegt weit unten - die Liste baut nur die
      // sichtbaren Eintraege, also wird bis zum Knopf gescrollt.
      // Ueber das Symbol gesucht: der Text "Backup erstellen" steht
      // auch als Knopf im Dialog.
      final knopf = find.byIcon(Icons.download_outlined);
      for (var i = 0; i < 60 && knopf.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(knopf, findsOneWidget, reason: 'Der Backup-Knopf muss da sein.');
      await tester.tap(knopf);
      await pumpFrames(tester);
    }

    testWidgets('der Dialog fragt nach dem Passwort', (tester) async {
      await oeffneBackupDialog(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('settings.backupChoosePw')),
        findsOneWidget,
      );
      // Zwei Felder: Passwort und Wiederholung.
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('ein zu kurzes Passwort wird abgewiesen', (tester) async {
      await oeffneBackupDialog(tester);

      await tester.enterText(find.byType(TextFormField).first, 'kurz');
      await tester.enterText(find.byType(TextFormField).last, 'kurz');
      await pumpFrames(tester);
      // Der Dialog-Knopf (der Text steht auch auf der Kachel dahinter -
      // darum der FilledButton).
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('settings.backupCreateBtn'),
        ),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      // Der Dialog bleibt offen und sagt, was fehlt.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('settings.backupPwShort')),
        findsOneWidget,
        reason:
            'Ein zu kurzes Passwort waere unbrauchbar - der Nutzer muss es '
            'wissen.',
      );
    });

    testWidgets('ein gueltiges Passwort zeigt den Backup-Code', (tester) async {
      await oeffneBackupDialog(tester);

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

      expect(tester.takeException(), isNull);
      // Der Code steht da - er ist das, was der Nutzer sichern muss.
      expect(find.text('TEST_BACKUP_CODE_1234'), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('settings.backupCodeTitle')),
        findsOneWidget,
      );
    });

    testWidgets('der Backup-Code laesst sich kopieren', (tester) async {
      await oeffneBackupDialog(tester);

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

      // "Kopieren" - dann ist der Code in der Zwischenablage.
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.copy')),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('settings.backupCopied')),
        findsOneWidget,
        reason: 'Der Nutzer muss wissen, dass der Code kopiert wurde.',
      );
    });

    testWidgets('zwei verschiedene Passwoerter werden abgewiesen', (
      tester,
    ) async {
      await oeffneBackupDialog(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'ein-sehr-langes-passwort',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'ein-anderes-passwort',
      );
      await pumpFrames(tester);
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('settings.backupCreateBtn'),
        ),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('settings.backupPwMismatch')),
        findsOneWidget,
        reason:
            'Ein Tippfehler beim Wiederholen darf nicht still zu einem '
            'unbrauchbaren Backup fuehren.',
      );
    });
  });
}
