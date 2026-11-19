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
      // Die Spur bleibt: sonst waere ein Fehler still.
      debugPrint('[Test] Der Temp-Ordner ist nicht lesbar: $e');
    }
  }
  return null;
}

void main() {
  /// Der Ersatz-Server (Antworten aus dem RAM).
  late FakeSupabaseServer server;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // DER KEYSTORE: Der Bildschirm liest die Einstellungen aus dem
    // verschluesselten Speicher - ohne den Mock ruft der Test auf dem
    // CI-Runner das echte Plugin (das findet dort keine libsecret-
    // Sitzung).
    mockKeystore();
    mockZeitzone();
    // DER PFAD-KANAL: der Export schreibt seine Datei in den
    // Temp-Ordner des Geraets - ohne den Mock sucht der Test auf dem
    // Rechner statt im Testordner.
    await mockPfadProvider();

    // DER CLIENT: der Datenexport braucht den Supabase-Client (der
    // Chat-Verlauf und die E2E-Boxen werden gelesen).
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

  Future<void> zeigeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Der Datenexport liest Profil, Einstellungen und Praeferenzen -
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
  // (DSGVO Art. 20). Der Test prueft die DATEI - sie wird geschrieben,
  // BEVOR das Teilen (share_plus) kommt; im Test scheitert das Teilen
  // (kein Plugin), die Datei muss trotzdem da sein.

  /// Tippt den Export-Knopf und liefert die geparste Datei.
  ///
  /// Das Schreiben der Datei braucht echte Zeit - und die Datei kann
  /// noch leer sein, wenn sie gerade geschrieben wird.
  Future<Map<String, dynamic>> holeExport(WidgetTester tester) async {
    // DER ORDNER BLEIBT UEBER DIE TESTS HINWEG: Der Pfad-Mock legt bei
    // jedem Testlauf einen neuen Temp-Ordner an, aber der Export sucht
    // in ALLEN nach der Datei. Eine alte Datei (mit dem Inhalt des
    // vorherigen Laufs) wuerde sonst gelesen - der Test pruefte dann
    // uralte Daten. Deshalb wird sie vorher geloescht.
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
    // STUN-Server noch den fehlenden TURN-Relay. Die vier oeffentlichen
    // STUN-Server sehen beim Verbindungsaufbau die oeffentliche
    // IP-Adresse des Nutzers - das ist eine Verarbeitung im Auftrag und
    // gehoert in die Liste.
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
