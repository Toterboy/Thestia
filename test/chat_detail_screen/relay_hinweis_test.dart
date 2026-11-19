// Der Relay-Hinweis und die Sicherheitsnummer im Chat.
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/parts/chatdetailaufbau.dart 148 offene Zeilen - darunter
// der Hinweis auf den Relay-Fallback (kein P2P moeglich) mit seiner
// technischen Diagnose.
//
// DER GRUND: Wenn keine Direktverbindung zustande kommt (Router mit
// AP-Isolation, Mobilfunknetz), laeuft der Chat ueber den Server-
// Relay weiter. Der Nutzer MUSS das wissen - sonst denkt er, die
// Nachrichten gingen direkt und waeren verschluesselt, obwohl sie
// ueber den Server laufen. Der Hinweis nennt auch den Grund (ICE-
// Zustand, letzter Fehler) - das ist die Diagnose, wenn der Aufbau
// haengt.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Hinweis erscheint, wenn keine Direktverbindung steht,
//   * er laesst sich aufklappen (die technische Diagnose),
//   * er laesst sich wegklicken (der Hinweis ist nicht aufdringlich),
//   * das Menue bietet die Sicherheitsnummer an (der Weg, den der
//     Nutzer bei einem Verdacht geht).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import 'hilfen.dart';

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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
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
    server.rpcAntworten.clear();
    server.rpcAufrufe.clear();
  });

  group('Der Hinweis auf den Relay-Fallback', () {
    testWidgets('er erscheint, wenn keine Direktverbindung steht', (
      tester,
    ) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('chat.relayBannerShort')),
        findsOneWidget,
        reason:
            'Der Nutzer muss erfahren, dass der Chat ueber den Server laeuft - '
            'sonst glaubt er, die Nachrichten gingen direkt und waeren '
            'verschluesselt.',
      );
    });

    testWidgets('er laesst sich aufklappen und wieder zuklappen', (
      tester,
    ) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      // DER HINWEIS: Er wird beim Antippen aufgeklappt - dann steht
      // dort die technische Diagnose (das ist der Grund, warum der
      // Hinweis nicht einfach weggeklickt werden muss).
      final hinweis = find.text(L10n.tWithoutContext('chat.relayBannerShort'));
      await tester.ensureVisible(hinweis);
      await tester.pump();
      await tester.tap(hinweis);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('chat.relayBanner')),
        findsOneWidget,
        reason:
            'Der aufgeklappte Hinweis muss erklaeren, was der Relay '
            'ueberhaupt ist.',
      );
      // Und die Diagnose steht dabei.
      expect(
        find.textContaining('ICE'),
        findsWidgets,
        reason:
            'Die technische Diagnose (ICE-Zustand) hilft, wenn der '
            'Verbindungsaufbau haengt - ohne sie wuesste der Nutzer nicht, '
            'ob es an seinem Router liegt.',
      );

      // Und wieder zuklappen.
      await tester.tap(find.text(L10n.tWithoutContext('chat.relayBanner')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(L10n.tWithoutContext('chat.relayBannerShort')),
        findsOneWidget,
      );
    });

    testWidgets('er laesst sich wegklicken', (tester) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      final hinweis = find.text(L10n.tWithoutContext('chat.relayBannerShort'));
      await tester.ensureVisible(hinweis);
      await tester.pump();

      // DER SCHLIESS-KNOPF: Der Hinweis darf nicht aufdringlich sein -
      // wer ihn kennt, muss ihn wegklicken koennen.
      final knopf = find.byTooltip(L10n.tWithoutContext('common.close'));
      await tester.ensureVisible(knopf);
      await tester.pump();
      await tester.tap(knopf);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('chat.relayBannerShort')),
        findsNothing,
        reason: 'Nach dem Wegklicken kommt der Hinweis nicht wieder.',
      );
    });
  });

  group('Die Sicherheitsnummer im Menue', () {
    testWidgets('das Menue bietet sie an', (tester) async {
      final chat = chatMitNachricht();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        find.text(L10n.tWithoutContext('chat.safetyNumberTooltip')),
        findsOneWidget,
        reason:
            'Der Weg zur Sicherheitsnummer muss erreichbar sein - er ist '
            'das einzige Mittel, um einen kompromittierten Kontakt zu '
            'erkennen.',
      );
    });
  });
}
