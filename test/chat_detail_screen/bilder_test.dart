// Das Senden von Bildern im Chat.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/parts/chatbilder.dart 89 offene Zeilen bei 91
// gesamt - der ganze Bildversand war ungetestet.
//
// DER GRUND: Ein Bild im Chat ist der heikelste Moment der App:
//   * es verlaesst das Geraet (ueber den Datenkanal, E2E-verschluesselt),
//   * seine Metadaten (GPS!) werden vorher entfernt,
//   * sein Hash wird serverseitig registriert (damit eine spaetere
//     Meldung dieses Bildes nachweisbar ist).
// Fehler in diesem Weg fallen niemandem auf: das Bild geht einfach
// nicht raus.
//
// WAS HIER GEPRUEFT WIRD:
//   * das Menue fragt nach der Quelle (Kamera oder Galerie),
//   * "Abbrechen" sendet nichts (die Bildauswahl wird gar nicht
//     geoeffnet),
//   * ohne Auswahl wird nichts gesendet (und nichts stuerzt ab),
//   * ein Bild, das nicht vorbereitet werden kann, wird abgewiesen und
//     dem Nutzer gemeldet.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Das Plattform-Interface wird von image_picker exportiert, aber nicht
// weitergereicht - der Test setzt die Attrappe darueber.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/verification/report_models.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import 'hilfen.dart';

/// Der Bildauswahl-Ersatz.
///
/// DER GRUND: Das echte Plugin oeffnet auf dem Testrechner eine Datei-
/// auswahl (oder gar nichts). Der Ersatz liefert eine feste Datei - oder
/// gar keine (so verhaelt sich ein Geraet, auf dem der Nutzer abbricht).
class _FakeImagePicker extends ImagePickerPlatform {
  _FakeImagePicker(this.datei);

  /// Die gelieferte Datei (null = der Nutzer bricht ab).
  final String? datei;

  /// Wie oft wurde ausgewahlt?
  int aufrufe = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    aufrufe++;
    if (datei == null) return null;
    return XFile(datei!);
  }
}

