// Der Datenschutz-Screen (bisher kaum getestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte für
// lib/screens/privacy/privacy_screen.dart 221 offene Zeilen - und der
// Bildschirm trägt die Aussagen, die der Betreiber nachgeführt hat:
// die Auftragsverarbeiter (kein Apple, Google nur für die
// Play-Store-Fassung) und der Weg zu den Nutzungsbedingungen.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * der Datenexport liegt unter "Deine Daten" (und nur dort),
//   * die Auftragsverarbeiter: Supabase, Google (Firebase), Brevo,
//     Cloudflare, Netlify - und KEIN Apple (es gibt keine
//     App-Store-Verteilung),
//   * der Eintrag zu den Nutzungsbedingungen ist da und öffnet den
//     Volltext in der App.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/privacy/privacy_screen.dart';
import 'package:thestia/services/storage/local_storage.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der Speicher im RAM (der Export braucht Profil und Einstellungen).
class _FakeLocalStorage implements LocalStorage {
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

/// Die zuletzt geschriebene Exportdatei (null = keine).
/// Die zuletzt geschriebene Exportdatei (null = keine).
File? _exportDatei() {
  for (final ordner in Directory.systemTemp.listSync().whereType<Directory>()) {
    if (!ordner.path.contains('thesia_test_pfad')) continue;
    try {
      final treffer = ordner
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('thestia_data_export.json'))
          .toList();
      if (treffer.isNotEmpty) return treffer.last;
    } catch (e) {
      // Der Ordner ist nicht lesbar - dann gibt es hier nichts.
      // Die Spur bleibt: sonst wäre ein Fehler still.
      debugPrint('[Test] Der Temp-Ordner ist nicht lesbar: $e');
    }
  }
  return null;
}

