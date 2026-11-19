// Die Tests 'transit_radar_screen' (Teil 1).
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Tests
// sind nach Themen aufgeteilt; die Helfer liegen in
// test/support/transit_radar_screen_hilfen.dart.

// Der Transit-Radar (Transit Spark) - bisher ungetestet.
//
// ANLASS (13.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/swipe/transit_radar_screen.dart 936 offene Zeilen. Der
// Bildschirm ist der Kern von Transit Spark ("Blicke getauscht, dich
// nicht getraut?") - und er wurde nie gerendert.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * die Alterssperre ist fail-closed (ohne Geburtsdatum gesperrt),
//   * beim ersten Oeffnen fragt die App, ob der Name sichtbar sein soll,
//   * der Start fragt zuerst nach der eigenen Beschreibung,
//   * "Blicke getauscht" oeffnet die Merkmalsauswahl und sendet die Tags,
//   * die Kandidatenliste erscheint und der Zuwink meldet Erfolg/Fehlschlag,
//   * der Ort wird uebernommen (frei gewaehlt - KEIN Standort),
//   * der Name-Schalter speichert die Entscheidung.
//
// OHNE FUNK, OHNE SERVER: Das BLE-Starten und der Server werden durch
// einen Fake-Notifier ersetzt (kein Bluetooth, kein Netz). Die
// Merkmalsauswahl selbst ist das ECHTE Widget der App - sie wird nicht
// nachgebaut, sonst wuerde der Test nur Flutter pruefen und nicht die
// App.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/transit/transit_models.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/providers/transit/transit_provider.dart';
import 'package:thestia/services/transit/transit_ble_service.dart';
import '../support/ble_mocks.dart';
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

