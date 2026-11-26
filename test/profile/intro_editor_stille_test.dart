// Die Aufnahme im Vorstellungs-Editor: still, anhören, verwenden.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/widgets/profile/intro_editor.dart 86 offene Zeilen. Der Weg nach
// der Aufnahme - aufnehmen, anhören, übernehmen oder verwerfen - war
// ungetestet. Das sind genau die Wege, an denen eine Aufnahme verloren
// geht (oder eine schlechte gespeichert wird).
//
// WAS HIER GEPRÜFT WIRD:
//   * eine stille Aufnahme wird verworfen und nachgefragt (der Nutzer
//     soll neu aufnehmen, nicht eine stille Datei speichern),
//   * die Aufnahme wird erst nach dem Anhören verwendet ("Verwerfen"
//     löscht die Datei und speichert nichts),
//   * nach dem Bestätigen wird die Datei hochgeladen und gemeldet.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/server/supabase_storage_service.dart';
import 'package:thestia/widgets/profile/intro_editor.dart';

import '../support/plugin_mocks.dart';

/// Der Speicher-Dienst ohne Server.
///
/// DER GRUND: Der echte Dienst braucht eine Anmeldung und den
/// Supabase-Client. Im Test reicht der Ersatz: er meldet das
/// Hochladen zurück.
class _FakeStorage extends SupabaseStorageService {
  _FakeStorage() : super(_dummyClient);

  /// Der Client wird nie benutzt (alle Methoden sind überschrieben).
  static final _dummyClient = supabase.Supabase.instance.client;

  /// Wie oft wurde hochgeladen?
  int uploads = 0;

  @override
  Future<String> uploadIntroAudio(List<int> data) async {
    uploads++;
    return 'hochgeladen/intro.m4a';
  }

  @override
  Future<void> deleteIntroAudio() async {
    // Der Test löscht keine Aufnahme vom Server.
  }
}

