// Die Tests 'transit_radar_screen' (Teil 2).
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
import 'package:thestia/widgets/funke_overlay.dart';
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
    group('Der Lauscher auf den spaeten Funken', () {
      testWidgets('ein frischer Funke wird angezeigt', (tester) async {
        // Der Server meldet einen FRISCHEN Funken - das ist der Fall, den
        // der Lauscher fangen soll: der Partner hat (fast gleichzeitig)
        // auch gedrueckt, der Funke entstand aber erst danach.
        server.rpcAntworten['list_my_matches_with_state'] = <dynamic>[
          <String, dynamic>{
            'matchId': 99,
            'status': 'active',
            // DER WEG: Ein DEUTLICH spaeterer Zeitstempel. Der Lauscher
            // vergleicht mit `now - 2s` - unter Parallel last vergehen
            // zwischen diesem Setzen und dem Start des Lauschers mehr als
            // zwei Sekunden, dann gilt der Funke als "alt" und das Overlay
            // bleibt aus (genau das flakte nach dem Aufteilen der Datei).
            'createdAt': DateTime.now()
                .add(const Duration(seconds: 30))
                .toIso8601String(),
            'profile': <String, dynamic>{'id': 'partner-9', 'name': 'Mira'},
          },
        ];

        final transit = FakeTransit();
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);

        // Den Radar starten und das Signal senden - danach lauscht die
        // App auf einen spaeter entstehenden Funken.
        await startTippen(tester);
        await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
        await sendenTippen(tester);
        await knopfTippen(tester, 'Blicke getauscht');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await merkmaleWaehlen(tester, ['Haarfarbe', 'Haarlänge']);
        await sendenTippen(tester);

        expect(tester.takeException(), isNull);

        // Der Lauscher tickt alle drei Sekunden.
        await tester.pump(const Duration(seconds: 4));
        await serverAntwortAbwarten(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        // Die Funke-Animation steht da - sonst haette der Nutzer den
        // Funke nicht mitbekommen.
        expect(
          find.byType(FunkeOverlay),
          findsOneWidget,
          reason:
              'Ein Funke, der erst nach dem Signal entsteht, muss trotzdem '
              'angezeigt werden.',
        );

        // Die Animation schliesst sich nach 1,2 s von selbst - der Timer
        // darf am Testende nicht mehr laufen.
        await tester.pump(const Duration(milliseconds: 1300));
        await tester.pumpWidget(const SizedBox());
      });
    });
    group('Die Erinnerung nach dem Radar', () {
      testWidgets('sie kommt, wenn der Radar gestoppt wird', (tester) async {
        final transit = FakeTransit();
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await radarStarten(tester);

        // Der Radar laeuft - jetzt stoppen. Danach fragt die App, ob
        // Bluetooth/Standort ausgeschaltet werden sollen.
        await knopfTippen(tester, L10n.tWithoutContext('transit.stop'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(L10n.tWithoutContext('transit.cleanupTitle')),
          findsOneWidget,
          reason:
              'Nach dem Radar soll die App ans Ausschalten erinnern - der '
              'Nutzerwunsch war genau das ("Erinnerung fehlt").',
        );

        await tester.pumpWidget(const SizedBox());
      });
    });
    group('Der Posteingang der Grueesse', () {
      /// Stellt einen Gruss in den Posteingang.
      void stelleGruess({String? name = 'Mira'}) {
        server.rpcAntworten['list_my_soft_pings'] = <dynamic>[
          <String, dynamic>{
            'id': 'ping-1',
            'messageKey': 'wave',
            'customLine': '',
            'createdAt': DateTime.now().toIso8601String(),
            'expiresAt': DateTime.now()
                .add(const Duration(hours: 48))
                .toIso8601String(),
            'senderName': name,
            'placeKind': 'train',
            'placeText': 'Wagen 3',
          },
        ];
      }

      testWidgets('der Gruss steht da', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        stelleGruess();

        final transit = FakeTransit();
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await serverAntwortAbwarten(tester);

        expect(tester.takeException(), isNull);
        // Der Gruss steht da - mit dem Namen des Absenders (er hat ihn
        // freigegeben) und mit dem Ort, damit der Nutzer weiss, wo er
        // suchen soll.
        expect(find.textContaining('Mira'), findsWidgets);
        expect(find.text('Wagen 3'), findsOneWidget);
        // Und der Vorschlagstext.
        expect(
          find.text(L10n.tWithoutContext('transit.preset.wave')),
          findsOneWidget,
        );
        // Die beiden Wege stehen bereit.
        expect(
          find.text(L10n.tWithoutContext('transit.accept')),
          findsOneWidget,
        );
        expect(
          find.text(L10n.tWithoutContext('transit.ignore')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('ohne freigegebenen Namen bleibt der Gruss anonym', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Der Absender hat seinen Namen NICHT freigegeben.
        stelleGruess(name: null);

        final transit = FakeTransit();
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await serverAntwortAbwarten(tester);

        expect(tester.takeException(), isNull);
        expect(
          find.text(L10n.tWithoutContext('transit.waveFromAnonymous')),
          findsOneWidget,
          reason:
              'Ohne freigegebenen Namen bleibt der Absender anonym - '
              'das ist der Normalzustand.',
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('ein Gruss laesst sich annehmen', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        stelleGruess();
        // Die Annahme liefert den neuen Funken (ohne Chat-ID).
        server.rpcAntworten['accept_soft_ping'] = <String, dynamic>{
          'matched': true,
          'match_id': 0,
        };

        final transit = FakeTransit();
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await serverAntwortAbwarten(tester);

        await knopfTippen(tester, L10n.tWithoutContext('transit.accept'));
        await serverAntwortAbwarten(tester);

        expect(tester.takeException(), isNull);
        // Die Funktion wurde wirklich aufgerufen.
        expect(
          server.rpcAufrufe.any((c) => c['funktion'] == 'accept_soft_ping'),
          isTrue,
          reason:
              'Ohne die Annahme beim Server entsteht kein Funke - der '
              'Nutzer bleibt ohne Antwort.',
        );
        // Und der Nutzer erfaehrt, was passiert ist.
        expect(
          find.textContaining(L10n.tWithoutContext('transit.acceptDone')),
          findsWidgets,
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('ein Gruss laesst sich ausblenden - erst nach Rueckfrage', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        stelleGruess();

        final transit = FakeTransit();
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await serverAntwortAbwarten(tester);

        // BEFUND (07.11.2026, Betreiber): "Funke wurde angezeigt, ist dann
        // aber wieder verschwunden." Das Ausblenden LOESCHT die Zeile -
        // und der Knopf sitzt genau dort, wo der Finger schon liegt.
        // Deshalb fragt die App vorher nach.
        await knopfTippen(tester, L10n.tWithoutContext('transit.ignore'));

        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason:
              'Ohne Rueckfrage waere der Gruss weg - und der Nutzer '
              'haette es nicht gewollt.',
        );
        expect(
          find.text(L10n.tWithoutContext('transit.ignoreConfirmTitle')),
          findsOneWidget,
        );

        // Bestaetigen: dann loescht die App wirklich.
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            L10n.tWithoutContext('transit.ignoreConfirmOk'),
          ),
        );
        await tester.pump();
        await serverAntwortAbwarten(tester);

        expect(tester.takeException(), isNull);
        expect(
          server.schreibvorgaenge.any(
            (v) => v['tabelle'] == 'transit_soft_pings',
          ),
          isTrue,
          reason: 'Das Ausblenden muss die Zeile beim Server loeschen.',
        );

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('ohne Rueckfrage wird nichts geloescht', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        stelleGruess();

        final transit = FakeTransit();
        final container = transitRadarScreenContainer(transit: transit);
        addTearDown(container.dispose);
        final router = transitRadarScreenRouter();
        addTearDown(router.dispose);

        await aufbauen(tester, container, router);
        await serverAntwortAbwarten(tester);

        await knopfTippen(tester, L10n.tWithoutContext('transit.ignore'));
        // "Abbrechen" - der Gruss bleibt.
        await tester.tap(
          find.widgetWithText(
            TextButton,
            L10n.tWithoutContext('common.cancel'),
          ),
        );
        await tester.pump();
        await serverAntwortAbwarten(tester);

        expect(tester.takeException(), isNull);
        expect(
          server.schreibvorgaenge.any(
            (v) => v['tabelle'] == 'transit_soft_pings',
          ),
          isFalse,
          reason: 'Ohne Bestaetigung wird nichts geloescht.',
        );
        // Und der Gruss steht noch da.
        expect(find.textContaining('Mira'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
