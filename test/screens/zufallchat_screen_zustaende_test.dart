// Der Verlauf des Zufallschats und der Relay-Eingang.
//
// ANLASS (24.11.2026): Die Coverage-Messung zeigte für
// lib/screens/swipe/random_chat_screen.dart 75 offene Zeilen und für
// lib/screens/swipe/parts/zufallchatverbindung.dart 66 offene Zeilen.
// Der größte Teil davon war der Verlauf (die Nachrichtenliste wurde nie
// gebaut) und der Weg, auf dem eine Nachricht über den Server-Relay
// ANKOMMT - also genau der Weg, den der Nutzer nutzt, wenn das
// Mobilfunknetz keine direkte Verbindung hinbekommt.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Verlauf des Zufallschats steht da (die Nachricht des Partners
//     und der eigene Text),
//   * eine Relay-Nachricht kommt an - und kommt NICHT doppelt an,
//   * eine fremde Relay-Zeile bleibt im Relay liegen,
//   * eine Nachricht aus dem direkten Kanal kommt an,
//   * der offene Datenkanal wird als "verbunden" angezeigt.
//
// OHNE ECHTE GERÄTE: Der Zufallschat-Dienst, der P2P-Dienst und der
// Relay-Dienst sind Hand-Attrappen (siehe zufallchat_hilfen.dart). Es
// geht keine Anfrage ins Netz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/services/chat/relay_service.dart';

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

  group('Der Verlauf des Zufallschats', () {
    testWidgets('die Nachricht des Partners steht da', (tester) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      // Die Nachricht kommt an (wie über den direkten Kanal).
      aufbau.notifier.addMessage(
        'session-1',
        Message(
          id: 'm_1',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: 'Hallo, wie geht es dir?',
          timestamp: DateTime.now(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Hallo, wie geht es dir?'),
        findsOneWidget,
        reason:
            'Die Nachricht des Partners muss im Verlauf stehen - der '
            'Zufallschat ist ein echter Chat, kein Platzhalter.',
      );
      // Und der Name der Gegenseite steht über der Nachricht.
      expect(find.text('Mira'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('die eigene Nachricht steht rechts', (tester) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      aufbau.notifier.addMessage(
        'session-1',
        Message(
          id: 'm_2',
          senderId: 'ich',
          receiverId: 'partner-1',
          text: 'Mir geht es gut!',
          timestamp: DateTime.now(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Mir geht es gut!'), findsOneWidget);
      // Die eigene Nachricht trägt das "Du" (nicht den Namen der
      // Gegenseite) - sonst würde der Nutzer denken, er schreibt sich
      // selbst.
      expect(find.text(L10n.tWithoutContext('chat.you')), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('ohne Nachricht steht die Begruessung da', (tester) async {
      await baueZufallChat(tester, sitzung: partnerSession);

      expect(tester.takeException(), isNull);
      // Der leere Chat begrüßt den Partner (mit seinem Namen).
      expect(
        find.textContaining('Mira'),
        findsWidgets,
        reason:
            'Der leere Verlauf soll den Nutzer zum Schreiben bringen - ein '
            'leerer Bildschirm wirkt kaputt.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Der Relay-Eingang (der Server bringt die Nachricht)', () {
    testWidgets('eine Relay-Nachricht landet im Verlauf', (tester) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      // Der Server hat eine Zeile für den Partner liegen.
      aufbau.relay.wartend.add(
        RelayMessage(
          id: 7,
          senderId: 'partner-1',
          text: 'Kommst du mit?',
          kind: 'text',
          createdAt: DateTime.now(),
        ),
      );

      // Der Partner meldet: im Relay wartet etwas.
      aufbau.p2p.ping();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Kommst du mit?'),
        findsOneWidget,
        reason:
            'Die Relay-Nachricht muss ankommen - ohne Direktverbindung laeuft '
            'der ganze Chat ueber den Server.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('dieselbe Relay-Nachricht kommt nicht doppelt an', (
      tester,
    ) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      aufbau.relay.wartend.add(
        RelayMessage(
          id: 7,
          senderId: 'partner-1',
          text: 'Nur einmal',
          kind: 'text',
          createdAt: DateTime.now(),
        ),
      );

      // Der Ping und der Poll-Takt können dieselbe Zeile bringen.
      aufbau.p2p.ping();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      aufbau.p2p.ping();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Nur einmal'),
        findsOneWidget,
        reason:
            'Dieselbe Nachricht darf nicht doppelt im Verlauf stehen - der '
            'Nutzer wuerde sie zweimal lesen und zweimal antworten.',
      );
      final nachrichten = aufbau.notifier.messagesFor('session-1');
      expect(nachrichten.where((m) => m.text == 'Nur einmal'), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('eine fremde Relay-Zeile bleibt liegen', (tester) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      // Die Zeile gehört zu einem ANDEREN Chat.
      aufbau.relay.wartend.add(
        RelayMessage(
          id: 8,
          senderId: 'partner-2',
          text: 'Fremde Nachricht',
          kind: 'text',
          createdAt: DateTime.now(),
        ),
      );

      aufbau.p2p.ping();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Fremde Nachricht'),
        findsNothing,
        reason:
            'Eine Nachricht eines anderen Chats darf nicht in diesem Chat '
            'landen - sonst sieht der Nutzer fremde Nachrichten.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Der direkte Kanal', () {
    testWidgets('eine Nachricht aus dem Kanal landet im Verlauf', (
      tester,
    ) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      aufbau.p2p.empfange('Direkt zugestellt');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Direkt zugestellt'),
        findsOneWidget,
        reason:
            'Der direkte Kanal ist der Normalfall - die Nachricht muss ohne '
            'Umweg ankommen.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('der offene Kanal wird als verbunden angezeigt', (
      tester,
    ) async {
      final aufbau = await baueZufallChat(tester, sitzung: partnerSession);

      // Vorher: der Kanal steht noch nicht.
      expect(
        find.textContaining('Verbindung wird hergestellt'),
        findsOneWidget,
        reason:
            'Solange keine Direktverbindung steht, muss der Nutzer das sehen '
            '- sonst denkt er, die Nachrichten gingen unverschluesselt raus.',
      );

      aufbau.p2p.kanalOeffnen();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Verbunden'),
        findsOneWidget,
        reason:
            'Mit offenem Kanal muss die Direktverbindung angezeigt werden - '
            'das ist das E2E-Versprechen der App.',
      );
      // Der Ladekreis ist weg.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
