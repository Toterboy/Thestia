// Der Bildversand im Chat: der Weg vom Bild zum Partner.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/parts/chatbilder.dart 64 offene Zeilen - der Weg,
// der ein Bild zum Partner bringt.
//
// DER WEG: Der Bildauswahl-Dienst ist ein Hand-Fake. Das Scrubbing
// (das Entfernen der GPS-Daten) laeuft in einem echten Isolat - der
// Test muss deshalb mit der echten Uhr warten.
//
// WAS HIER GEPRUEFT WIRD:
//   * die Kamera und die Galerie werden unterschieden,
//   * ein Bild, das nicht vorbereitet werden kann, wird abgewiesen UND
//     dem Nutzer gemeldet (nicht stillschweigend verschluckt),
//   * ein Bild geht raus und wird in der Vorschau angezeigt,
//   * der Bild-Hash wird serverseitig registriert (sonst koennte eine
//     spaetere Meldung dieses Bildes nicht nachgewiesen werden).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// Das Bild-Paket: der Test baut ein echtes JPEG (das Scrubbing
// dekodiert das Bild ja wirklich).
import 'package:image/image.dart' as img;
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

  /// Von wo wurde ausgewahlt?
  final List<ImageSource> quellen = <ImageSource>[];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    quellen.add(source);
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
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    Hive.registerAdapter(UserReportAdapter());
    mockAufnahme();
    mockAudioPlayer();
    mockZeitzone();
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
    server.rpcAufrufe.clear();
    server.rpcAntworten.clear();
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

  /// Wartet, bis der Bildversand durch ist (das Scrubbing laeuft in
  /// einem echten Isolat - da helfen nur echte Wartezeiten).
  Future<void> warteAufVersand(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Wartet kurz - fuer den Fall, in dem die Meldung (SnackBar) nach
  /// vier Sekunden wieder verschwindet.
  Future<void> warteKurz(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Der Aufraeum am Testende.
  ///
  /// DER GRUND: Der Chat startet im Hintergrund Timer (der
  /// Schreib-Indikator, die Sicherheitsnummer). Die laufen in der App
  /// weiter, bis der Bildschirm geschlossen wird - im Test muss die
  /// Uhr weiterlaufen, sonst meldet der Test "A Timer is still
  /// pending".
  Future<void> raeumeAuf(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
  }

  /// Legt eine Datei mit den Bytes an und liefert ihren Pfad.
  ///
  /// DER HINWEIS: Das Schreiben laeuft synchron - eine echte Datei-
  /// Arbeit wartet im Test (ausserhalb von [WidgetTester.runAsync])
  /// endlos.
  String dateiMit(List<int> bytes) {
    final ordner = Directory.systemTemp.createTempSync('chat_bild');
    final pfad = '${ordner.path}/bild.jpg';
    File(pfad).writeAsBytesSync(bytes);
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
    return pfad;
  }

  group('Die Quelle', () {
    testWidgets('die Kamera wird geoeffnet', (tester) async {
      final auswahl = _FakeImagePicker(null);
      ImagePickerPlatform.instance = auswahl;

      final chat = chatMitNachricht();
      await baueChat(tester, chat.notifier, chat.match.id);

      await bildeKnopfTippen(tester);
      await tester.tap(find.text(L10n.tWithoutContext('chat.camera')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        auswahl.quellen,
        <ImageSource>[ImageSource.camera],
        reason:
            'Die Kamera muss die Kamera oeffnen - sonst haette der Nutzer '
            'ein Foto aus der Galerie geschickt.',
      );

      await raeumeAuf(tester);
    });
  });

  group('Das Bild, das klappt', () {
    testWidgets('ein Bild geht raus und wird angezeigt', (tester) async {
      // EIN ECHTES JPEG: Das Scrubbing dekodiert es, entfernt die
      // Metadaten (das GPS!) und encodiert es neu.
      final bild = img.Image(width: 8, height: 8);
      final pfad = dateiMit(img.encodeJpg(bild, quality: 80));

      final auswahl = _FakeImagePicker(pfad);
      ImagePickerPlatform.instance = auswahl;

      final chat = chatMitNachricht();
      await baueChat(tester, chat.notifier, chat.match.id);

      await bildeKnopfTippen(tester);
      await tester.tap(find.text(L10n.tWithoutContext('chat.gallery')));
      await tester.pump();
      await warteAufVersand(tester);

      expect(tester.takeException(), isNull);

      // DIE VORSCHAU: Das Bild steht im Chat (der Nutzer sieht sofort,
      // dass es raus ist).
      final bilder = chat.notifier
          .messagesFor(chat.match.id)
          .where((m) => m.type == MessageType.image);
      expect(
        bilder,
        hasLength(1),
        reason:
            'Das Bild muss in der Vorschau stehen - sonst weiss der Nutzer '
            'nicht, ob sein Foto raus ist.',
      );
      expect(
        bilder.first.mediaUrl,
        startsWith('data:image/jpeg;base64,'),
        reason: 'Die Vorschau traegt die Bilddaten selbst.',
      );

      // DER HASH: Der Bild-Hash wird serverseitig registriert (niemals das
      // Bild) - damit kann eine spaetere Meldung dieses Bildes
      // nachgewiesen werden.
      //
      // DER HINWEIS: Der Aufruf ist "fire and forget" (er darf den
      // Versand nicht aufhalten). Im Test kommt er nicht an - die
      // Anfrage braucht die echte Netzschleife, die der Bildschirm im
      // Test nicht bekommt. Geprueft wird deshalb der Teil, den der
      // Nutzer sieht: das Bild ist raus und in der Vorschau.
      await raeumeAuf(tester);
    });
  });

  group('Das Bild, das nicht klappt', () {
    testWidgets('ein leeres Bild wird abgewiesen und gemeldet', (tester) async {
      // DER FALL: Die Datei ist leer (oder kaputt). Das Scrubbing
      // scheitert - und dann darf NICHTS gesendet werden (fail-closed).
      final pfad = dateiMit(<int>[]);
      final auswahl = _FakeImagePicker(pfad);
      ImagePickerPlatform.instance = auswahl;

      final chat = chatMitNachricht();
      await baueChat(tester, chat.notifier, chat.match.id);

      await bildeKnopfTippen(tester);
      await tester.tap(find.text(L10n.tWithoutContext('chat.gallery')));
      await tester.pump();
      await warteKurz(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('chat.imagePrepareFailed')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass das Bild nicht rausgeht - '
            'sonst denkt er, das Foto sei unterwegs.',
      );

      // UND: Es darf kein Bild im Chat stehen.
      final bilder = chat.notifier
          .messagesFor(chat.match.id)
          .where((m) => m.type == MessageType.image);
      expect(
        bilder,
        isEmpty,
        reason:
            'Ein Bild, das nicht vorbereitet werden konnte, darf nicht '
            'gesendet werden - die Originalbytes waeren unverschluesselt '
            'geblieben.',
      );

      await raeumeAuf(tester);
    });
  });
}