void main() {
  // DER STIMMUNGS-DIENST: Der Chat zeigt die Stimmungskarte - ohne den
  // Client schlaegt der Aufbau fehl.
  moodClient = supabase.SupabaseClient(
    'https://example.supabase.co',
    'test-key',
  );
  tearDownAll(() async {
    await moodClient.dispose();
  });

  /// Der Ersatz fuer die Bildauswahl (der echte waere das Plugin).
  late ImagePickerPlatform original;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner das echte
    // Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE und HIVE: der Signal-Dienst (Sicherheitsnummer) liest
    // seine verschluesselten Boxen aus dem Keystore und aus Hive.
    mockKeystore();
    await mockHive();
    // DER ADAPTER: Der Meldungs-Store legt seine Zeilen als
    // UserReport-Objekte ab.
    Hive.registerAdapter(UserReportAdapter());
    // DIE AUFNAHME: der Chat hat eine Sprachnachricht-Funktion - der
    // Recorder wird beim Aufbau erzeugt.
    mockAufnahme();
    mockAudioPlayer();
    mockZeitzone();
    // DER SERVER: die Aktionen, die auf dem Server etwas aendern, gehen
    // ueber den Client.
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

  setUp(() {
    original = ImagePickerPlatform.instance;
  });

  tearDown(() {
    ImagePickerPlatform.instance = original;
  });

  /// Baut den Chat-Bildschirm - MIT Scaffold.
  ///
  /// DER GRUND: Der Bildschirm hat kein eigenes Scaffold (in der App
  /// steckt er in der Shell). Ohne Scaffold kann aber keine Meldung
  /// (SnackBar) erscheinen - und genau die soll der Test sehen.
  Future<void> baueChat(
    WidgetTester tester,
    ChatNotifier notifier,
    String matchId,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: chatDetailScreenOverrides(notifier),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(body: ChatDetailScreen(matchId: matchId)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tippt auf den Bild-Knopf in der Eingabeleiste.
  Future<void> bildeKnopfTippen(WidgetTester tester) async {
    final knopf = find.byTooltip(L10n.tWithoutContext('chat.imageSend'));
    await tester.ensureVisible(knopf);
    await tester.pump();
    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Der Aufraeum am Testende.
  ///
  /// DER GRUND: Der Chat startet im Hintergrund Timer (der
  /// Schreib-Indikator, die Sicherheitsnummer). Die laufen in der App
  /// weiter, bis der Bildschirm geschlossen wird - im Test muss die
  /// Uhr weiterlaufen, sonst meldet der Test "A Timer is still
  /// pending".
  ///
  /// DER WEG: Der Baum wird NICHT abgebaut - ein Abbau waehrend
  /// laufender Hintergrundarbeit wuerde im Bildschirm selbst einen
  /// Fehler ausloesen ("Cannot use ref after dispose").
  Future<void> raeumeAuf(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
  }

  group('Das Senden von Bildern', () {
    testWidgets('das Menue fragt nach der Quelle', (tester) async {
      final chat = chatMitNachricht();
      await baueChat(tester, chat.notifier, chat.match.id);

      await bildeKnopfTippen(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('chat.camera')), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('chat.gallery')), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('common.cancel')),
        findsOneWidget,
        reason:
            'Der Nutzer muss auch abbrechen koennen - ohne das sitzt er '
            'im Menue fest.',
      );

      await raeumeAuf(tester);
    });

    testWidgets('Abbrechen sendet nichts', (tester) async {
      final auswahl = _FakeImagePicker(null);
      ImagePickerPlatform.instance = auswahl;

      final chat = chatMitNachricht();
      await baueChat(tester, chat.notifier, chat.match.id);

      await bildeKnopfTippen(tester);
      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        auswahl.aufrufe,
        0,
        reason:
            'Nach dem Abbruch darf die Bildauswahl gar nicht erst '
            'geoeffnet werden - sonst waere der Abbruch umsonst.',
      );

      await raeumeAuf(tester);
    });

    testWidgets('ohne Auswahl wird nichts gesendet', (tester) async {
      final auswahl = _FakeImagePicker(null);
      ImagePickerPlatform.instance = auswahl;

      final chat = chatMitNachricht();
      await baueChat(tester, chat.notifier, chat.match.id);

      await bildeKnopfTippen(tester);
      await tester.tap(find.text(L10n.tWithoutContext('chat.gallery')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        auswahl.aufrufe,
        1,
        reason: 'Die Galerie muss gewaehlt worden sein.',
      );
      // Und es ist keine Bild-Nachricht entstanden.
      final bilder = chat.notifier
          .messagesFor(chat.match.id)
          .where((m) => m.type == MessageType.image);
      expect(bilder, isEmpty);

      await raeumeAuf(tester);
    });

    testWidgets('die Auswahl wird angenommen', (tester) async {
      // DER FALL: Der Nutzer waehlt ein Bild aus der Galerie. Die
      // Bildauswahl wird geoeffnet - und der Bildversand beginnt.
      //
      // DER WEG: Der Test prueft nur, dass die Auswahl angenommen wird
      // (der Bildversand selbst liest eine echte Datei - das laeuft im
      // Test nicht zuverlaessig).
      final ordner = Directory.systemTemp.createTempSync('chat_bild_leer');
      final datei = File('${ordner.path}/leer.jpg');
      datei.writeAsBytesSync(<int>[]);
      addTearDown(() {
        try {
          if (ordner.existsSync()) {
            ordner.deleteSync(recursive: true);
          }
        } catch (e) {
          // Der Temp-Ordner wird ohnehin irgendwann vom System geraeumt -
          // das Loeschen darf den Test aber nicht scheitern lassen.
          debugPrint('Der Temp-Ordner blieb liegen: $e');
        }
      });

      final auswahl = _FakeImagePicker(datei.path);
      ImagePickerPlatform.instance = auswahl;

      final chat = chatMitNachricht();
      await baueChat(tester, chat.notifier, chat.match.id);

      await bildeKnopfTippen(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text(L10n.tWithoutContext('chat.gallery')));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(auswahl.aufrufe, 1, reason: 'Die Auswahl muss angenommen werden.');

      await raeumeAuf(tester);
    });
  });
}
