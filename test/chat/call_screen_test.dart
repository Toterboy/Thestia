// Der Anruf-Screen (Sprachchat).
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte für
// lib/screens/chat/call_screen.dart 137 offene Zeilen bei 69 % Abdeckung.
// Der Screen entscheidet, was der Nutzer sieht, wenn es keine Verbindung
// gibt - und genau das ist der Fall, der im Alltag auffällt.
//
// WAS HIER GEPRÜFT WIRD:
//   * ohne Verbindung wird der Anruf als "nicht erreichbar" gemeldet
//     (nicht: endloses Klingeln ohne Ende),
//   * der ausgehende Anruf klingelt beim Partner,
//   * der eingehende Anruf klingelt bei mir (mit Annahme und Ablehnung),
//   * das Auflegen beendet den Anruf.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
// webrtc_interface kommt als Transitivum über flutter_webrtc - der Test
// braucht nur den DataChannel-Zustand.
// ignore_for_file: depend_on_referenced_packages
import 'package:webrtc_interface/webrtc_interface.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';
import 'package:thestia/screens/chat/call_screen.dart';

import '../support/fake_supabase_server.dart';
import '../support/plugin_mocks.dart';

/// Der P2P-Dienst als Ersatz.
///
/// DER GRUND: Die echte Direktverbindung braucht das WebRTC-Plugin - im
/// Test gibt es kein Gerät. Der Ersatz meldet, was der Test will: die
/// Verbindung steht oder sie fällt aus.
class _FakeP2P extends P2PChatService {
  _FakeP2P(super.webrtc, super.prekey, {this.verbunden = true});

  /// Steht die Verbindung?
  final bool verbunden;

  /// Soll der Verbindungsaufbau scheitern?
  bool verbindungSchlaegtFehl = false;

  /// Die gesendeten Kontroll-Nachrichten.
  final List<Map<String, dynamic>> kontrolle = <Map<String, dynamic>>[];

  final StreamController<Map<String, dynamic>> _kontrolle =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<
    ({Uint8List data, String contentType, Map<String, dynamic>? metadata})
  >
  _audio =
      StreamController<
        ({Uint8List data, String contentType, Map<String, dynamic>? metadata})
      >.broadcast();

  @override
  bool get isConnected => verbunden;

  @override
  bool get isDataChannelOpen => verbunden;

  @override
  Stream<Map<String, dynamic>> get callControl => _kontrolle.stream;

  @override
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
  get callAudio => _audio.stream;

  @override
  Stream<RTCDataChannelState> get connectionState =>
      const Stream<RTCDataChannelState>.empty();

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {
    if (verbindungSchlaegtFehl) {
      throw StateError('Verbindung nicht moeglich');
    }
  }

  @override
  Future<void> sendCallControl(Map<String, dynamic> payload) async {
    kontrolle.add(payload);
  }

  @override
  Future<void> dispose() async {
    await _kontrolle.close();
    await _audio.close();
  }
}

void main() {
  late FakeSupabaseServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    // HIVE: der Verschlüsselungs-Dienst öffnet seine Boxen - ohne
    // initialisiertes Hive schlägt der Aufbau fehl.
    await mockHive();
    // DER AUDIO-PLAYER und die AUFNAHME: Der Screen benutzt beide.
    mockAudioPlayer();
    mockAufnahme();
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
    server.pfade.clear();
  });

  /// Baut den Anruf-Screen.
  Future<_FakeP2P> zeige(
    WidgetTester tester, {
    bool eingehend = false,
    bool verbindungSchlaegtFehl = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late _FakeP2P p2p;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          p2pChatServiceProvider.overrideWith((ref) {
            p2p = _FakeP2P(
              ref.watch(webRTCServiceProvider),
              ref.watch(preKeyServiceProvider),
              verbunden: !verbindungSchlaegtFehl,
            )..verbindungSchlaegtFehl = verbindungSchlaegtFehl;
            return p2p;
          }),
        ],
        child: MaterialApp(
          home: CallScreen(
            partnerName: 'Mira',
            peerId: 'partner-1',
            isIncoming: eingehend,
            incomingCallId: eingehend ? 'call-1' : null,
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return p2p;
  }

  group('Die Gesprächsdauer', () {
    testWidgets('sie steht im Bild, während man telefoniert', (tester) async {
      await zeige(tester, eingehend: true);

      // DER ANRUF ANNIMMEN: erst dann läuft die Uhr.
      await tester.tap(find.byIcon(Icons.call));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(
        find.text(L10n.tWithoutContext('chat.callDuration')),
        findsOneWidget,
        reason:
            'Die Dauer braucht einen Namen - "00:03" allein sagt nicht, '
            'ob es Sekunden oder Minuten sind.',
      );
      expect(
        find.text('00:03'),
        findsOneWidget,
        reason: 'Nach drei Sekunden muss die Dauer "00:03" sein.',
      );
    });

    testWidgets('sie zaehlt mit', (tester) async {
      await zeige(tester, eingehend: true);
      await tester.tap(find.byIcon(Icons.call));
      await tester.pump();

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(find.text('00:05'), findsOneWidget);
    });

    testWidgets('vor dem Annehmen steht keine Dauer', (tester) async {
      await zeige(tester, eingehend: true);

      expect(
        find.text(L10n.tWithoutContext('chat.callDuration')),
        findsNothing,
        reason:
            'Vor dem Annehmen telefoniert niemand - eine Dauer wäre '
            'gelogen.',
      );
    });
  });

  group('Der Anruf-Screen', () {
    testWidgets('ohne Verbindung ist der Anruf nicht erreichbar', (
      tester,
    ) async {
      await zeige(tester, verbindungSchlaegtFehl: true);

      expect(
        find.text(L10n.tWithoutContext('chat.callStatusUnreachable')),
        findsOneWidget,
        reason:
            'Ohne Verbindung muss der Nutzer das sehen - ein Bildschirm, der '
            'einfach klingelt, laesst ihn raten.',
      );
    });

    testWidgets('der ausgehende Anruf klingelt beim Partner', (tester) async {
      final p2p = await zeige(tester);

      expect(
        find.text(L10n.tWithoutContext('chat.callStatusRingingOut')),
        findsOneWidget,
        reason: 'Der Anruf muss als "klingelt" erkennbar sein.',
      );
      expect(
        p2p.kontrolle.any((c) => c['type'] == 'invite'),
        isTrue,
        reason:
            'Das Invite muss an den Partner gehen - ohneInvite klingelt es '
            'gar nicht.',
      );
      expect(find.text('Mira'), findsOneWidget);
    });

    testWidgets('der eingehende Anruf klingelt bei mir', (tester) async {
      await zeige(tester, eingehend: true);

      expect(
        find.text(L10n.tWithoutContext('chat.callStatusRingingIn')),
        findsOneWidget,
        reason: 'Der eingehende Anruf muss als "klingelt" erkennbar sein.',
      );
      // ANNEHMEN und ABLEHNEN: Beide Wege müssen da sein.
      expect(find.byIcon(Icons.call), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);
    });

    testWidgets('das Auflegen meldet dem Partner das Ende', (tester) async {
      final p2p = await zeige(tester);

      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(tester.takeException(), isNull);
      expect(
        p2p.kontrolle.any((c) => c['type'] == 'end'),
        isTrue,
        reason:
            'Das Auflegen muss dem Partner gemeldet werden - sonst klingelt '
            'es bei ihm weiter und er wartet auf einen Anruf, der nicht '
            'kommt.',
      );
    });
  });
}