void main() {
  late _FakeStorage storage;
  late List<String> aufnahmeDateien;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
    // DIE AUFNAHMEDATEIEN: Echtes Datei-Work - es muss VOR dem Test
    // passieren (im Test-Bereich hängt die Datei-Arbeit).
    final ordner = await Directory.systemTemp.createTemp('thesia_intro');
    aufnahmeDateien = <String>[];
    for (var i = 0; i < 3; i++) {
      final datei = File('${ordner.path}/aufnahme-$i.m4a');
      await datei.writeAsBytes(<int>[1, 2, 3, 4, 5]);
      aufnahmeDateien.add(datei.path);
    }
  });

  setUp(() {
    storage = _FakeStorage();
    // DER STANDARD: Erlaubt, mit Pegel (also "Sprache").
    mockAufnahme();
    // DER AUDIO-PLAYER: Das Anhören-Blatt nutzt ihn - ohne den
    // Ersatz schlägt der Aufbau des Blattes fehl.
    mockAudioPlayer();
  });

  /// Baut den Editor und meldet jede Änderung.
  Future<void> baueEditor(
    WidgetTester tester, {
    void Function(String text, String? pfad)? onChanged,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseStorageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: IntroEditor(
                initialText: 'Hallo, ich bin Lena.',
                initialAudioPath: null,
                required: true,
                onChanged: onChanged ?? (text, pfad) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Tippt auf einen Knopf (der Knopf kann unterhalb der Falz liegen).
  Future<void> knopfTippen(WidgetTester tester, String text) async {
    final knopf = find.text(text);
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Nimmt auf und beendet die Aufnahme wieder.
  ///
  /// DER GRUND FÜR DIE KLEINEN SCHRITTE: Das Plugin fragt den Pegel
  /// alle 100 ms ab (10 Hz). Ein großer Zeitsprung lässt den Timer nur
  /// einmal feuern - die Messungen kämen dann nicht an, und die App
  /// hält die Aufnahme für "still".
  Future<void> aufnehmenUndStoppen(
    WidgetTester tester, {
    int sekunden = 0,
  }) async {
    await knopfTippen(tester, L10n.tWithoutContext('intro.record'));
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < sekunden * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await knopfTippen(tester, L10n.tWithoutContext('intro.stopListen'));
    // Das Stoppen ist echte Datei-Arbeit - sie braucht die echte
    // Ereignisschleife.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Die Aufnahme im Vorstellungs-Editor', () {
    testWidgets('eine stille Aufnahme wird verworfen und nachgefragt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // STILLE: Der Pegel liegt unter der Rauschgrenze - es wurde nichts
      // gesagt.
      mockAufnahme(amplitude: -60);
      await baueEditor(tester);

      await aufnehmenUndStoppen(tester);

      expect(
        find.text(L10n.tWithoutContext('intro.silentTitle')),
        findsOneWidget,
        reason:
            'Eine Aufnahme ohne verstaendlichen Ton soll nicht gespeichert '
            'werden - der Nutzer muss es erfahren und neu aufnehmen '
            'koennen.',
      );
      expect(
        storage.uploads,
        0,
        reason: 'Eine stille Aufnahme wird nicht hochgeladen.',
      );
    });

    testWidgets('nach dem Anhoeren verwirft der Nutzer die Aufnahme', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var gemeldet = false;
      mockAufnahme(dateiBeimStoppen: aufnahmeDateien[0]);
      await baueEditor(tester, onChanged: (text, pfad) => gemeldet = true);

      // SECHS SEKUNDEN: Die Aufnahme muss lang genug sein, sonst fragt
      // das Blatt "zu kurz" und bietet nur das Neuaufnehmen an.
      await aufnehmenUndStoppen(tester, sekunden: 12);

      expect(
        find.text(L10n.tWithoutContext('intro.review.title')),
        findsOneWidget,
        reason:
            'Die Aufnahme wird erst angehoert - "Anhoeren vor Senden" ist '
            'die Regel der App.',
      );

      // VERWERFEN:
      await knopfTippen(tester, L10n.tWithoutContext('intro.review.discard'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump(const Duration(milliseconds: 200));

      expect(storage.uploads, 0, reason: 'Wer verwirft, laedt nichts hoch.');
      expect(
        gemeldet,
        isFalse,
        reason: 'Der Editor darf keine Aenderung melden, die es nicht gibt.',
      );
      expect(
        File(aufnahmeDateien[0]).existsSync(),
        isFalse,
        reason:
            'Die verworfene Aufnahme muss von der Platte verschwinden - '
            'sonst bleibt eine Aufnahme des Nutzers auf dem Geraet.',
      );
    });

    testWidgets('nach dem Bestaetigen wird die Aufnahme hochgeladen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? gemeldeterPfad;
      mockAufnahme(dateiBeimStoppen: aufnahmeDateien[1]);

      // DER PLAYER: Der Test-Ersatz kann den Audio-Player nicht sauber
      // schließen - beim Schließen meldet der Player noch einen offenen
      // Datenstrom ("cannot close the subject while items are being added").
      // Das ist ein Fehler des Ersatzes, nicht der App: die Aussagen
      // unten prüfen den Weg der App, nicht den des Players.
      Object? unerwartet;
      await runZonedGuarded(
        () async {
          await baueEditor(
            tester,
            onChanged: (text, pfad) => gemeldeterPfad = pfad,
          );

          await aufnehmenUndStoppen(tester, sekunden: 12);

          expect(
            find.text(L10n.tWithoutContext('intro.review.title')),
            findsOneWidget,
          );

          // BESTÄTIGEN:
          await knopfTippen(
            tester,
            L10n.tWithoutContext('intro.review.confirm'),
          );
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 40));
            });
            await tester.pump(const Duration(milliseconds: 100));
          }
        },
        (fehler, stapel) {
          // Siehe oben: der Fehler kommt vom Test-Ersatz des Players.
          if (fehler is StateError &&
              fehler.message.contains('cannot close the subject')) {
            return;
          }
          unerwartet = fehler;
        },
      );

      expect(
        unerwartet,
        isNull,
        reason: 'Ausser dem Player-Fehler des Ersatzes darf nichts passieren.',
      );

      expect(
        storage.uploads,
        1,
        reason:
            'Die Aufnahme muss zum Server - sonst hat der Partner keine '
            'Vorstellung.',
      );
      expect(
        gemeldeterPfad,
        'hochgeladen/intro.m4a',
        reason: 'Der Bildschirm muss den neuen Pfad melden.',
      );
      expect(
        File(aufnahmeDateien[1]).existsSync(),
        isFalse,
        reason:
            'Die lokale Datei wird nach dem Hochladen geloescht - sie '
            'gehoert auf den Server, nicht auf das Geraet.',
      );
    });
  });
}
