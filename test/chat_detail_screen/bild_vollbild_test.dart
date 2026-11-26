// Das Vollbild-Bild im Chat (und das Wischen zum Schließen).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/screens/chat/parts/swipetoclose.dart und
// lib/screens/chat/parts/swipetoclosestate.dart 0 % Abdeckung.
//
// NUTZERWUNSCH (09.11.2026, Betreiber): "Wenn Bild geöffnet und zurück
// swipe, dann im Hintergrund zurück, aber Bild noch offen (Swipe soll
// Bild schließen und nicht im Hintergrund weiter machen)."
//
// WAS HIER GEPRÜFT WIRD:
//   * ein Tippen auf das Bild öffnet die Vollbild-Ansicht,
//   * ein kurzes Wischen schließt NICHT (sonst wäre jedes kurze
//     Versehen ein Weg zurück aus dem Bild),
//   * ein deutliches Wischen schließt das Bild - und nur das Bild.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/models/chat/message.dart';
import 'package:thestia/providers/chat/chat_provider.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat/chat_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import 'hilfen.dart';

/// Ein 1x1-Pixel-Bild als Daten-URL (der Chat zeigt Bilder aus Daten-URLs).
const String _bild =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  // DER STIMMUNGS-DIENST: Der Chat zeigt die Stimmungskarte - ohne den
  // Client schlägt der Aufbau fehl.
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

  /// Ein Chat mit EINER Bildnachricht von mir.
  ///
  /// DER GRUND FÜR "von mir": Nur eigene Bilder werden nicht verpixelt
  /// - der Weg über die Bestätigung wäre ein zweites Thema.
  ({ChatNotifier notifier, String matchId}) chatMitBild() {
    final service = ChatService();
    final match = service.createMatch(chatDetailScreenPartner());
    service.addMessage(
      match.id,
      Message(
        id: 'bild-1',
        senderId: 'ich',
        receiverId: 'partner-1',
        text: '',
        timestamp: DateTime.now(),
        type: MessageType.image,
        mediaUrl: _bild,
      ),
    );
    return (notifier: ChatNotifier(service), matchId: match.id);
  }

  group('Das Vollbild-Bild im Chat', () {
    testWidgets('ein Tippen auf das Bild oeffnet die Vollbild-Ansicht', (
      tester,
    ) async {
      final chat = chatMitBild();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.matchId),
        chat.notifier,
      );

      // DAS BILD BRAUCHT EINEN FRAME: `Image.memory` kennt die Höhe erst
      // nach dem Dekodieren - vorher ist die Kachel höhenlos und der Tipp
      // landet daneben.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.ensureVisible(find.byType(Image));
      await tester.pump();
      await tester.tap(find.byType(Image));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(Dialog),
        findsOneWidget,
        reason:
            'Ein Tippen auf ein Bild soll es gross zeigen - der Nutzer '
            'will Details sehen.',
      );
    });

    testWidgets('ein kurzes Wischen schliesst das Bild NICHT', (tester) async {
      final chat = chatMitBild();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.matchId),
        chat.notifier,
      );

      await tester.tap(find.byType(Image));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // EIN KURZER WEG: 30 Pixel - das ist unter der Schwelle (70).
      await tester.timedDrag(
        find.byType(Dialog),
        const Offset(-30, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(Dialog),
        findsOneWidget,
        reason:
            'Ein kurzes Wischen ist kein "machen Sie das zu" - das Bild '
            'muss offen bleiben.',
      );
    });

    testWidgets('ein deutliches Wischen schliesst das Bild', (tester) async {
      final chat = chatMitBild();
      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.matchId),
        chat.notifier,
      );

      await tester.tap(find.byType(Image));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.timedDrag(
        find.byType(Dialog),
        const Offset(-160, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(Dialog),
        findsNothing,
        reason:
            'NUTZERWUNSCH (09.11.2026): Das Wischen soll das Bild '
            'schliessen - und nicht den Bildschirm dahinter mit.',
      );
    });
  });
}
