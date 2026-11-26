// Die Verbindung des Zufallschats: der Relay-Modus, das Schreiben, der
// Aufbau und das Beenden.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/screens/swipe/parts/zufallchatverbindung.dart 66 offene Zeilen - das
// sind genau die Wege, die im Mobilfunknetz laufen: der Wechsel auf den
// Server-Relay, der Wiederholungs-Versuch beim Handshake und das
// Pausieren im Hintergrund.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Relay-Modus übernimmt, wenn die Direktverbindung scheitert
//     (und die früher geschriebene Nachricht geht nicht verloren),
//   * der Relay-Takt holt die Nachrichten auch ohne Ping ab,
//   * eine getippte Nachricht erscheint sofort im Verlauf,
//   * der Verbindungsaufbau wird wiederholt (und gedrosselt),
//   * das Beenden fragt nach, lässt sich abbrechen und geht danach
//     wirklich zur Modus-Auswahl,
//   * der Wechsel in den Hintergrund pausiert die Suche.
//
// OHNE ECHTE GERÄTE: Der Zufallschat-Dienst, der P2P-Dienst und der
// Relay-Dienst sind Hand-Attrappen (siehe zufallchat_hilfen.dart). Es
// geht keine Anfrage ins Netz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/random_chat_session.dart';
import 'package:thestia/providers/chat/chat_provider.dart';

