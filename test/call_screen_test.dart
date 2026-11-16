// Der Anruf-Bildschirm (bisher ungetestet).
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/call_screen.dart 435 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * der Name der Person steht da,
//   * ohne Verbindung erscheint der Mobilfunk-Hinweis (der Nutzer soll
//     wissen, dass es am Netz liegt und nicht an ihm).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/chat/call_screen.dart';
import 'package:thestia/services/p2p_chat_service.dart';
import 'package:thestia/services/prekey_service.dart';
import 'package:thestia/services/webrtc_service.dart';

import 'support/plugin_mocks.dart';

/// Der P2P-Dienst mit einer offenen Verbindung.
///
/// DER GRUND: Ohne diese Ersatzwaerter wartet der Anruf-Bildschirm
/// zehn Sekunden auf einen offenen DataChannel, den es im Test nie
/// gibt - der Anruf schlaegt dann immer fehl. Mit ihr laeuft der Weg
/// weiter: das Invite geht raus.
class _FakeP2P extends P2PChatService {
  _FakeP2P(super.webrtc, super.prekey);

  /// Die Anruf-Steuerungen, die rausgegangen sind.
  final List<Map<String, dynamic>> controls = [];

  @override
  bool get isConnected => true;

  @override
  bool get isDataChannelOpen => true;

  @override
  Stream<RTCDataChannelState> get connectionState =>
      Stream<RTCDataChannelState>.value(RTCDataChannelState.RTCDataChannelOpen);

  @override
  Future<void> sendCallControl(Map<String, dynamic> payload) async {
    controls.add(payload);
  }

  @override
  Future<void> connect({
    required String myUserId,
    required String peerId,
  }) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
    await mockPfadProvider();
    await supabase.Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  /// Baut den Screen und liefert den P2P-Fake (null = ohne Fake).
  ///
  /// DER HINWEIS: Der Fake wird erst beim Lesen des Providers erzeugt
  /// (er ist "lazy") - der Screen holt ihn beim Start, deshalb steht er
  /// nach dem Aufbau bereit.
  Future<_FakeP2P?> zeigeScreen(
    WidgetTester tester, {
    bool mitVerbindung = false,
    bool eingehend = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    _FakeP2P? fake;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (mitVerbindung)
            p2pChatServiceProvider.overrideWith((ref) {
              fake = _FakeP2P(
                ref.watch(webRTCServiceProvider),
                ref.watch(preKeyServiceProvider),
              );
              ref.onDispose(fake!.dispose);
              return fake!;
            }),
        ],
        child: MaterialApp(
          home: CallScreen(
            partnerName: 'Mira',
            peerId: 'partner-1',
            isIncoming: eingehend,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return fake;
  }

  testWidgets('der Bildschirm baut sich ohne Absturz', (tester) async {
    await zeigeScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CallScreen), findsOneWidget);
  });

  testWidgets('der Name der Person steht da', (tester) async {
    await zeigeScreen(tester);

    expect(find.text('Mira'), findsWidgets);
  });

  testWidgets('der ausgehende Anruf schickt das Invite', (tester) async {
    final p2p = await zeigeScreen(tester, mitVerbindung: true);

    expect(tester.takeException(), isNull);
    // Das Invite ist raus - sonst klingelt es bei der Gegenseite nie.
    final invites = p2p!.controls.where((c) => c['type'] == 'invite');
    expect(
      invites,
      isNotEmpty,
      reason:
          'Der ausgehende Anruf muss die Gegenseite ueber den '
          'Anruf-Kanal erreichen.',
    );
  });

  testWidgets('der eingehende Anruf klingelt', (tester) async {
    final p2p = await zeigeScreen(tester, mitVerbindung: true, eingehend: true);

    expect(tester.takeException(), isNull);
    // Beim eingehenden Anruf wartet die App auf die Gegenseite.
    expect(p2p!.controls.where((c) => c['type'] == 'invite'), isEmpty);
  });

  testWidgets('ohne Verbindung erscheint der Mobilfunk-Hinweis', (
    tester,
  ) async {
    await zeigeScreen(tester);

    // Im Test gibt es keine Gegenstelle - der Aufbau schlaegt fehl, und
    // die App sagt das (statt zu schweigen).
    expect(
      find.textContaining(L10n.tWithoutContext('chat.callNetHint')),
      findsWidgets,
      reason:
          'Ohne Gegenstelle muss der Nutzer erfahren, dass es am Netz '
          'liegt - nicht an ihm.',
    );
  });
}
