// Der Empfang einer Nachricht über die Direktverbindung (P2P).
//
// ANLASS (19.11.2026): Die Coverage-Messung zeigte für
// lib/screens/chat/parts/chatp2p.dart 89 offene Zeilen - der Empfang
// über den direkten Kanal war ungetestet.
//
// DER WEG: Der WebRTC-Dienst spricht über die Anbieter
// ([webRTCServiceProvider]) - der Test zieht einen Ersatz ein, dessen
// eingehende Nachrichten er selbst schiebt. So kommt eine Nachricht
// an, ohne dass zwei echte Geräte nötig sind.
//
// DER GRUND: Der Empfang ist der heikelste Teil des Chats:
//   * eine Nachricht darf nicht doppelt ankommen (der P2P-Kanal UND
//     der Relay-Weg können dieselbe Nachricht bringen),
//   * die Nachrichten-ID des Senders muss erhalten bleiben (sonst
//     funktioniert "Nachricht für alle löschen" nicht),
//   * ein Eisbrecher muss als solcher erkannt werden.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/chat/message.dart';
import 'package:thestia/screens/chat/chat_detail_screen.dart';
import 'package:thestia/services/chat/encryption_service.dart';
import 'package:thestia/services/chat/message_envelope.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';
import 'hilfen.dart';

/// Der WebRTC-Ersatz: er schiebt die eingehenden Nachrichten selbst.
class FakeWebRTCService extends WebRTCService {
  FakeWebRTCService(super.encryptionService);

  final StreamController<String> _eingang =
      StreamController<String>.broadcast();

  @override
  Stream<String> get incomingMessages => _eingang.stream;

  /// Der Zustand des Datenkanals (steuert das E2E-Abzeichen).
  final StreamController<webrtc.RTCDataChannelState> _zustand =
      StreamController<webrtc.RTCDataChannelState>.broadcast();

  @override
  Stream<webrtc.RTCDataChannelState> get connectionState => _zustand.stream;

  /// Der Kanal gilt als offen (das steuert das E2E-Abzeichen).
  bool verbunden = false;

  @override
  bool get isConnected => verbunden;

  /// Meldet die offene Direktverbindung.
  void verbinde() {
    verbunden = true;
    _zustand.add(webrtc.RTCDataChannelState.RTCDataChannelOpen);
  }

  /// Schiebt eine Nachricht in den Kanal (wie der Partner).
  void empfange(String draht) => _eingang.add(draht);

  Future<void> schliessen() => _eingang.close();
}

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

  group('Der Empfang ueber die Direktverbindung', () {
    testWidgets('das E2E-Abzeichen zeigt die offene Verbindung', (
      tester,
    ) async {
      final chat = chatMitNachricht();
      late FakeWebRTCService webrtc;

      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        overrides: <Override>[
          webRTCServiceProvider.overrideWith((ref) {
            webrtc = FakeWebRTCService(ref.watch(encryptionServiceProvider));
            return webrtc;
          }),
        ],
      );
      addTearDown(() => webrtc.schliessen());

      // VORHER: noch keine Verbindung - das Abzeichen warnt.
      expect(
        find.byTooltip(L10n.tWithoutContext('chat.e2eWaiting')),
        findsOneWidget,
      );

      // Der Datenkanal geht auf.
      webrtc.verbinde();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(
        find.byTooltip(L10n.tWithoutContext('chat.e2eReady')),
        findsOneWidget,
        reason:
            'Der Nutzer muss sehen, dass die Nachrichten jetzt direkt und '
            'verschluesselt gehen - vorher lief alles ueber den Server.',
      );
    });

    testWidgets('eine eingehende Nachricht erscheint im Chat', (tester) async {
      final chat = chatMitNachricht();
      late FakeWebRTCService webrtc;

      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        overrides: <Override>[
          webRTCServiceProvider.overrideWith((ref) {
            webrtc = FakeWebRTCService(ref.watch(encryptionServiceProvider));
            return webrtc;
          }),
        ],
      );
      addTearDown(() => webrtc.schliessen());

      // DER PARTNER schickt eine Nachricht (über den direkten Kanal).
      webrtc.empfange(
        buildEnvelope(id: 'msg-1', kind: WireKind.text, text: 'Hallo du!'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // DIE NACHRICHT: Sie steht im Verlauf. (Der Text steht nicht
      // zwingend im Baum - die Liste baut nur die sichtbaren
      // Einträge, und die neue Nachricht liegt ganz unten.)
      final angekommen = chat.notifier
          .messagesFor(chat.match.id)
          .where((m) => m.text == 'Hallo du!')
          .toList();
      expect(
        angekommen,
        hasLength(1),
        reason:
            'Die Nachricht des Partners muss im Chat stehen - der direkte '
            'Kanal ist der Normalfall.',
      );
      // Und die Nachrichten-ID des Senders bleibt erhalten (das macht
      // "Nachricht für alle löschen" möglich).
      expect(angekommen.first.id, 'msg-1');
    });

    testWidgets('dieselbe Nachricht kommt nicht doppelt an', (tester) async {
      final chat = chatMitNachricht();
      late FakeWebRTCService webrtc;

      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        overrides: <Override>[
          webRTCServiceProvider.overrideWith((ref) {
            webrtc = FakeWebRTCService(ref.watch(encryptionServiceProvider));
            return webrtc;
          }),
        ],
      );
      addTearDown(() => webrtc.schliessen());

      final draht = buildEnvelope(
        id: 'msg-2',
        kind: WireKind.text,
        text: 'Nur einmal',
      );
      webrtc.empfange(draht);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // Die zweite Route (z. B. P2P und Relay) bringt dieselbe Nachricht.
      webrtc.empfange(draht);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      final angekommen = chat.notifier
          .messagesFor(chat.match.id)
          .where((m) => m.text == 'Nur einmal')
          .toList();
      expect(
        angekommen,
        hasLength(1),
        reason:
            'Dieselbe Nachricht darf nicht doppelt im Chat stehen - der '
            'Nutzer wuerde sie zweimal lesen und zweimal antworten.',
      );
    });

    testWidgets('ein Eisbrecher wird als solcher erkannt', (tester) async {
      final chat = chatMitNachricht();
      late FakeWebRTCService webrtc;

      await chatDetailScreenPump(
        tester,
        ChatDetailScreen(matchId: chat.match.id),
        chat.notifier,
        overrides: <Override>[
          webRTCServiceProvider.overrideWith((ref) {
            webrtc = FakeWebRTCService(ref.watch(encryptionServiceProvider));
            return webrtc;
          }),
        ],
      );
      addTearDown(() => webrtc.schliessen());

      webrtc.empfange(
        buildEnvelope(
          id: 'msg-3',
          kind: WireKind.icebreaker,
          text: 'Was machst du heute?',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      final eisbrecher = chat.notifier
          .messagesFor(chat.match.id)
          .where((m) => m.text == 'Was machst du heute?')
          .toList();
      expect(eisbrecher, hasLength(1));
      expect(
        eisbrecher.first.type,
        MessageType.icebreaker,
        reason:
            'Der Eisbrecher muss als Eisbrecher ankommen - er gehoert in '
            'die Mitte des Chats und nicht in den normalen Verlauf.',
      );
    });
  });
}