import '../support/plugin_mocks.dart';
import 'zufallchat_hilfen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: die verschlüsselten Schlüssel (Signal-Protokoll) liegen in
    // Hive-Boxen - ohne sie bleibt der Aufbau hängen.
    await mockHive();
    await initZufallChatServer();
  });

  setUp(() {
    zufallChatServer.zeilen.clear();
    zufallChatServer.rpcAntworten.clear();
    zufallChatServer.rpcAufrufe.clear();
  });

  group('Der Relay-Modus (kein direkter Kanal)', () {
    testWidgets('die App schaltet auf den Server um und sagt es', (
      tester,
    ) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      // Eine Nachricht, die vor dem offenen Kanal geschrieben wurde.
      aufbau.p2p.outbox.add('Frueher geschrieben');

      // DER ICE-FEHLER: Mobilfunk/CGNAT - die direkte Verbindung geht
      // nicht auf.
      aufbau.p2p.iceZustand.add(
        RTCIceConnectionState.RTCIceConnectionStateFailed,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Der Nutzer muss erfahren, dass der Chat über den Server läuft.
      expect(
        find.text(L10n.tWithoutContext('random.relayNoDirect')),
        findsOneWidget,
        reason:
            'Ohne Direktverbindung laeuft der Chat ueber den Server - der '
            'Nutzer muss das wissen, sonst denkt er, die App haenge.',
      );
      // Und die Statuszeile zeigt den Relay-Modus.
      expect(
        find.text(L10n.tWithoutContext('random.relayStatus')),
        findsOneWidget,
      );
      // Die früher geschriebene Nachricht ist nicht verloren gegangen:
      // sie wurde über den Server nachgeliefert.
      expect(
        aufbau.relay.abgelegt,
        contains('Frueher geschrieben'),
        reason:
            'Eine Nachricht, die vor dem offenen Kanal geschrieben wurde, '
            'darf nicht verloren gehen - der Server-Relay ist der Ersatzweg.',
      );

      // Und kommt die Direktverbindung doch noch zustande, geht der Chat
      // wieder auf den direkten Weg zurück.
      aufbau.p2p.kanalOeffnen();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('Verbunden'),
        findsOneWidget,
        reason:
            'Wenn die Direktverbindung doch noch zustande kommt, muss der '
            'Chat wieder darauf laufen - der Server waere sonst nur eine '
            'Umleitung.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('der Relay-Takt holt die Nachrichten ab', (tester) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      aufbau.p2p.iceZustand.add(
        RTCIceConnectionState.RTCIceConnectionStateFailed,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final abholungenVorher = aufbau.relay.abholungen;

      // DER Takt: Auch ohne Wake-up-Ping holt der Timer die Nachrichten
      // ab - sonst kännte eine verlorene Meldung ewig liegen.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        aufbau.relay.abholungen,
        greaterThan(abholungenVorher),
        reason:
            'Der Relay-Takt muss regelmaessig abholen - ein verlorener Ping '
            'darf keine Nachricht kosten.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Das Schreiben im Zufallschat', () {
    testWidgets('eine getippte Nachricht erscheint sofort', (tester) async {
      await baueZufallChat(tester, sitzung: partnerSession);

      // Die eigene Tastatur öffnen und tippen.
      //
      // KEIN pumpAndSettle: In der Statuszeile läuft ein Ladekreis -
      // der dreht sich endlos, also kommt pumpAndSettle nie zur Ruhe.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('h'));
      await tester.tap(find.text('i'));
      await tester.pump();

      // Senden.
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text('hi'),
        findsOneWidget,
        reason:
            'Die eigene Nachricht muss sofort sichtbar sein - der Nutzer '
            'darf nicht denken, sie sei nicht angekommen.',
      );

      // Das Zeitlimit des Edge-Funktions-Aufrufs (20 Sekunden) ablaufen
      // lassen: der Aufruf läuft im Test weiter, sonst bliebe ein Timer
      // stehen und der Test scheiterte an "A Timer is still pending".
      await tester.pump(const Duration(seconds: 21));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Der Verbindungsaufbau', () {
    testWidgets('der Aufbau wird wiederholt, wenn er nicht klappt', (
      tester,
    ) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      // Die Sitzung lebt noch - nur so fragt der Status-Takt weiter.
      aufbau.dienst.befragt = partnerSession;
      aufbau.p2p.fehler = 'Der Aufbau klappt nicht';

      // Der Status-Poll tickt alle fünf Sekunden und versucht es
      // erneut - das erste Offer geht leicht ins Leere, wenn der Peer
      // noch nicht mitlauscht.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        aufbau.p2p.wiederholungen,
        greaterThan(0),
        reason:
            'Der Aufbau muss wiederholt werden - sonst bleibt der Chat '
            'lange ohne Verbindung, wenn das erste Offer ins Leere ging.',
      );

      // Der zweite Versuch ist gedrosselt (höchstens alle 25 Sekunden).
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        aufbau.p2p.wiederholungen,
        1,
        reason:
            'Der Handshake-Versuch muss gedrosselt sein - sonst feuert die '
            'App im Sekundentakt Anfragen an den Server.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('der Partner liefert noch kein Buendel: die App wartet', (
      tester,
    ) async {
      await baueZufallChat(
        tester,
        sitzung: partnerSession,
        fehler: '404 Partner hat noch kein Buendel',
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.waitingForPartner')),
        findsOneWidget,
        reason:
            'Fehlt das Buendel des Partners, ist das KEIN Fehler - die App '
            'wartet freundlich und versucht es erneut.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('ein Fehler beim Aufbau wird gemeldet', (tester) async {
      await baueZufallChat(
        tester,
        sitzung: partnerSession,
        fehler: 'Kein Netz',
      );

      expect(tester.takeException(), isNull);
      final erwartet = L10n.tWithoutContext(
        'random.connectFailed',
      ).replaceAll('{error}', 'Bad state: Kein Netz');
      expect(
        find.text(erwartet),
        findsOneWidget,
        reason:
            'Ein Fehler beim Aufbau muss sichtbar sein - der Nutzer soll '
            'wissen, dass es an der Verbindung liegt und nicht an ihm.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Das Beenden des Zufallschats', () {
    testWidgets('der Zurueck-Knopf fragt nach dem Beenden', (tester) async {
      await baueZufallChat(tester, sitzung: partnerSession);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.leaveTitle')),
        findsOneWidget,
        reason:
            'Der Zurueck-Knopf muss genauso fragen wie der Block-Knopf - '
            'sonst beendet der Nutzer den Chat aus Versehen.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('das System-Zurueck fragt nach dem Beenden', (tester) async {
      await baueZufallChat(tester, sitzung: partnerSession);

      // Das System-Zurück (der Randwisch oder der Zurück-Knopf des
      // Systems). `maybePop()` ist der Weg, der den PopScope beachtet.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.leaveTitle')),
        findsOneWidget,
        reason:
            'Auch das Wischen vom Rand muss fragen - der Partner bleibt sonst '
            'auf der Plattform stehen.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('das Abbrechen laesst den Chat stehen', (tester) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      await tester.tap(find.byIcon(Icons.block));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      // Der Dialog nennt, was passiert - der Nutzer soll wissen, worauf er
      // sich einlässt.
      expect(
        find.text(L10n.tWithoutContext('random.leaveBody')),
        findsOneWidget,
      );

      // Abbrechen.
      await tester.tap(
        find.widgetWithText(TextButton, L10n.tWithoutContext('common.cancel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      // Der Chat steht noch - das Beenden wurde abgebrochen.
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(aufbau.container.read(activeChatIdProvider), 'session-1');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('nach dem Beenden geht es zur Modus-Auswahl', (tester) async {
      await baueZufallChat(tester, sitzung: partnerSession);

      await tester.tap(find.byIcon(Icons.block));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('random.leaveConfirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Modus-Auswahl'),
        findsOneWidget,
        reason:
            'Nach dem Beenden muss der Nutzer wieder eine Auswahl sehen - '
            'sonst steht er auf einem leeren Bildschirm.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Der Wechsel in den Hintergrund', () {
    testWidgets('die Suche pausiert und laeuft weiter', (tester) async {
      // Die Sitzung wartet noch auf einen Partner (kein Match) - dann
      // läuft die Suche (der Poll-Timer).
      final aufbau = await baueZufallChat(
        tester,
        sitzung: const RandomChatSession(sessionId: 'session-wartend'),
      );
      expect(aufbau.dienst.beitritte, greaterThan(0));

      // In den Hintergrund: die Abfragen stoppen.
      setzeLebenszyklus(tester, AppLifecycleState.paused);
      await tester.pump();
      final abfragenVorher = aufbau.dienst.abfragen;
      await tester.pump(const Duration(seconds: 5));
      expect(
        aufbau.dienst.abfragen,
        abfragenVorher,
        reason:
            'Im Hintergrund darf die App nicht pollen - das kostet Akku und '
            'das Netz.',
      );

      // Und wieder in den Vordergrund: die Suche läuft weiter.
      setzeLebenszyklus(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(
        aufbau.dienst.abfragen,
        greaterThan(abfragenVorher),
        reason:
            'Nach der Rueckkehr muss die Suche weiterlaufen - sonst wartet '
            'der Nutzer vergebens auf einen Partner.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('im Chat laeuft der Status-Takt nach der Rueckkehr weiter', (
      tester,
    ) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);
      // Die Sitzung lebt noch - nur so fragt der Status-Takt weiter.
      aufbau.dienst.befragt = partnerSession;

      // In den Hintergrund: der Status-Takt stoppt.
      setzeLebenszyklus(tester, AppLifecycleState.paused);
      await tester.pump();
      final abfragenVorher = aufbau.dienst.abfragen;
      await tester.pump(const Duration(seconds: 6));
      expect(
        aufbau.dienst.abfragen,
        abfragenVorher,
        reason:
            'Im Hintergrund darf die App nicht pollen - das kostet Akku und '
            'das Netz.',
      );

      // Und wieder in den Vordergrund: der Takt läuft weiter.
      setzeLebenszyklus(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(
        aufbau.dienst.abfragen,
        greaterThan(abfragenVorher),
        reason:
            'Nach der Rueckkehr muss der Status-Takt weiterlaufen - sonst '
            'faellt die Erkennung "der Partner ist gegangen" aus.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('im Relay-Modus laeuft der Relay-Takt weiter', (tester) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      // Der Relay-Modus (die Direktverbindung geht nicht auf).
      aufbau.p2p.iceZustand.add(
        RTCIceConnectionState.RTCIceConnectionStateFailed,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // In den Hintergrund: der Relay-Takt stoppt.
      setzeLebenszyklus(tester, AppLifecycleState.paused);
      await tester.pump();
      final abholungenVorher = aufbau.relay.abholungen;
      await tester.pump(const Duration(seconds: 3));
      expect(aufbau.relay.abholungen, abholungenVorher);

      // Und wieder in den Vordergrund: der Takt läuft weiter.
      setzeLebenszyklus(tester, AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(
        aufbau.relay.abholungen,
        greaterThan(abholungenVorher),
        reason:
            'Nach der Rueckkehr muss der Relay-Takt weiterlaufen - sonst '
            'bleiben die Nachrichten des Partners liegen, bis der Chat neu '
            'geoeffnet wird.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Der Fehlerfall', () {
    testWidgets('ohne Partner kommt der Hinweis statt Warten', (tester) async {
      // Der Dienst liefert nichts - auch beim zweiten Versuch nicht.
      await baueZufallChat(tester, sitzung: null);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('random.errorNoPartner')),
        findsOneWidget,
        reason:
            'Ohne Partner muss der Zustand erkennbar sein - endloses Warten '
            'sieht wie ein Fehler aus.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