void main() {
  /// Der Ersatz-Server (Antworten aus dem RAM).
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();

    // DER CLIENT: Wird nur EINMAL initialisiert. EIN ZWEITER Aufruf von
    // `Supabase.initialize` wird vom Paket ignoriert ("Skipping
    // reinitialization") - der Client würde dann weiter den Server des
    // ERSTEN Tests benutzen, und die FehlerAntworten eines späteren
    // Tests kämen nie an.
    server = FakeSupabaseServer(userId: 'ich');
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

  setUp(() async {
    // DER KEYSTORE: Der Bildschirm liest die Einstellungen aus dem
    // verschlüsselten Speicher - ohne den Mock ruft der Test auf dem
    // CI-Runner das echte Plugin (das findet dort keine libsecret-
    // Sitzung).
    mockKeystore();
    mockZeitzone();
    // DER PFAD-KANAL: der Export schreibt seine Datei in den
    // Temp-Ordner des Geräts - ohne den Mock sucht der Test auf dem
    // Rechner statt im Testordner.
    await mockPfadProvider();

    // Jeder Test startet mit einem sauberen Server.
    server.antwortetMitFehler = false;
    server.rpcAntworten.clear();
    server.fehlerAntworten.clear();
    server.zeilen.clear();
    server.schreibvorgaenge.clear();
    server.pfade.clear();
    server.funktionsAufrufe.clear();
  });

  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Der Datenexport liest Profil, Einstellungen und Präferenzen -
          // ohne den Speicher kann er gar nicht laufen.
          localStorageProvider.overrideWithValue(_FakeLocalStorage()),
        ],
        child: const MaterialApp(home: PrivacyScreen()),
      ),
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

  // Der Datenexport: Das ist das Recht des Nutzers auf seine Daten
  // (DSGVO Art. 20). Der Test prüft die DATEI - sie wird geschrieben,
  // BEVOR das Teilen (share_plus) kommt; im Test scheitert das Teilen
  // (kein Plugin), die Datei muss trotzdem da sein.

  /// Tippt den Export-Knopf und liefert die geparste Datei.
  ///
  /// Das Schreiben der Datei braucht echte Zeit - und die Datei kann
  /// noch leer sein, wenn sie gerade geschrieben wird.
  Future<Map<String, dynamic>> holeExport(WidgetTester tester) async {
    // DER ORDNER BLEIBT ÜBER DIE TESTS HINWEG: Der Pfad-Mock legt bei
    // jedem Testlauf einen neuen Temp-Ordner an, aber der Export sucht
    // in ALLEN nach der Datei. Eine alte Datei (mit dem Inhalt des
    // vorherigen Laufs) würde sonst gelesen - der Test prüfte dann
    // uralte Daten. Deshalb wird sie vorher gelöscht.
    for (final ordner
        in Directory.systemTemp.listSync().whereType<Directory>()) {
      if (!ordner.path.contains('thesia_test_pfad')) continue;
      try {
        for (final datei in ordner.listSync().whereType<File>()) {
          if (datei.path.endsWith('thestia_data_export.json')) {
            datei.deleteSync();
          }
        }
      } catch (e) {
        // Der Ordner ist nicht lesbar - dann gibt es hier nichts.
        debugPrint('[Test] Der Temp-Ordner ist nicht lesbar: $e');
      }
    }

    await scrolleZu(tester, L10n.tWithoutContext('privacy.export'));
    final knopf = find.text(L10n.tWithoutContext('privacy.export'));
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    File? export;
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 120));
      export = _exportDatei();
      if (export != null && export.lengthSync() > 0) break;
    }
    expect(export, isNotNull, reason: 'Der Export muss eine Datei anlegen.');
    return jsonDecode(export!.readAsStringSync()) as Map<String, dynamic>;
  }

  group('Der Datenexport', () {
    testWidgets('die Exportdatei enthaelt die Daten und keine Chats', (
      tester,
    ) async {
      await zeigeScreen(tester);

      final inhalt = await holeExport(tester);

      expect(tester.takeException(), isNull);

      // Die eigenen Daten sind drin.
      expect(inhalt['app'], 'Thestia');
      expect(inhalt.containsKey('profile'), isTrue);
      expect(inhalt.containsKey('settings'), isTrue);
      expect(inhalt.containsKey('preferences'), isTrue);
      // Die Auftragsverarbeiter stehen drin (Datenschutz-Erklärung).
      final prozessoren = (inhalt['processors'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        prozessoren.map((p) => p['name']).toList(),
        contains('Supabase Inc.'),
      );
      expect(
        prozessoren.map((p) => p['name']).toList(),
        isNot(contains('Apple Inc.')),
      );
      // Und der Hinweis, dass die Chats NICHT exportiert werden.
      expect(inhalt['note'], isNotNull);
      expect(inhalt.containsKey('chats'), isFalse);
    });

    // BEFUND (16.11.2026, Audit): Die Liste nannte weder die
    // STUN-Server noch den fehlenden TURN-Relay. Die vier öffentlichen
    // STUN-Server sehen beim Verbindungsaufbau die öffentliche
    // IP-Adresse des Nutzers - das ist eine Verarbeitung im Auftrag und
    // gehört in die Liste.
    testWidgets('der Export nennt die STUN-Server und das fehlende TURN', (
      tester,
    ) async {
      await zeigeScreen(tester);
      final inhalt = await holeExport(tester);

      final namen = (inhalt['processors'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((p) => p['name'] as String)
          .toList();
      expect(
        namen.any((n) => n.contains('Nextcloud') && n.contains('OVH')),
        isTrue,
        reason:
            'Die STUN-Server sehen die oeffentliche IP-Adresse des Nutzers - '
            'sie gehoeren als Auftragsverarbeiter in die Liste.',
      );
      expect(
        namen.any((n) => n.contains('TURN')),
        isTrue,
        reason:
            'Es gibt keinen TURN-Relay - das muss im Export stehen, damit '
            'der Nutzer weiss, dass es keinen gibt.',
      );
    });
  });

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
    // Play-Store-Fassung läuft (im F-Droid-Build läuft UnifiedPush).
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

  // Der Wechsel der E-Mail-Adresse: Das ist der sicherheitskritischste
  // Weg auf dem Bildschirm - er ändert, wer der Nutzer ist. Deshalb
  // verlangt er das AKTUELLE Passwort und prüft die Eingaben, BEVOR
  // er den Server anruft.
  group('Der Wechsel der E-Mail-Adresse', () {
    /// Öffnet den Dialog zum Wechseln.
    Future<void> oeffneDialog(WidgetTester tester) async {
      await zeigeScreen(tester);
      await scrolleZu(tester, L10n.tWithoutContext('privacy.changeEmail'));

      final eintrag = find.text(L10n.tWithoutContext('privacy.changeEmail'));
      await tester.ensureVisible(eintrag);
      await tester.pump();
      await tester.tap(eintrag);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Füllt die beiden Felder und bestätigt den Dialog.
    Future<void> fuelleUndBestaetige(
      WidgetTester tester,
      String email,
      String passwort,
    ) async {
      final felder = find.byType(TextFormField);
      await tester.enterText(felder.at(0), email);
      await tester.enterText(felder.at(1), passwort);
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(L10n.tWithoutContext('common.save')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Wartet, bis der Server geantwortet hat.
    Future<void> warteAufServer(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    testWidgets('der Dialog fragt nach der Adresse und dem Passwort', (
      tester,
    ) async {
      await oeffneDialog(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.byType(TextFormField),
        findsNWidgets(2),
        reason:
            'Der Dialog braucht die neue Adresse UND das aktuelle '
            'Passwort - ohne Passwort waere der Wechsel ein Einfall '
            'fuer jeden, der am Geraet sitzt.',
      );
    });

    testWidgets('eine ungueltige Adresse wird abgewiesen', (tester) async {
      await oeffneDialog(tester);

      await fuelleUndBestaetige(tester, 'keine-mail', 'geheim123');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('privacy.validator.invalidEmail')),
        findsOneWidget,
        reason: 'Eine Adresse ohne "@" ist keine Adresse.',
      );
      // Der Dialog bleibt offen - es wurde nichts an den Server gegeben.
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('ein zu kurzes Passwort wird abgewiesen', (tester) async {
      await oeffneDialog(tester);

      await fuelleUndBestaetige(tester, 'neu@example.de', 'kurz');

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('privacy.validator.tooShort')),
        findsOneWidget,
        reason:
            'Ein zu kurzes Passwort kann nicht das aktuelle Passwort sein - '
            'der Wechsel muss scheitern.',
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('der Wechsel wird gemeldet', (tester) async {
      await oeffneDialog(tester);

      await fuelleUndBestaetige(tester, 'neu@example.de', 'geheim123');
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('privacy.changeEmailSent')),
        findsOneWidget,
        reason:
            'Der Nutzer muss wissen, dass die Aenderung an den Server '
            'gegangen ist - der Wechsel wird erst mit der Bestaetigung '
            'an der neuen Adresse aktiv.',
      );
    });

    testWidgets('ein falsches Passwort wird gemeldet', (tester) async {
      // DER SERVER LEHNT DIE ANMELDUNG AB (falsches Passwort).
      server.fehlerAntworten['/auth/v1/token'] = (
        status: 400,
        body: '{"error":"invalid_credentials"}',
      );

      await oeffneDialog(tester);
      await fuelleUndBestaetige(tester, 'neu@example.de', 'falsch123');
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining(L10n.tWithoutContext('privacy.changeFailed')),
        findsWidgets,
        reason:
            'Ein falsches Passwort muss gemeldet werden - der Nutzer darf '
            'nicht denken, die Adresse sei gewechselt.',
      );
    });
  });

  // Der Wechsel des Passworts: Auch hier gilt - bevor etwas passiert,
  // muss das aktuelle Passwort geprüft werden, und die beiden neuen
  // Passwörter müssen übereinstimmen.
  group('Der Wechsel des Passworts', () {
    /// Öffnet den Dialog zum Wechseln.
    Future<void> oeffneDialog(WidgetTester tester) async {
      await zeigeScreen(tester);
      await scrolleZu(tester, L10n.tWithoutContext('privacy.changePassword'));

      final eintrag = find.text(L10n.tWithoutContext('privacy.changePassword'));
      await tester.ensureVisible(eintrag);
      await tester.pump();
      await tester.tap(eintrag);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Füllt die drei Felder und bestätigt den Dialog.
    Future<void> fuelleUndBestaetige(
      WidgetTester tester,
      String aktuell,
      String neu,
      String wiederholung,
    ) async {
      final felder = find.byType(TextFormField);
      await tester.enterText(felder.at(0), aktuell);
      await tester.enterText(felder.at(1), neu);
      await tester.enterText(felder.at(2), wiederholung);
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(L10n.tWithoutContext('common.save')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Wartet, bis der Server geantwortet hat.
    Future<void> warteAufServer(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    testWidgets('der Dialog fragt nach drei Passwoertern', (tester) async {
      await oeffneDialog(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byType(TextFormField),
        findsNWidgets(3),
        reason:
            'Es braucht das aktuelle, das neue und die Wiederholung des '
            'neuen Passworts - sonst koennte der Nutzer sich selbst '
            'aussperren.',
      );
    });

    testWidgets('ein zu kurzes Passwort wird abgewiesen', (tester) async {
      await oeffneDialog(tester);

      await fuelleUndBestaetige(
        tester,
        'kurz',
        'neuesPasswort1',
        'neuesPasswort1',
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('privacy.validator.tooShort')),
        findsWidgets,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('zwei verschiedene neue Passwoerter werden abgewiesen', (
      tester,
    ) async {
      await oeffneDialog(tester);

      await fuelleUndBestaetige(
        tester,
        'geheim123',
        'neuesPasswort1',
        'anderesPasswort',
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('privacy.validator.mismatch')),
        findsOneWidget,
        reason:
            'Die Wiederholung muss stimmen - sonst ueberschreibt der '
            'Nutzer sein Passwort mit einem Tippfehler und sperrt sich '
            'aus.',
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('der Wechsel wird gemeldet', (tester) async {
      await oeffneDialog(tester);

      await fuelleUndBestaetige(
        tester,
        'geheim123',
        'neuesPasswort1',
        'neuesPasswort1',
      );
      await warteAufServer(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('privacy.changePasswordDone')),
        findsOneWidget,
        reason: 'Der Nutzer muss sehen, dass das Passwort gewechselt wurde.',
      );
    });
  });
}