void main() {
  setUpAll(() async {
    // DER SPEICHER: Supabase braucht ihn (der Auth-Client legt den
    // Sitzungs-Token dort ab) - ohne den Ersatz sucht das Plugin auf dem
    // CI-Runner das echte und findet nichts.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // DER SERVER: Der Posteingang der Grueesse laeuft ueber die Datenbank
    // (list_my_soft_pings). Ohne Server bleibt der Posteingang leer -
    // und genau den Bereich prueft kein Test.
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: server,
      authOptions: const supabase.FlutterAuthClientOptions(
        detectSessionInUri: false,
        persistSession: false,
        autoRefreshToken: false,
      ),
    );
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Der Server beginnt ohne Gruesse - jeder Test stellt seine eigenen.
    server.rpcAntworten['list_my_soft_pings'] = <dynamic>[];
    server.rpcAntworten.remove('accept_soft_ping');
    server.schreibvorgaenge.clear();
    // DER KEYSTORE: Der Bildschirm liest die Einstellungen (Altersspanne
    // und Suchradius) aus dem verschluesselten Speicher. Ohne diesen
    // Mock ruft der Test auf dem CI-Runner das echte Plugin - und das
    // findet dort keine libsecret-Sitzung.
    mockKeystore();
  });
  group('Der Transit-Radar', () {
    group('Die Fehler beim Start', () {
      /// Startet den Radar mit einem Start, der scheitert.
      ///
      /// [grund] ist der Fehlergrund, den der echte Dienst liefert
      /// ([TransitBleService.lastError]) - der Bildschirm liest ihn
      /// von dort, um die passende Erklaerung zu zeigen.
      Future<FakeTransit> starteFehlgeschlagen(
        WidgetTester tester, {
        required String grund,
      }) async {
        final transit = FakeTransit()..startFehler = grund;
        TransitBleService.instance.lastError = grund;
        addTearDown(() => TransitBleService.instance.lastError = null);

        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await startTippen(tester);
        // Der Start fragt zuerst nach der eigenen Beschreibung.
        // Wichtig: es muessen MINDESTENS ZWEI Merkmale sein (Migration
        // 149) - mit einem einzigen bleibt der Senden-Knopf gesperrt und
        // der Start kommt nie zustande.
        await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
        await sendenTippen(tester);
        return transit;
      }

      testWidgets('ohne den Standortdienst sagt die App, was fehlt', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = await starteFehlgeschlagen(
          tester,
          grund: 'location_service',
        );

        expect(transit.starts, greaterThan(0));
        expect(tester.takeException(), isNull);
        // Der Dialog nennt den Standortdienst - sonst sucht der Nutzer
        // vergebens nach Bluetooth.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text(L10n.tWithoutContext('transit.locationTitle')),
          findsOneWidget,
        );
      });

      testWidgets('ohne Bluetooth-Berechtigung kommt der Hinweis', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = await starteFehlgeschlagen(
          tester,
          grund: 'bluetooth_scan',
        );

        expect(transit.starts, greaterThan(0));
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('ist Bluetooth aus, steht das auch da', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = await starteFehlgeschlagen(
          tester,
          grund: 'bluetooth_off',
        );

        expect(transit.starts, greaterThan(0));
        expect(tester.takeException(), isNull);
        // Auch fuer "Bluetooth ist aus" gibt es eine eigene Erklaerung.
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    });
    testWidgets('rendert ohne Absturz und zeigt die Bedienung', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      expect(tester.takeException(), isNull);
      // Der Titel steht da.
      expect(find.text('Transit Spark'), findsOneWidget);
      // Der Radar ist aus - mit dem Klartext, was das bedeutet.
      expect(find.textContaining('Radar aus'), findsOneWidget);
      // Start und "Blicke getauscht" sind da.
      expect(find.text('Radar aktivieren'), findsOneWidget);
      expect(find.text('Blicke getauscht'), findsOneWidget);
      // Die Ortseingabe steht bereit.
      expect(find.byKey(const Key('transit.placeText')), findsOneWidget);
      // Der Schalter fuer den Namen steht da.
      expect(find.text('Namen beim Zuwinken zeigen'), findsOneWidget);
      // Und die Datenschutz-Erklaerung nicht vergessen.
      expect(find.text('Wie funktioniert das?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('ohne Geburtsdatum bleibt der Radar gesperrt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      final container = transitRadarScreenContainer(
        transit: transit,
        profil: ohneGeburtsdatum(),
      );
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      expect(tester.takeException(), isNull);
      // Die Sperre wird erklaert, nicht kommentarlos gezeigt.
      expect(find.text('Transit Spark nur ab 18'), findsOneWidget);
      // Und es gibt KEINEN Start-Knopf (fail-closed).
      expect(find.text('Radar aktivieren'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('beim ersten Oeffnen fragt die App nach dem Namen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      // Die Namensfrage ist noch nicht beantwortet.
      final container = transitRadarScreenContainer(
        transit: transit,
        namensfrageErledigt: false,
      );
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      expect(tester.takeException(), isNull);
      expect(find.text('Soll dein Name sichtbar sein?'), findsOneWidget);

      // "Nein" heisst: anonym bleiben.
      await tester.tap(find.text('Nein, bleib anonym'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final settings = container.read(settingsProvider);
      expect(
        settings.transitShowName,
        isFalse,
        reason: 'Die Entscheidung "anonym" muss gespeichert werden.',
      );
      expect(
        settings.transitShowNameSet,
        isTrue,
        reason:
            'Nach der Entscheidung darf die Frage nicht mehr kommen - '
            'sonst fragt die App bei jedem Oeffnen.',
      );

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('der Start fragt zuerst nach der eigenen Beschreibung', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      await startTippen(tester);

      expect(find.text('Wie siehst du gerade aus?'), findsOneWidget);
      expect(transit.starts, 0, reason: 'Der Radar darf noch nicht laufen.');

      // Mit einem Merkmal allein ist der Senden-Knopf noch gesperrt
      // (die Server-Regel verlangt mindestens zwei).
      await merkmaleWaehlen(tester, ['Haarfarbe']);
      final knopf = find.widgetWithText(FilledButton, 'Funken');
      expect(
        tester.widget<FilledButton>(knopf).onPressed,
        isNull,
        reason: 'Mit einem Merkmal darf noch nicht gesendet werden.',
      );

      // Zwei Merkmale aus verschiedenen Kategorien - dann geht es.
      await merkmaleWaehlen(tester, ['Haarlänge']);
      expect(
        tester.widget<FilledButton>(knopf).onPressed,
        isNotNull,
        reason: 'Zwei Merkmale muessen reichen.',
      );

      await sendenTippen(tester);

      expect(tester.takeException(), isNull);
      expect(transit.starts, 1, reason: 'Der Radar muss jetzt laufen.');
      // Die eigene Beschreibung steht im Zustand.
      expect(container.read(transitProvider).selfTags, hasLength(2));
      // Und die Bedienung wechselt auf "Stoppen".
      expect(find.text('Radar stoppen'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('Blicke getauscht schickt die gewaehlten Merkmale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      // Erst den Radar starten - "Blicke getauscht" ist nur im laufenden
      // Radar moeglich.
      await startTippen(tester);
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);

      // Jetzt der eigentliche Knopf.
      await knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Die Merkmalsauswahl geht auf - mit der Frage "Wer war das?".
      expect(find.text('Wer war das?'), findsOneWidget);
      // Der Zaehler zeigt noch nichts.
      expect(find.text('0 gewaehlt'.replaceAll('ae', 'ä')), findsOneWidget);

      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);

      expect(tester.takeException(), isNull);
      expect(
        transit.gesendeteTags,
        hasLength(2),
        reason: 'Die beiden gewaehlten Merkmale muessen gesendet werden.',
      );
      expect(transit.gesendeteTags, contains('hair_color'));
      expect(transit.gesendeteTags, contains('hair_length'));
      // Ohne Gegensignal wird das Signal gespeichert - der Nutzer
      // bekommt eine Antwort, nicht Schweigen.
      expect(find.textContaining('Signal'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('ein Treffer zeigt den Freude-Dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      // Der Radar hat einen Treffer: die andere Person signalisiert auch.
      transit.sparkErgebnis = const TransitSparkResult(
        matched: true,
        partnerId: 'partner-1',
        partnerNote: 'Steig ein!',
      );
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);
      await startTippen(tester);
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);
      await knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Der Nutzer muss erfahren, dass ein Funke entstanden ist.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('transit.matchTitle')),
        findsOneWidget,
        reason:
            'Der Treffer muss dem Nutzer gemeldet werden - sonst passiert '
            'es scheinbar gar nichts.',
      );

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('ein bestehender Funke wird erkannt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      // BEFUND (09.11.2026): Mit der Person besteht SCHON ein Funke - der
      // Nutzer soll darauf hingewiesen werden statt den Freude-Dialog zu
      // sehen.
      transit.sparkErgebnis = const TransitSparkResult(
        matched: true,
        partnerId: 'partner-1',
        alreadySpark: true,
      );
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);
      await startTippen(tester);
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);
      await knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('transit.alreadySparkTitle')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass mit der Person schon ein Funke '
            'besteht.',
      );

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('ohne Geraet in Reichweite steht das drin', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      // Kein Match - und der Server sagt, warum.
      transit.sparkErgebnis = null;
      transit.sendFehler = 'no_devices';
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);
      await startTippen(tester);
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);
      await knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // DIE SNACKBAR STEHT IN DER SCHLANGE (die vorherige hat acht
      // Sekunden) - der Test muss warten.
      await warteAufText(tester, L10n.tWithoutContext('transit.noDevices'));
      expect(
        find.text(L10n.tWithoutContext('transit.noDevices')),
        findsOneWidget,
        reason:
            '"Kein Geraet in Reichweite" ist kein Fehler, sondern der '
            'Normalfall - der Nutzer soll das lesen und nicht eine tote '
            'Meldung.',
      );

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('ohne eigenen Token steht das drin', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      transit.sparkErgebnis = null;
      transit.sendFehler = 'own_token_missing';
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);
      await startTippen(tester);
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);
      await knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      await warteAufText(
        tester,
        L10n.tWithoutContext('transit.ownTokenMissing'),
      );
      expect(
        find.text(L10n.tWithoutContext('transit.ownTokenMissing')),
        findsOneWidget,
        reason:
            'Ohne eigenen Token sendet das Radar kein Signal - das muss der '
            'Nutzer erfahren.',
      );

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('der Zuwink meldet Erfolg und Fehlschlag', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      transit.kandidaten = const [
        TransitCandidate(
          id: 'kandidat-1',
          tags: ['hemd'],
          selfTags: ['schal'],
          name: 'Mira',
          placeText: 'Wagen 3',
        ),
      ];
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      await startTippen(tester);
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);

      await knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);

      // Die Kandidatenliste erscheint - mit Name und Ort der Person.
      expect(find.text('Menschen mit deiner Beschreibung'), findsOneWidget);
      expect(find.text('Mira'), findsOneWidget);
      // Der Untertitel nennt die Merkmale UND den Ort in einem Text
      // ("hemd - Wagen 3") - deshalb "enthält" statt "ist gleich".
      // (Der Ort steht auch im Platzhalter des Eingabefelds - deshalb
      // muss der Text vollstaendig passen.)
      expect(find.textContaining('hemd - Wagen 3'), findsOneWidget);

      await knopfTippen(tester, 'Zuwinken');
      await warteAufText(tester, 'Zugewinkt');

      expect(tester.takeException(), isNull);
      expect(
        find.text('Zugewinkt'),
        findsOneWidget,
        reason: 'Der Zuwink muss bestaetigt werden.',
      );

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('der Zuwink meldet auch einen Fehlschlag', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      transit.kandidaten = const [
        TransitCandidate(id: 'kandidat-1', tags: ['hemd'], selfTags: ['schal']),
      ];
      transit.zuwinkKlappt = false;
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      await startTippen(tester);
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);

      await knopfTippen(tester, 'Blicke getauscht');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);

      // Ohne freigegebenen Namen bleibt die Person anonym.
      expect(find.text('Jemand in der Nähe'), findsOneWidget);

      await knopfTippen(tester, 'Zuwinken');
      await warteAufText(tester, 'Das hat nicht geklappt');

      expect(tester.takeException(), isNull);
      expect(
        find.text('Das hat nicht geklappt'),
        findsOneWidget,
        reason: 'Ein Fehlschlag muss gesagt werden - nicht still bleiben.',
      );

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('der Ort wird uebernommen - er wird nicht ermittelt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      // Die Art des Ortes wird als Chip gewaehlt.
      await tester.ensureVisible(find.text('Zug'));
      await tester.pump();
      await tester.tap(find.text('Zug'));
      await tester.pump();

      expect(container.read(transitProvider).placeKind, 'zug');

      // Und der Ort selbst wird frei getextet.
      final feld = find.byKey(const Key('transit.placeText'));
      await tester.ensureVisible(feld);
      await tester.pump();
      await tester.enterText(feld, 'Wagen 3');
      await tester.pump();

      expect(container.read(transitProvider).placeText, 'Wagen 3');
      // Der Datenschutz-Hinweis steht daneben - der Ort ist eine
      // Selbstauskunft, keine Ortung.
      expect(find.textContaining('selbst'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('der Name-Schalter speichert die Entscheidung', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final transit = FakeTransit();
      final container = transitRadarScreenContainer(transit: transit);
      addTearDown(container.dispose);
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      final schalter = find.ancestor(
        of: find.text('Namen beim Zuwinken zeigen'),
        matching: find.byType(SwitchListTile),
      );
      expect(schalter, findsOneWidget);

      // Der Schalter steht jetzt in der Karte mit der Erinnerung
      // (BEFUND 14.11.2026: "Transit Spark Screen sieht ueberfuellt und
      // durcheinander aus") - er liegt damit weiter unten auf der
      // Seite. Ohne Scrollen geht der Tipp ins Leere.
      await tester.ensureVisible(schalter);
      await tester.pump();
      await tester.tap(schalter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final settings = container.read(settingsProvider);
      expect(
        settings.transitShowName,
        isFalse,
        reason: 'Der Schalter muss die Entscheidung uebernehmen.',
      );
      expect(
        settings.transitShowNameSet,
        isTrue,
        reason: 'Nach dem Schalter ist die Frage entschieden.',
      );
      // Und die Grenze wird genannt - ein Schalter ohne diese Erklaerung
      // erzeugt eine falsche Sicherheit.
      expect(
        find.textContaining('erkennt dich trotzdem'),
        findsOneWidget,
        reason:
            'Der Schalter muss die Grenze nennen - ein Schalter ohne diese '
            'Erklaerung erzeugt eine falsche Sicherheit.',
      );

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('der Start schaltet das Advertising ein', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      mockBluetooth();
      resetAdvertisingZaehler();

      // OHNE den Fake-Notifier: hier laeuft der echte Transit-Notifier
      // (er spricht den Bluetooth-Dienst an).
      final container = transitRadarScreenContainer();
      final router = transitRadarScreenRouter();
      addTearDown(router.dispose);

      await aufbauen(tester, container, router);

      // Der Start fragt zuerst nach der eigenen Beschreibung (zwei
      // Merkmale sind Pflicht).
      await startTippen(tester);
      await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
      await sendenTippen(tester);

      expect(tester.takeException(), isNull);
      expect(
        advertisingStarts,
        greaterThan(0),
        reason:
            'Der Start muss das Advertising wirklich einschalten - sonst '
            'sendet der Radar nichts.',
      );

      // Der Container schliesst den Transit-Notifier - und damit die
      // Timer (der 45-Minuten-Countdown und der Scan-Puls). Das muss
      // VOR dem Testende passieren: die Pruefung auf offene Timer laeuft
      // noch vor den tearDowns.
      container.dispose();

      // Der Scan-Aufruf des Plugins hat einen eigenen Timer (12 s) - der
      // laeuft hier einfach ab.
      await tester.pump(const Duration(seconds: 13));
    });
    group('Die Begegnungsliste', () {
      testWidgets('sie zeigt die gesehenen Geraete', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = FakeTransit();
        transit.begegnungen = [
          TransitEncounter(token: 'token-1', seenAt: DateTime.now()),
          TransitEncounter(
            token: 'token-2',
            seenAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ];
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        // Die Begegnungsliste steht nur im laufenden Radar.
        await radarStarten(tester);

        expect(tester.takeException(), isNull);
        // Beide Geraete stehen da - mit dem Alter ("gerade eben", "vor
        // 5 Min.").
        expect(find.text('gerade eben'), findsOneWidget);
        expect(find.text('vor 5 Min.'), findsOneWidget);
        // Und beide kann der Nutzer gruessen.
        expect(
          find.text(L10n.tWithoutContext('transit.greet')),
          findsNWidgets(2),
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('bei vielen Geraeten steht die Zahl da', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = FakeTransit();
        transit.begegnungen = List<TransitEncounter>.generate(
          12,
          (i) => TransitEncounter(token: 'token-$i', seenAt: DateTime.now()),
        );
        transit.setzeBegegnungszahl(12);
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await radarStarten(tester);

        expect(tester.takeException(), isNull);
        // BEFUND (18.11.2026, gefunden von einem Test): Der Text benutzte
        // "%count"/"%shown" - die App ersetzt aber "{count}"/"{shown}".
        // Der Nutzer sah deshalb literally "%count Personen in der
        // Naehe - du siehst %shown davon.".
        expect(
          find.textContaining('%count'),
          findsNothing,
          reason:
              'Der Platzhalter muss ersetzt sein - sonst steht der '
              'Nutzer vor einem Text mit "%count".',
        );
        expect(find.textContaining('%shown'), findsNothing);
        // Und die Zahlen stehen da.
        expect(find.textContaining('12'), findsWidgets);
        expect(find.textContaining('10'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('ohne Geraete steht der Leerzustand da', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = FakeTransit();
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await radarStarten(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('transit.noEncounters')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('der Gruss wird gesendet', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = FakeTransit();
        transit.begegnungen = [
          TransitEncounter(token: 'token-1', seenAt: DateTime.now()),
        ];
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await radarStarten(tester);

        // Der Gruss-Knopf oeffnet das Blatt mit den Vorschlaegen.
        await knopfTippen(tester, L10n.tWithoutContext('transit.greet'));

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('transit.pingSheetTitle')),
          findsOneWidget,
          reason: 'Das Blatt mit den Vorschlaegen muss aufgehen.',
        );
        expect(
          find.text(L10n.tWithoutContext('transit.preset.wave')),
          findsOneWidget,
        );

        // Einen Vorschlag waehlen und senden.
        await tester.tap(
          find.text(L10n.tWithoutContext('transit.preset.wave')),
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            L10n.tWithoutContext('transit.pingSend'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(
          transit.gruesse,
          hasLength(1),
          reason:
              'Der Gruss muss wirklich raus - sonst sieht die Person '
              'nie, dass jemand in der Naehe war.',
        );
        expect(transit.gruesse.first.messageKey, 'wave');
        // Und der Nutzer bekommt die Bestaetigung.
        expect(find.textContaining('Gruß gesendet'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('die eigene Zeile wandert mit', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = FakeTransit();
        transit.begegnungen = [
          TransitEncounter(token: 'token-1', seenAt: DateTime.now()),
        ];
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await radarStarten(tester);

        await knopfTippen(tester, L10n.tWithoutContext('transit.greet'));

        // Die eigene Zeile eintippen (das Feld im Blatt - der Bildschirm
        // hat noch ein eigenes Eingabefeld).
        await tester.enterText(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          ),
          'Bis gleich im Zug!',
        );
        await tester.pump();
        await tester.tap(
          find.text(L10n.tWithoutContext('transit.preset.wave')),
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            L10n.tWithoutContext('transit.pingSend'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(
          transit.gruesse.first.customLine,
          'Bis gleich im Zug!',
          reason:
              'Die eigene Zeile muss mitgesendet werden - sie ist der '
              'einzige frei formulierte Teil des Grusses.',
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('nach dem Radar bleiben die Begegnungen erreichbar', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final transit = FakeTransit();
        transit.begegnungen = [
          TransitEncounter(
            token: 'token-1',
            seenAt: DateTime.now().subtract(const Duration(minutes: 50)),
          ),
        ];
        // Der Radar ist nicht aktiv, aber es gab Begegnungen.
        transit.setzeBegegnungszahl(1);
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);

        // Der Knopf "in Ruhe finden" steht da - die Begegnungen gehen
        // nach dem Radar nicht verloren.
        await knopfTippen(tester, L10n.tWithoutContext('transit.retainedBtn'));

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('transit.retainedTitle')),
          findsOneWidget,
          reason: 'Das Blatt mit den erhaltenen Begegnungen muss aufgehen.',
        );
        // Und die Begegnung steht drin.
        expect(find.text('vor 50 Min.'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
