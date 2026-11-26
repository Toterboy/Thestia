// Die Tests 'chat_detail_screen' (Teil 2).
//
// DER WEG: Die Testdatei war zu lang (> 1000 Zeilen). Die Tests
// sind nach Themen aufgeteilt; die Helfer liegen in
// test/support/chat_detail_screen_hilfen.dart.

// Der 1:1-Chat OHNE Server (v0.10.1).
//
// WARUM (13.11.2026): Der Chat-Screen ist die größte Datei der App
// (rund 1.800 Zeilen) - und die Coverage-Messung zeigte: 0,1 %.
// Genau dort sitzt auch die eigene Tastatur (Build 54). Ein Screen, den
// niemand gerendert hat, ist geraten: der Absturz beim Wischen zwischen
// den Reitern (31.10.2026) war nur zufällig im Screenshot-Render
// aufgefallen.
//
// WAS HIER GEPRÜFT WIRD:
//   * der Chat rendert mit seinen Nachrichten (kein Absturz, kein
//     Render-Overflow),
//   * ein Chat, den es nicht mehr gibt, zeigt den Hinweis statt eines
//     leeren Bildschirms,
//   * die EINGABE ist die eigene Tastatur: das Feld ist readOnly (die
//     Systemtastatur sieht nichts) und das Tippen öffnet die
//     App-Tastatur,
//   * eine getippte Nachricht landet im Chat.
//
// OHNE SERVER: Die Supabase-Aufrufe des Bildschirms (P2P, Relay,
// Löschen, Herz-Stärken) laufen über bestEffort/bestEffortOr und
// brechen ohne Client still ab. Genau das ist hier der Fall - es wird
// geprüft, was der Bildschirm ohne Server macht, nicht was er mit
// Server macht (das macht test/live_message_flow_test.dart).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Präfix, weil supabase_flutter ein eigenes LocalStorage mitbringt.
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/models/verification/report_models.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

