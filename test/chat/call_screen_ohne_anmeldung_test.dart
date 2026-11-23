// Der Anruf-Screen ohne Anmeldung.
//
// ANLASS (23.11.2026): Der Screen baut das Signaling ueber die
// Nutzer-ID auf. Fehlt sie (die Sitzung ist abgelaufen, der Aufruf
// kommt aus einem alten Zustand), darf der Bildschirm nicht endlos
// klingeln - er muss sagen, dass es nicht geht.
//
// WARUM EINE EIGENE DATEI: Das Abmelden im laufenden Test klemmt (der
// Client wartet auf den Server, und im Test gibt es keinen). Hier wird
// einfach gar nicht angemeldet - das ist derselbe Zustand.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
// webrtc_interface kommt als Transitivum ueber flutter_webrtc - der Test
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

/// Der P2P-Dienst als Ersatz (ohne Verbindung).
class _FakeP2P extends P2PChatService {
  _FakeP2P(super.webrtc, super.prekey);

  @override
  bool get isConnected => false;

  @override
  bool get isDataChannelOpen => false;

  @override
  Stream<Map<String, dynamic>> get callControl =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Stream<({Uint8List data, String contentType, Map<String, dynamic>? metadata})>
  get callAudio =>
      const Stream<
        ({Uint8List data, String contentType, Map<String, dynamic>? metadata})
      >.empty();

  @override
  Stream<RTCDataChannelState> get connectionState =>
      const Stream<RTCDataChannelState>.empty();

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    mockKeystore();
    await mockHive();
    mockAudioPlayer();
    mockAufnahme();
    // DER SERVER NUR FUER DIE INITIALISIERUNG: Es wird sich NICHT
    // angemeldet - genau darum geht es in diesem Test.
    final server = FakeSupabaseServer(userId: 'ich');
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
  });

  testWidgets('ohne Anmeldung bleibt der Anruf nicht haengen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          p2pChatServiceProvider.overrideWith(
            (ref) => _FakeP2P(
              ref.watch(webRTCServiceProvider),
              ref.watch(preKeyServiceProvider),
            ),
          ),
        ],
        child: const MaterialApp(
          home: CallScreen(partnerName: 'Mira', peerId: 'partner-1'),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      find.text(L10n.tWithoutContext('chat.callStatusUnreachable')),
      findsOneWidget,
      reason:
          'Ohne angemeldete Person gibt es keine Nutzer-ID fuer das '
          'Signaling - der Bildschirm muss das melden, statt endlos zu '
          'klingeln.',
    );
  });
}
