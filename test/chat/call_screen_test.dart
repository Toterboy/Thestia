// Der Anruf-Bildschirm.
//
// ANLASS (14.11.2026): Die Coverage-Messung zeigte fuer
// lib/screens/chat/call_screen.dart 435 offene Zeilen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Bildschirm baut sich (kein Absturz, kein Render-Overflow),
//   * der Name der Person steht da,
//   * ohne Verbindung erscheint der Mobilfunk-Hinweis (der Nutzer soll
//     wissen, dass es am Netz liegt und nicht an ihm),
//   * der eingehende Anruf kann angenommen und abgelehnt werden,
//   * der ausgehende Anruf kann abgebrochen werden,
//   * die Gegenseite nimmt an oder legt auf - und der Bildschirm folgt,
//   * ein zweiter Anruf waehrend des Gespraechs wird als "besetzt"
//     gemeldet (die Gegenseite wartet sonst 30 s ins Leere),
//   * das Stummschalten und die Eisbrecher-Sammlung.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/screens/chat/call_screen.dart';
import 'package:thestia/services/chat/p2p_chat_service.dart';
import 'package:thestia/services/chat/prekey_service.dart';
import 'package:thestia/services/chat/webrtc_service.dart';

import '../support/plugin_mocks.dart';

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

  /// Die gesendeten Sprachpakete.
  final List<Uint8List> sprachPakete = [];

  /// Die eingehenden Anruf-Steuerungen (die Gegenseite).
  ///
  /// DER GRUND: Ohne diesen Kanal kann der Test nicht pruefen, was der
  /// Bildschirm auf ein "accept" oder "end" der Gegenseite macht -
  /// und ob er einen fremden Anruf als "besetzt" meldet.
  final StreamController<Map<String, dynamic>> _eingang =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get callControl => _eingang.stream;

  /// Schickt der Gegenseite eine Steuerung (so wie es die echte tut).
  void sendeSteuerung(Map<String, dynamic> nachricht) {
    _eingang.add(nachricht);
  }

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
  Future<void> sendCallAudio(
    Uint8List data, {
    Map<String, dynamic>? metadata,
  }) async {
    sprachPakete.add(data);
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
    // DIE AUFNAHME: Das Mikrofon (Push-to-Talk) wird ueber das Plugin
    // bedient - ohne den Ersatz wartet der Aufruf endlos.
    mockAufnahme();
    // DER AUFNAHME-PLAYER: just_audio braucht beim Anlegen die Engine.
    mockAudioPlayer();
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
  ///
  /// [anrufId]: Die ID des Anrufs. Ohne sie vergibt der Bildschirm eine
  /// eigene - dann kann der Test der Gegenseite keine passende
  /// Steuerung schicken.
  Future<_FakeP2P?> zeigeScreen(
    WidgetTester tester, {
    bool mitVerbindung = false,
    bool eingehend = false,
    String? anrufId,
    double breite = 390,
  }) async {
    await tester.binding.setSurfaceSize(Size(breite, 844));
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
            incomingCallId: anrufId,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return fake;
  }

  /// Bringt den Bildschirm in den Zustand "im Gespraech".
  ///
  /// DER WEG: Die Gegenseite nimmt an - dann steht der Bildschirm auf
  /// "verbunden" (mit Mikrofon, Eisbrechern und Auflege-Knopf).
  Future<_FakeP2P> imGespraech(
    WidgetTester tester, {
    String anrufId = 'anruf-1',
    double breite = 390,
  }) async {
    final p2p = await zeigeScreen(
      tester,
      mitVerbindung: true,
      anrufId: anrufId,
      breite: breite,
    );
    p2p!.sendeSteuerung({'type': 'accept', 'callId': anrufId});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return p2p;
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

  testWidgets('der eingehende Anruf kann angenommen werden', (tester) async {
    final p2p = await zeigeScreen(
      tester,
      mitVerbindung: true,
      eingehend: true,
      anrufId: 'anruf-1',
    );

    expect(tester.takeException(), isNull);
    // Der Annahme-Knopf steht da.
    expect(find.byIcon(Icons.call), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Das "accept" ist raus - sonst weiss die Gegenseite nichts.
    expect(
      p2p!.controls.any((c) => c['type'] == 'accept'),
      isTrue,
      reason:
          'Ohne "accept" bleibt die Gegenseite im Klingel-Zustand - der '
          'Anruf gaenge nie an.',
    );
    // Der Bildschirm steht jetzt auf "verbunden".
    expect(find.byIcon(Icons.mic), findsWidgets);
  });

  testWidgets('der eingehende Anruf kann abgelehnt werden', (tester) async {
    final p2p = await zeigeScreen(
      tester,
      mitVerbindung: true,
      eingehend: true,
      anrufId: 'anruf-1',
    );

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(
      p2p!.controls.any((c) => c['type'] == 'decline'),
      isTrue,
      reason:
          'Ohne "decline" wartet die Gegenseite 45 Sekunden auf eine '
          'Antwort, die nie kommt.',
    );
  });

  testWidgets('der ausgehende Anruf kann abgebrochen werden', (tester) async {
    final p2p = await zeigeScreen(
      tester,
      mitVerbindung: true,
      anrufId: 'anruf-1',
    );

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(
      p2p!.controls.any((c) => c['type'] == 'end'),
      isTrue,
      reason:
          'Ohne "end" wartet die Gegenseite auf einen Anruf, den es nicht '
          'mehr gibt.',
    );
  });

  testWidgets('die Gegenseite nimmt an - der Bildschirm folgt', (tester) async {
    await imGespraech(tester);

    expect(tester.takeException(), isNull);
    // Der verbundene Zustand: Mikrofon, Eisbrecher und Auflege-Knopf.
    expect(find.byIcon(Icons.mic), findsWidgets);
    expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
  });

  group('Die Stummschaltung', () {
    testWidgets('der Schalter schaltet um', (tester) async {
      await imGespraech(tester);

      expect(tester.takeException(), isNull);
      // Das Mikrofon-Symbol steht fuer "nicht stumm".
      expect(find.byIcon(Icons.mic_off), findsNothing);
      expect(
        find.text(L10n.tWithoutContext('chat.callUnmuted')),
        findsOneWidget,
      );

      // DER SCHALTER: Er ist ein eigener Knopf (nicht das Mikrofon des
      // Push-to-Talk) - sonst wuerde man sich selbst stumm schalten.
      final schalter = find.widgetWithIcon(FloatingActionButton, Icons.mic);
      expect(schalter, findsOneWidget);
      await tester.tap(schalter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.text(L10n.tWithoutContext('chat.callMuted')), findsOneWidget);
    });

    testWidgets('im stummgeschalteten Zustand wird nicht gesprochen', (
      tester,
    ) async {
      final p2p = await imGespraech(tester);

      // Erst stumm schalten.
      await tester.tap(find.widgetWithIcon(FloatingActionButton, Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Dann "sprechen": Der Knopf wird gedrueckt und wieder losgelassen.
      final sprechKnopf = find.byIcon(Icons.mic_off_outlined);
      expect(sprechKnopf, findsOneWidget);
      final gestures = await tester.startGesture(tester.getCenter(sprechKnopf));
      await tester.pump(const Duration(milliseconds: 200));
      await gestures.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        p2p.sprachPakete,
        isEmpty,
        reason:
            'Im stummgeschalteten Zustand darf nichts aufgenommen werden - '
            'der Nutzer hat es ausgeschaltet.',
      );
    });
  });

  testWidgets('die Gegenseite legt auf - der Bildschirm folgt', (tester) async {
    final p2p = await zeigeScreen(
      tester,
      mitVerbindung: true,
      anrufId: 'anruf-1',
    );

    p2p!.sendeSteuerung({'type': 'end', 'callId': 'anruf-1'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    // Der Endzustand: keine Anruf-Knoepfe mehr.
    expect(find.byIcon(Icons.call_end), findsNothing);
    expect(find.byIcon(Icons.call), findsNothing);
  });

  testWidgets('ein zweiter Anruf wird als besetzt gemeldet', (tester) async {
    final p2p = await imGespraech(tester);

    // Waehrend des Gespraechs klingelt ein weiterer Anruf.
    p2p.sendeSteuerung({'type': 'invite', 'callId': 'anderer-anruf'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    final besetzt = p2p.controls.where(
      (c) => c['type'] == 'decline' && c['busy'] == true,
    );
    expect(
      besetzt,
      isNotEmpty,
      reason:
          'Der zweite Anrufer muss sofort erfahren, dass besetzt ist - '
          'sonst wartet er 30 Sekunden ins Leere.',
    );
  });

  testWidgets('das Stummschalten geht an und wieder aus', (tester) async {
    await imGespraech(tester);

    expect(tester.takeException(), isNull);
    // Der Stumm-Knopf (das Mikrofon-Symbol am Stumm-Schalter).
    final stumm = find.descendant(
      of: find.byType(FloatingActionButton),
      matching: find.byIcon(Icons.mic),
    );
    expect(stumm, findsOneWidget);

    await tester.tap(stumm);
    await tester.pump();
    expect(find.text(L10n.tWithoutContext('chat.callMuted')), findsOneWidget);

    // Und wieder zurueck.
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byIcon(Icons.mic_off),
      ),
    );
    await tester.pump();
    expect(find.text(L10n.tWithoutContext('chat.callUnmuted')), findsOneWidget);
  });

  testWidgets('die Eisbrecher-Sammlung laesst sich oeffnen', (tester) async {
    await imGespraech(tester);

    await tester.tap(find.byIcon(Icons.lightbulb_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.text(L10n.tWithoutContext('call.icebreakerTitle')),
      findsWidgets,
      reason: 'Die Sammlung muss ueberhaupt etwas zeigen.',
    );
  });

  testWidgets('die Knopf-Reihe passt auch auf ein schmales Telefon', (
    tester,
  ) async {
    // BEFUND (18.11.2026, gefunden von einem Test): Auf einem 390er
    // Bildschirm lief die Knopf-Reihe 186 Pixel ueber den Rand - waehrend
    // des Gespraechs standen die gelb-schwarzen Streifen im Bild.
    // Auch schmalere Telefone (360 Pixel) muessen ohne Streifen
    // auskommen.
    await imGespraech(tester, breite: 360);

    expect(
      tester.takeException(),
      isNull,
      reason:
          'Die Knopf-Reihe muss auf ein schmales Telefon passen - sonst '
          'sieht der Nutzer waehrend des Gespraechs die Ueberlauf-Streifen.',
    );
    // Und die Knopfe sind alle da (nichts ist weggefallen).
    expect(find.byIcon(Icons.mic), findsWidgets);
    expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
  });
}