import 'hilfen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    // Der Supabase-Client muss initialisiert sein: der Sende-Weg holt
    // ihn über den Relay-Service, und `Supabase.instance` wirft ohne
    // Initialisierung eine Assertion. Der Client zeigt auf einen nicht
    // existierenden Server - im Test laufen alle HTTP-Anfragen ins Leere
    // (der Test-Binding liefert 400), und der Sende-Weg ist in
    // bestEffort gekapselt.
    // DER PFAD-KANAL: sonst ruft der Test auf dem CI-Runner
    // das echte Plugin (das findet dort kein XDG-Verzeichnis).
    await mockPfadProvider();
    // DER KEYSTORE und HIVE: der Signal-Dienst (Sicherheitsnummer)
    // liest seine verschlüsselten Boxen aus dem Keystore und aus Hive.
    // Ohne diese beiden Ersatzwärter bleibt der Dialog leer.
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
    // DER SERVER: die Aktionen, die auf dem Server etwas ändern
    // ("Nachricht für alle löschen"), gehen über den Client - ohne
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
      // DER SERVER: die Aktionen, die auf dem Server etwas ändern
      // ("Nachricht für alle löschen"), gehen über den Client - ohne
      // den Ersatz-Server bekommen sie keine Antwort.
      httpClient: server,
    );
    // ANGEMELDET: die eigene User-ID kommt aus der Sitzung - ohne sie
    // weiß der Bildschirm nicht, welche Nachrichten die eigenen sind.
    await alsNutzerAnmelden(supabase.Supabase.instance.client, 'ich');
  });
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    moodClient = supabase.SupabaseClient(
      'https://example.supabase.co',
      'test-key',
    );
    // Die Aufnahme: zurück auf den Standard (kein eigener Pfad).
    mockAufnahme();
    // Der Audio-Player (das Blatt zum Anhören legt einen an).
    mockAudioPlayer();
  });
  tearDown(() async {
    // Sonst bleibt der Auto-Refresh-Timer des Clients stehen.
    await moodClient.dispose();
  });
  group('Der 1:1-Chat (Menue und Hinweise)', () {
    testWidgets('das Menue zeigt die Gruppenueberschriften', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      // Das Menü öffnen.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // BEFUND (09.11.2026, Betreiber: "Bei 3 Punkte Menü ist über
      // Eisbrecher Fragen ein Strich einfach so aber keine überschrift
      // oder so"): JEDE Gruppe hat eine Überschrift - kein nackter
      // Trennstrich.
      expect(find.text('Gespräch'), findsOneWidget);
      expect(find.text('Sicherheit'), findsOneWidget);
      // Und die wichtigen Eingänge stehen drin.
      expect(find.text('Nutzer melden'), findsOneWidget);
      expect(find.text('Nutzer blockieren'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('der Hinweis auf den Chat-Hintergrund kommt einmal', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      // Der Hinweis ist noch nicht gesehen - er muss kommen.
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        hinweisGesehen: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Chat-Hintergrund'), findsOneWidget);

      // "Später" schließt ihn - und er kommt nicht wieder.
      await tester.tap(find.text('Später'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('das Menue oeffnet die Erinnerungsliste', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Ein SERVER-Funke - nur bei einer Match-ID aus dem Server gibt es
      // die Erinnerungsliste.
      final chat = chatMitNachricht(serverFunke: true);
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Erinnerungsliste'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Das Blatt steht da (ohne Server: keine Einträge, aber der
      // Aufbau muss klappen).
      expect(find.text('Erinnerungsliste'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    // ANMERKUNG: Der Dialog zur Sicherheitsnummer wird hier NICHT
    // getestet. Er braucht den vollständigen Signal-Dienst
    // (Identity-Key, PreKeys, Session-Ratchet) - der lädt im Test
    // seine verschlüsselten Boxen und rechnet, das ist im
    // Widget-Test nicht sinnvoll nachzubauen. Die Sicherheitsnummer
    // selbst hat eigene Tests (test/safety_number_test.dart).

    testWidgets('das Menue beendet den Funke ueber einen Dialog', (
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

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Funke beenden'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // Der Dialog fragt nach - es gibt Absage-Wege, kein sofortiges
      // Ende.
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
  group('Die Sprachnachricht', () {
    testWidgets('das Mikrofon fragt zuerst nach der Offenlegung', (
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

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // DIE OFFENLEGUNG: Google Play verlangt sie VOR der Berechtigung.
      expect(
        find.text(L10n.tWithoutContext('chat.micDisclosureTitle')),
        findsOneWidget,
        reason:
            'Ohne Offenlegung fragt die App das Mikrofon im Hintergrund ab '
            '- das verlangt Google Play nicht.',
      );

      // "Abbrechen" - es wird nichts aufgenommen.
      await tester.tap(find.text(L10n.tWithoutContext('common.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsNothing,
        reason:
            'Ohne Offenlegung wird nicht aufgenommen - sonst nimmt die App '
            'ohne Zutun des Nutzers auf.',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('nach der Offenlegung laeuft die Aufnahme', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.text(L10n.tWithoutContext('chat.micDisclosureAccept')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Die Aufnahme läuft (das Panel steht da).
      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsOneWidget,
      );

      // PAUSE: die Aufnahme hält an.
      await tester.tap(find.text(L10n.tWithoutContext('intro.pause')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(L10n.tWithoutContext('intro.pausedState')),
        findsOneWidget,
        reason:
            'Die Pause muss am Panel stehen - sonst merkt der Nutzer '
            'nicht, dass es weitergeht.',
      );

      // UND WEITER: sie läuft wieder.
      await tester.tap(find.text(L10n.tWithoutContext('intro.resume')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsOneWidget,
      );

      // VERWERFEN: es wird nichts gesendet, der Nutzer bekommt es gesagt.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await echteZeit(tester);
      expect(
        find.text(L10n.tWithoutContext('chat.voiceCancelled')),
        findsOneWidget,
      );
      expect(
        find.text(L10n.tWithoutContext('intro.recordingState')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('eine zu kurze Aufnahme wird verworfen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Eine ECHTE Datei - das Plugin meldet sie beim Stoppen. Ohne Datei
      // wäre der Aufnahme-Pfad ein anderer (das prüft der Test nicht).
      final datei = (await tester.runAsync(aufnahmeDatei))!;
      mockAufnahme(dateiBeimStoppen: datei);

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.text(L10n.tWithoutContext('chat.micDisclosureAccept')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Sofort stoppen - das sind weniger als eine Sekunde.
      await tester.tap(find.text(L10n.tWithoutContext('intro.stopListen')));
      await echteZeit(tester);

      expect(tester.takeException(), isNull);
      // Der Nutzer bekommt die Meldung ...
      expect(
        find.text(L10n.tWithoutContext('chat.voiceTooShort')),
        findsOneWidget,
        reason:
            'Eine zu kurze Aufnahme ist fuer die Gegenseite unbrauchbar - '
            'der Nutzer muss es wissen.',
      );
      // ... und die Datei liegt nicht mehr im Speicher.
      final existiert = await tester.runAsync(() => File(datei).exists());
      expect(
        existiert,
        isFalse,
        reason: 'Die verworfene Aufnahme darf nicht liegen bleiben.',
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('die Aufnahme wird erst nach dem Anhoeren gesendet', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final datei = (await tester.runAsync(aufnahmeDatei))!;
      mockAufnahme(dateiBeimStoppen: datei);

      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.text(L10n.tWithoutContext('chat.micDisclosureAccept')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Zwei Sekunden aufnehmen (unter einer Sekunde wird verworfen).
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text(L10n.tWithoutContext('intro.stopListen')));
      await echteZeit(tester);

      expect(tester.takeException(), isNull);
      // Das Blatt zum Anhören steht da - gesendet wird erst danach.
      expect(
        find.text(L10n.tWithoutContext('intro.review.title')),
        findsOneWidget,
        reason:
            'Der Nutzer soll die Aufnahme anhoeren koennen, bevor sie '
            'rausgeht.',
      );
      // Und noch ist keine Sprachnachricht im Chat.
      expect(
        chat.notifier
            .messagesFor(chat.match.id)
            .where((m) => m.type == MessageType.voice),
        isEmpty,
      );

      // Senden.
      await tester.tap(find.text(L10n.tWithoutContext('intro.review.send')));
      await echteZeit(tester);

      expect(tester.takeException(), isNull);
      // Jetzt steht sie im Chat (mit ihrer Dauer).
      final stimmen = chat.notifier
          .messagesFor(chat.match.id)
          .where((m) => m.type == MessageType.voice)
          .toList();
      expect(stimmen, hasLength(1));
      expect(stimmen.first.durationSeconds, 2);
      expect(find.textContaining('0:02'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
