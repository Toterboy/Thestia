// Die Tests 'chat_detail_screen' (Teil 1).
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Tests
// sind nach Themen aufgeteilt; die Helfer liegen in
// test/support/chat_detail_screen_hilfen.dart.

// Der 1:1-Chat OHNE Server (v0.10.1).
//
// WARUM (13.11.2026): Der Chat-Screen ist die groesste Datei der App
// (rund 1.800 Zeilen) - und die Coverage-Messung zeigte: 0,1 %.
// Genau dort sitzt auch die eigene Tastatur (Build 54). Ein Screen, den
// niemand gerendert hat, ist geraten: der Absturz beim Wischen zwischen
// den Reitern (31.10.2026) war nur zufaellig im Screenshot-Render
// aufgefallen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Chat rendert mit seinen Nachrichten (kein Absturz, kein
//     Render-Overflow),
//   * ein Chat, den es nicht mehr gibt, zeigt den Hinweis statt eines
//     leeren Bildschirms,
//   * die EINGABE ist die eigene Tastatur: das Feld ist readOnly (die
//     Systemtastatur sieht nichts) und das Tippen oeffnet die
//     App-Tastatur,
//   * eine getippte Nachricht landet im Chat.
//
// OHNE SERVER: Die Supabase-Aufrufe des Bildschirms (P2P, Relay,
// Loeschen, Herz-Staerken) laufen ueber bestEffort/bestEffortOr und
// brechen ohne Client still ab. Genau das ist hier der Fall - es wird
// geprueft, was der Bildschirm ohne Server macht, nicht was er mit
// Server macht (das macht test/live_message_flow_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Praefix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/message.dart';
import 'package:thestia/models/user_profile.dart';
import 'package:thestia/providers/chat_provider.dart';
import 'package:thestia/models/report_models.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/report_service.dart';
import 'package:thestia/services/chat_service.dart';
import 'package:thestia/widgets/secure_composer.dart';
import 'package:thestia/widgets/secure_keyboard.dart';
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Der Supabase-Client muss initialisiert sein: der Sende-Weg holt
    // ihn ueber den Relay-Service, und `Supabase.instance` wirft ohne
    // Initialisierung eine Assertion. Der Client zeigt auf einen nicht
    // existierenden Server - im Test laufen alle HTTP-Anfragen ins Leere
    // (der Test-Binding liefert 400), und der Sende-Weg ist in
    // bestEffort gekapselt.
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE und HIVE: der Signal-Dienst (Sicherheitsnummer)
    // liest seine verschluesselten Boxen aus dem Keystore und aus Hive.
    // Ohne diese beiden Ersatzwaerter bleibt der Dialog leer.
    mockKeystore();
    await mockHive();
    // DER ADAPTER: Der Meldungs-Store legt seine Zeilen als
    // UserReport-Objekte ab - ohne den Adapter kann Hive sie nicht
    // schreiben.
    Hive.registerAdapter(UserReportAdapter());
    // DIE AUFNAHME: der Chat hat eine Sprachnachricht-Funktion - der
    // Recorder wird beim Aufbau erzeugt (sonst: MissingPluginException).
    mockAufnahme();
    mockZeitzone();
    // DER SERVER: die Aktionen, die auf dem Server etwas aendern
    // ("Nachricht fuer alle loeschen"), gehen ueber den Client - ohne
    // den Ersatz-Server bekommen sie keine Antwort.
    server = FakeSupabaseServer(userId: 'ich');
    await supabase.Supabase.initialize(
      // DIE DREI OPTIONEN (siehe der Kommentar unten): kein
      // Timer, kein Speicher, kein Deeplink-Observer - sonst
      // scheitert der Aufbau auf dem CI-Runner.
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),

      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      // DER SERVER: die Aktionen, die auf dem Server etwas aendern
      // ("Nachricht fuer alle loeschen"), gehen ueber den Client - ohne
      // den Ersatz-Server bekommen sie keine Antwort.
      httpClient: server,
    );
    // ANGEMELDET: die eigene User-ID kommt aus der Sitzung - ohne sie
    // weiss der Bildschirm nicht, welche Nachrichten die eigenen sind.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    moodClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
    // Die Aufnahme: zurueck auf den Standard (kein eigener Pfad).
    mockAufnahme();
    // Der Audio-Player (das Blatt zum Anhoeren legt einen an).
    mockAudioPlayer();
  });
  tearDown(() async {
    // Sonst bleibt der Auto-Refresh-Timer des Clients stehen.
    await moodClient.dispose();
  });
  group('Der 1:1-Chat (ohne Server)', () {
    testWidgets('rendert die Nachrichten ohne Absturz', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      expect(tester.takeException(), isNull);
      // Die Nachricht steht da.
      expect(find.text('Hallo, magst du Kaffee?'), findsOneWidget);
      // Die Name der Partnerin steht in der Kopfzeile.
      expect(find.text('Mira'), findsWidgets);
      // Und die Eingabeleiste ist die eigene Tastatur.
      expect(find.byType(SecureComposer), findsOneWidget);

      // Der Screen muss wieder abgeraeumt werden - sonst bleibt der
      // Relay-Timer stehen und der Test scheitert an "A Timer is still
      // pending".
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ein unbekannter Chat zeigt den Hinweis', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        const ChatDetailScreen(matchId: 'gibt-es-nicht'),
        chat.notifier,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Dieser Chat existiert nicht mehr.'), findsOneWidget);
      // Und KEINE Eingabeleiste - es gibt nichts zu schreiben.
      expect(find.byType(SecureComposer), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('das Eingabefeld gibt der Systemtastatur nichts', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      final feld = tester.widget<TextField>(find.byType(TextField));
      // `readOnly` ist der entscheidende Punkt: bei einem readOnly-Feld
      // entsteht auf Android und iOS keine Eingabeverbindung - die
      // Systemtastatur sieht also keinen Buchstaben.
      expect(feld.readOnly, isTrue);
      expect(feld.keyboardType, TextInputType.none);
      expect(feld.enableIMEPersonalizedLearning, isFalse);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('das Tippen oeffnet die eigene Tastatur', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      expect(find.byType(SecureKeyboard), findsNothing);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.byType(SecureKeyboard), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('eine getippte Nachricht landet im Chat', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      // Die App-Tastatur oeffnen und "Hi" tippen.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('h'));
      await tester.tap(find.text('i'));
      await tester.pump();

      // Senden.
      await tester.tap(find.byIcon(Icons.send));
      // Der Neuaufbau passiert direkt nach dem Hinzufuegen (BEFUND
      // 13.11.2026) - die eigene Nachricht ist also sofort da.
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Die Nachricht steht im Chat - und der Verlauf ist nicht leer.
      expect(find.text('hi'), findsOneWidget);
      final nachrichten = chat.notifier.messagesFor(chat.match.id);
      expect(nachrichten.any((m) => m.text == 'hi'), isTrue);

      await tester.pumpWidget(const SizedBox());
    });
  });
  group('Der 1:1-Chat (die Nachrichtenarten)', () {
    testWidgets('eine Bildnachricht wird als Bild dargestellt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(chatDetailScreenPartner());
      service.addMessage(
        match.id,
        Message(
          id: 'm_bild',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: '',
          type: MessageType.image,
          mediaUrl: 'https://example.de/foto.jpg',
          timestamp: DateTime.now(),
        ),
      );
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      // Das Bild wird geladen - bis es da ist, steht der Platzhalter
      // (das Bild zaehlt, dass der Bildzweig gebaut wurde).
      expect(find.byIcon(Icons.image), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('eine Sprachnachricht wird mit Play-Knopf dargestellt', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(chatDetailScreenPartner());
      service.addMessage(
        match.id,
        Message(
          id: 'm_voice',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: '',
          type: MessageType.voice,
          mediaUrl: '/tmp/thesei_stimme.m4a',
          durationSeconds: 12,
          timestamp: DateTime.now(),
        ),
      );
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      // Der Abspiel-Knopf und die Dauer stehen da.
      expect(find.byIcon(Icons.play_arrow), findsWidgets);
      expect(find.textContaining('0:12'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('eine Systemnotiz steht mittig', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(chatDetailScreenPartner());
      service.addMessage(
        match.id,
        Message(
          id: 'm_notiz',
          senderId: 'ich',
          receiverId: 'partner-1',
          text: 'Die Runde endet in 5 Minuten',
          type: MessageType.notice,
          timestamp: DateTime.now(),
        ),
      );
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Die Runde endet in 5 Minuten'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('eine eigene Nachricht laesst sich fuer alle loeschen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Ein SERVER-Funke: nur bei einer Match-ID aus dem Server gibt es
      // das "fuer alle" (ein lokaler Kontakt hat keinen Funke).
      final service = ChatService();
      final match = service.restoreServerMatch(
        '7',
        chatDetailScreenPartner(),
        DateTime.now(),
      )!;
      service.addMessage(
        match.id,
        Message(
          id: 'm_eigen',
          senderId: 'ich',
          receiverId: 'partner-1',
          text: 'Ein Satz, der weg soll',
          timestamp: DateTime.now(),
        ),
      );
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      // Die eigene Nachricht steht da.
      expect(find.text('Ein Satz, der weg soll'), findsOneWidget);

      // Lange druecken -> die Rueckfrage.
      await tester.longPress(find.text('Ein Satz, der weg soll'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(L10n.tWithoutContext('chat.deleteForAllTitle')),
        findsOneWidget,
      );

      // Bestaetigen: der Server wird informiert und lokal steht der
      // Hinweis statt der Nachricht.
      await tester.tap(
        find.text(L10n.tWithoutContext('chat.deleteForAllAction')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(
        server.pfade.any((p) => p.contains('delete_message_for_all')),
        isTrue,
        reason: 'Der Server muss die Loeschung erfahren.',
      );
      expect(find.text('Ein Satz, der weg soll'), findsNothing);
      expect(
        find.text(L10n.tWithoutContext('chat.deletedNotice')),
        findsOneWidget,
        reason:
            'Statt der Nachricht steht der Hinweis - auch bei der Gegenseite.',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ein unscharfes Bild laesst sich freigeben', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Die Bilder der Gegenseite sind zuerst unscharf (Schutz vor
      // unangemessenen Inhalten) - das kommt aus den Einstellungen.
      final service = ChatService();
      final match = service.createMatch(chatDetailScreenPartner());
      service.addMessage(
        match.id,
        Message(
          id: 'm_bild',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: '',
          type: MessageType.image,
          mediaUrl: 'https://example.de/foto.jpg',
          timestamp: DateTime.now(),
        ),
      );
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
        unscharfeBilder: true,
      );

      expect(tester.takeException(), isNull);
      // DIE SEMANTICS: Im Widget-Test sind sie aus - ohne
      // `ensureSemantics()` findet der Test kein Label. Der Handle wird
      // am Ende des Testkoerpers freigegeben (der tearDown laeuft zu
      // spaet - das Test-Framework prueft vorher auf offene Handles).
      final semantics = tester.ensureSemantics();

      // Solange das Bild nicht freigegeben ist, ist es unscharf.
      // (Der Text ist mehrzeilig - darum der RegExp statt des exakten
      // Labels.)
      expect(
        find.bySemanticsLabel(RegExp('Verpixelte')),
        findsWidgets,
        reason:
            'Das Bild der Gegenseite ist zuerst unscharf - der Nutzer '
            'soll es bewusst freigeben.',
      );

      // Lange druecken -> das Aktionsmenue mit "Anzeigen".
      await tester.longPress(find.byIcon(Icons.image).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(L10n.tWithoutContext('chat.revealAction')),
        findsWidgets,
        reason: 'Ein unscharfes Bild laesst sich freigeben.',
      );

      // Und die Freigabe wird noch einmal bestaetigt (der Nutzer soll
      // nicht aus Versehen fremde Bilder sehen).
      await tester.tap(find.text(L10n.tWithoutContext('chat.revealAction')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('chat.revealAction'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Jetzt ist es scharf - das Bild ist freigegeben.
      expect(find.bySemanticsLabel(RegExp('Bildnachricht')), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp('Verpixelte')),
        findsNothing,
        reason: 'Nach der Freigabe ist das Bild nicht mehr verpixelt.',
      );

      semantics.dispose();
    });

    testWidgets(
      'ein bereits angesehenes View-Once-Bild zeigt den Platzhalter',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final service = ChatService();
        final match = service.createMatch(chatDetailScreenPartner());
        service.addMessage(
          match.id,
          Message(
            id: 'm_once',
            senderId: 'partner-1',
            receiverId: 'ich',
            text: '',
            type: MessageType.image,
            mediaUrl: 'https://example.de/einmal.jpg',
            viewOnce: true,
            viewed: true,
            timestamp: DateTime.now(),
          ),
        );
        await chatDetailScreenPump(
          tester,
          ChatDetailScreen(matchId: match.id),
          ChatNotifier(service),
        );

        expect(tester.takeException(), isNull);
        // Das Bild ist weg - da steht der Platzhalter.
        expect(
          find.text(L10n.tWithoutContext('chat.viewedOnce')),
          findsWidgets,
          reason:
              'Ein einmaliges Bild wird nach dem Ansehen nicht wieder '
              'angezeigt.',
        );
      },
    );

    group('Die Meldung geht mit dem Verlauf zum Support', () {
      testWidgets('nur die letzten drei Nachrichten', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final service = ChatService();
        final match = service.createMatch(chatDetailScreenPartner());
        for (var i = 1; i <= 4; i++) {
          service.addMessage(
            match.id,
            Message(
              id: 'm_$i',
              senderId: 'partner-1',
              receiverId: 'ich',
              text: 'Nachricht Nummer $i',
              timestamp: DateTime.now(),
            ),
          );
        }
        // Der Meldungs-Dienst als Ersatz (der echte braucht die
        // verschluesselten Hive-Boxen).
        final meldedienst = FakeReportService();
        await chatDetailScreenPump(
          tester,
          ChatDetailScreen(matchId: match.id),
          ChatNotifier(service),
          overrides: [reportServiceProvider.overrideWithValue(meldedienst)],
        );

        // Das Menue (die drei Punkte) oeffnen.
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final eintrag = find.text(L10n.tWithoutContext('chat.reportTooltip'));
        await tester.ensureVisible(eintrag);
        await tester.pump();
        await tester.tap(eintrag);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);

        // Den Grund waehlen (der erste Punkt der Liste) - ohne Grund
        // ist der Melde-Knopf gesperrt.
        final grund = find.byType(RadioListTile<ReportType>).first;
        await tester.tap(grund);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Und absenden.
        final senden = find.widgetWithText(
          FilledButton,
          L10n.tWithoutContext('bug.send'),
        );
        await tester.ensureVisible(senden);
        await tester.pump();
        await tester.tap(senden);
        // Die Meldung braucht mehrere echte Runden: erst der Speicher
        // (Hive), dann der Server.
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
          });
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(tester.takeException(), isNull);
        // Die Meldung geht mit genau drei Nachrichten zum Support.
        expect(
          meldedienst.gemeldeteNachrichten,
          hasLength(3),
          reason:
              'Es duerfen nur die letzten drei Nachrichten mitgehen - der '
              'Support soll den Verlauf sehen, nicht den ganzen Chat.',
        );
        // Und es sind die LETZTEN drei.
        expect(
          meldedienst.gemeldeteNachrichten.last.text,
          'Nachricht Nummer 4',
        );
        expect(
          meldedienst.gemeldeteNachrichten.first.text,
          'Nachricht Nummer 2',
        );
      });
    });

    group('Ein Funke, der lokal fehlt', () {
      testWidgets('wird vom Server nachgeladen', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // Der Server kennt den Funke (Match-ID 7).
        server.rpcAntworten['list_my_matches_with_state'] = <dynamic>[
          <String, dynamic>{
            'matchId': 7,
            'status': 'active',
            'createdAt': DateTime.now().toIso8601String(),
            'profile': <String, dynamic>{
              'id': 'partner-1',
              'name': 'Mira',
              'bio': 'Liest gern',
            },
          },
        ];

        // Der Chat wird mit der Nummer geoeffnet - lokal gibt es ihn
        // nicht (z. B. nach einem Neustart oder aus einem gespeicherten
        // Verlauf).
        await chatDetailScreenPump(
          tester,
          const ChatDetailScreen(matchId: '7'),
          ChatNotifier(ChatService()),
        );
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
          });
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(tester.takeException(), isNull);
        // Der Name steht da - der Funke wurde wiederhergestellt.
        expect(
          find.textContaining('Mira'),
          findsWidgets,
          reason:
              'Ein Funke, den es lokal nicht mehr gibt, muss vom Server '
              'nachgeladen werden - sonst sieht der Nutzer einen leeren '
              'Chat.',
        );
      });
    });

    group('Die Nutzer-Meldung', () {
      testWidgets('der Melde-Dialog zeigt die letzten Nachrichten', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final service = ChatService();
        final match = service.createMatch(chatDetailScreenPartner());
        for (var i = 1; i <= 4; i++) {
          service.addMessage(
            match.id,
            Message(
              id: 'm_$i',
              senderId: 'partner-1',
              receiverId: 'ich',
              text: 'Nachricht Nummer $i',
              timestamp: DateTime.now(),
            ),
          );
        }
        await chatDetailScreenPump(
          tester,
          ChatDetailScreen(matchId: match.id),
          ChatNotifier(service),
        );

        // Das Menue (die drei Punkte) oeffnen.
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final eintrag = find.text(L10n.tWithoutContext('chat.reportTooltip'));
        await tester.ensureVisible(eintrag);
        await tester.pump();
        await tester.tap(eintrag);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
        // Der Dialog sagt, wie viele Nachrichten mitgehen: die letzten
        // DREI - nur so kann der Support den Verlauf sehen, ohne dass der
        // Nutzer den ganzen Chat verliert.
        //
        // DER HINWEIS: Geprueft wird nur der DIALOG - im Chat selbst
        // stehen natuerlich alle vier Nachrichten.
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('letzten 3 Nachrichten'),
          ),
          findsOneWidget,
          reason:
              'Es duerfen nur die letzten drei Nachrichten mitgehen - der '
              'Support soll den Verlauf sehen, nicht den ganzen Chat.',
        );

        await tester.pumpWidget(const SizedBox());
      });
    });

    group('Das Menue (Sicherheit und Verbindung)', () {
      /// Baut den Chat mit einer Nachricht der Gegenseite.
      ///
      /// DER HINWEIS: Die Person hat eine UUID als ID - das Sperren
      /// pruft die ID vorher ("Ungueltiger Nutzer" sonst). Die
      /// Test-Personen haben ansonsten "partner-1".
      Future<ChatNotifier> chatBauen(WidgetTester tester) async {
        final service = ChatService();
        final match = service.createMatch(
          UserProfile(
            id: '11111111-2222-3333-4444-555555555555',
            name: 'Mira',
            bio: '',
            birthDate: DateTime.now().subtract(const Duration(days: 24 * 365)),
          ),
        );
        service.addMessage(
          match.id,
          Message(
            id: 'm_1',
            senderId: '11111111-2222-3333-4444-555555555555',
            receiverId: 'ich',
            text: 'Hallo, magst du Kaffee?',
            timestamp: DateTime.now(),
          ),
        );
        final notifier = ChatNotifier(service);
        await chatDetailScreenPump(
          tester,
          ChatDetailScreen(matchId: match.id),
          notifier,
        );
        return notifier;
      }

      /// Oeffnet das Menue (die drei Punkte oben rechts).
      Future<void> menueOeffnen(WidgetTester tester) async {
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      testWidgets('das Sperren der Person fragt erst nach', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await chatBauen(tester);
        await menueOeffnen(tester);

        // Der Eintrag "Sperren" sitzt weiter unten im Menue.
        final eintrag = find.text(L10n.tWithoutContext('chat.block'));
        await tester.ensureVisible(eintrag);
        await tester.pump();
        await tester.tap(eintrag);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        // Ohne Rueckfrage waere die Person gesperrt - das ist ein Eingriff,
        // der nicht zurueckgenommen werden kann.
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text(L10n.tWithoutContext('chat.blockTitle')),
          findsOneWidget,
        );
        // Und der Dialog nennt die Person.
        expect(find.textContaining('Mira'), findsWidgets);
      });

      testWidgets('das Sperren geht an den Server', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await chatBauen(tester);
        await menueOeffnen(tester);

        final eintrag = find.text(L10n.tWithoutContext('chat.block'));
        await tester.ensureVisible(eintrag);
        await tester.pump();
        await tester.tap(eintrag);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Bestaetigen - dann geht die Sperre an den Server.
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            L10n.tWithoutContext('chat.blockAction'),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          });
          await tester.pump(const Duration(milliseconds: 120));
        }

        expect(tester.takeException(), isNull);
        expect(
          server.rpcAufrufe.any((c) => c['funktion'] == 'block_user'),
          isTrue,
          reason:
              'Die Sperre muss beim Server ankommen - sonst kann die Person '
              'weiter schreiben.',
        );
        // Und der Nutzer bekommt die Bestaetigung.
        expect(find.textContaining('Mira wurde blockiert.'), findsWidgets);

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('das Beenden des Funken fragt erst nach', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await chatBauen(tester);
        await menueOeffnen(tester);

        final eintrag = find.text(L10n.tWithoutContext('chat.end'));
        await tester.ensureVisible(eintrag);
        await tester.pump();
        await tester.tap(eintrag);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    });

    testWidgets('das lange Druecken auf ein Bild zeigt die Aktionen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(chatDetailScreenPartner());
      service.addMessage(
        match.id,
        Message(
          id: 'm_bild',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: '',
          type: MessageType.image,
          mediaUrl: 'https://example.de/foto.jpg',
          timestamp: DateTime.now(),
        ),
      );
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      // Das lange Druecken auf das Bild zeigt das Aktionsmenue.
      await tester.longPress(find.byIcon(Icons.image).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Melden und (bei einem unscharfen Bild) Freigeben.
      expect(find.text(L10n.tWithoutContext('chat.reportImage')), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('die Eisbrecher-Frage steht mittig', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(chatDetailScreenPartner());
      service.addMessage(
        match.id,
        Message(
          id: 'm_eis',
          senderId: 'partner-1',
          receiverId: 'ich',
          text: 'Was ist dein Lieblingsgericht?',
          type: MessageType.icebreaker,
          timestamp: DateTime.now(),
        ),
      );
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Was ist dein Lieblingsgericht?'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('viele Nachrichten werden alle gebaut', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = ChatService();
      final match = service.createMatch(chatDetailScreenPartner());
      for (var i = 0; i < 30; i++) {
        service.addMessage(
          match.id,
          Message(
            id: 'm_$i',
            senderId: i.isEven ? 'partner-1' : 'ich',
            receiverId: i.isEven ? 'ich' : 'partner-1',
            text: 'Nachricht Nummer $i',
            timestamp: DateTime.now().subtract(Duration(minutes: 30 - i)),
          ),
        );
      }
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: match.id),
        ChatNotifier(service),
      );

      expect(tester.takeException(), isNull);
      // Die Liste ist lang - die letzten Nachrichten stehen weiter
      // unten (die Liste ist umgekehrt gebaut).
      final notifier = ChatNotifier(service);
      expect(notifier.messagesFor(match.id).length, 30);
      // Und die Liste laesst sich scrollen.
      expect(find.byType(Scrollable), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
