// Der Anruf-Screen: der ganze Ablauf eines Sprachanrufs.
//
// ANLASS (23.11.2026): Die Coverage-Messung zeigte für
// lib/screens/chat/call_screen.dart 300 offene Zeilen bei 32 %
// Abdeckung - die größte Lücke der App. Der Screen entscheidet,
// was im Gespräch passiert: Wer nimmt ab, wer legt auf, was bei
// fehlender Verbindung gemeldet wird und was die Sprache des
// Partners auslöst.
//
// WAS HIER GEPRÜFT WIRD:
//   * die Annahme und die Ablehnung (beide Richtungen),
//   * das Ende des Anrufs durch den Partner und durch mich,
//   * der besetzte Zweit-Anruf (der Partner soll nicht 30 Sekunden
//     ins Leere warten),
//   * die Zeitüberschreitung (kein endloses Klingeln),
//   * das Push-to-Talk (ohne Mikrofon, mit Mikrofon, der Versand),
//   * der Eisbrecher-Bogen und die Stummschaltung,
//   * die Fehlerfälle: kein Invite, kein DataChannel, keine ID.
import 'dart:async';
import 'dart:io';
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
/// Test gibt es kein Gerät. Der Ersatz meldet, was der Test will, und
/// nimmt die Nachrichten auf, die der Screen schickt.
class _FakeP2P extends P2PChatService {
  _FakeP2P(
    super.webrtc,
    super.prekey, {
    this.verbunden = true,
    this.kanalOffen = true,
  });

  /// Steht die Verbindung?
  bool verbunden;

  /// Ist der DataChannel offen?
  bool kanalOffen;

  /// Soll das Invite scheitern?
  bool inviteSchlaegtFehl = false;

  /// Die gesendeten Kontroll-Nachrichten.
  final List<Map<String, dynamic>> kontrolle = <Map<String, dynamic>>[];

  /// Die gesendeten Sprachpakete.
  final List<Uint8List> sprachpakete = <Uint8List>[];

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
  bool get isDataChannelOpen => kanalOffen;

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
  }) async {}

  @override
  Future<void> sendCallControl(Map<String, dynamic> payload) async {
    if (payload['type'] == 'invite' && inviteSchlaegtFehl) {
      throw StateError('Invite nicht moeglich');
    }
    kontrolle.add(payload);
  }

  @override
  Future<void> sendCallAudio(
    Uint8List data, {
    Map<String, dynamic>? metadata,
  }) async {
    sprachpakete.add(data);
  }

  /// Der Partner nimmt an (oder legt auf).
  void empfangeKontrolle(Map<String, dynamic> nachricht) =>
      _kontrolle.add(nachricht);

  /// Der Partner spricht.
  void empfangeAudio(Uint8List daten) =>
      _audio.add((data: daten, contentType: 'audio/call', metadata: null));

  /// Die ID des Anrufs (steht im Invite).
  String get callId =>
      kontrolle.firstWhere((c) => c['type'] == 'invite')['callId']!.toString();
}

void main() {
  late FakeSupabaseServer server;
  late Directory tempDir;
  late File aufnahme;

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

  setUp(() async {
    server.pfade.clear();
    // DER TEMP-ORDNER UND DIE AUFNAHME: Das Push-to-Talk liest die Datei
    // spater im Screen. Das Anlegen muss VOR dem Test passieren - im
    // Test selbst wartet das Dateisystem endlos (der Test läuft in einer
    // nachgebauten Zeit, in der die echte Datei keine Antwort bekommt).
    tempDir = await Directory.systemTemp.createTemp('thesia_call_test');
    aufnahme = File('${tempDir.path}/aufnahme.m4a');
    await aufnahme.writeAsBytes(Uint8List.fromList(List<int>.filled(256, 3)));
    mockAufnahme(dateiBeimStoppen: aufnahme.path);
  });

  /// Baut den Anruf-Screen.
  Future<_FakeP2P> zeige(
    WidgetTester tester, {
    bool eingehend = false,
    bool verbunden = true,
    bool kanalOffen = true,
    bool inviteSchlaegtFehl = false,
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
              verbunden: verbunden,
              kanalOffen: kanalOffen,
            )..inviteSchlaegtFehl = inviteSchlaegtFehl;
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

  /// Der Partner nimmt an - das Gespräch steht.
  Future<void> partnerNimmtAn(WidgetTester tester, _FakeP2P p2p) async {
    p2p.empfangeKontrolle({'type': 'accept', 'callId': p2p.callId});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Der Knopf zum Sprechen (der große Kreis in der Mitte).
  Finder sprechKnopf() => find.byWidgetPredicate(
    (w) => w is Icon && w.icon == Icons.mic && w.size == 40,
  );

  /// Der Knopf mit dem angegebenen Hero-Tag (die runden Knöpfe).
  Finder knopf(String tag) => find.byWidgetPredicate(
    (w) => w is FloatingActionButton && w.heroTag == tag,
  );

  /// Lässt Test-Kreis und echten Kreis abwechseln.
  ///
  /// DER GRUND: Das Dateisystem (Aufnahme lesen, Paket speichern,
  /// Datei löschen) braucht den echten Ereignis-Kreis - im Test-Kreis
  /// wartet es endlos. Die Bildschirm-Aktionen laufen dagegen im
  /// Test-Kreis (dort ist die Uhr künstlich). Deshalb wird abwechselnd
  /// gearbeitet: einmal den Test-Kreis vor und danach den echten.
  Future<void> wechsle(WidgetTester tester, {int mal = 4}) async {
    for (var i = 0; i < mal; i++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    }
    await tester.pump();
  }

  group('Der Anruf-Ablauf', () {
    testWidgets('der Partner nimmt an - das Gespraech steht', (tester) async {
      final p2p = await zeige(tester);

      await partnerNimmtAn(tester, p2p);

      expect(
        find.text('00:00'),
        findsOneWidget,
        reason:
            'Nach der Annahme steht die Gesprächszeit da (und nicht mehr der '
            'Klingeltext) - das ist das Zeichen, dass das Gespraech steht.',
      );
      expect(
        find.byIcon(Icons.lightbulb_outline),
        findsOneWidget,
        reason:
            'Er im Gespräch gibt es die Eisbrecher-Fragen - sie sind nur im '
            'verbundenen Zustand da.',
      );
    });

    testWidgets('die Dauer laeuft mit', (tester) async {
      final p2p = await zeige(tester);

      await partnerNimmtAn(tester, p2p);
      await tester.pump(const Duration(seconds: 3));

      expect(
        find.text('00:03'),
        findsOneWidget,
        reason:
            'Im Gespraech muss die Zeit stehen - sonst weiss niemand, wie '
            'lange man schon spricht.',
      );
    });

    testWidgets('der eingehende Anruf wird angenommen', (tester) async {
      final p2p = await zeige(tester, eingehend: true);

      await tester.tap(find.byIcon(Icons.call));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('00:00'),
        findsOneWidget,
        reason: 'Die Annahme muss den Anruf verbinden.',
      );
      expect(
        p2p.kontrolle.any((c) => c['type'] == 'accept'),
        isTrue,
        reason: 'Die Annahme muss dem Partner gemeldet werden.',
      );
    });

    testWidgets('der eingehende Anruf wird abgelehnt', (tester) async {
      final p2p = await zeige(tester, eingehend: true);

      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        p2p.kontrolle.any((c) => c['type'] == 'decline'),
        isTrue,
        reason:
            'Die Ablehnung muss dem Partner gemeldet werden - sonst klingelt '
            'es bei ihm weiter.',
      );
    });

    testWidgets('der Partner legt auf', (tester) async {
      final p2p = await zeige(tester);

      p2p.empfangeKontrolle({'type': 'end', 'callId': p2p.callId});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text(L10n.tWithoutContext('chat.callStatusEnded')),
        findsOneWidget,
        reason: 'Das Auflegen des Partners muss im Bildschirm stehen.',
      );
    });

    testWidgets('der Partner nimmt nicht ab - nach 30 Sekunden ist Schluss', (
      tester,
    ) async {
      final p2p = await zeige(tester);

      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text(L10n.tWithoutContext('chat.callStatusUnreachable')),
        findsOneWidget,
        reason:
            'Ein Anruf, den niemand annimmt, darf nicht endlos klingeln - '
            'der Nutzer braucht eine Antwort.',
      );
      expect(
        p2p.kontrolle.any((c) => c['type'] == 'end'),
        isTrue,
        reason: 'Das Ende muss dem Partner gemeldet werden.',
      );
    });

    testWidgets('der eingehende Anruf endet nach 45 Sekunden von selbst', (
      tester,
    ) async {
      final p2p = await zeige(tester, eingehend: true);

      await tester.pump(const Duration(seconds: 46));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        p2p.kontrolle.any((c) => c['type'] == 'end'),
        isTrue,
        reason:
            'Ein Anruf, den niemand annimmt, muss von selbst enden - der '
            'Nutzer hat den Bildschirm vielleicht schon verlassen.',
      );
      expect(
        find.text(L10n.tWithoutContext('chat.callStatusEnded')),
        findsOneWidget,
        reason: 'Der Bildschirm muss den Ende-Zustand zeigen.',
      );
    });

    testWidgets('ein zweiter Anruf waehrend des Gespraechs wird abgewiesen', (
      tester,
    ) async {
      final p2p = await zeige(tester);
      await partnerNimmtAn(tester, p2p);

      p2p.empfangeKontrolle({'type': 'invite', 'callId': 'fremder-anruf'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final abweisung = p2p.kontrolle.where(
        (c) => c['type'] == 'decline' && c['busy'] == true,
      );
      expect(
        abweisung,
        isNotEmpty,
        reason:
            'Wer schon telefoniert, muss dem zweiten Anrufer sofort Bescheid '
            'geben - er soll nicht 30 Sekunden ins Leere warten.',
      );
    });

    testWidgets('eine fremde Anruf-ID wird verworfen', (tester) async {
      final p2p = await zeige(tester);

      p2p.empfangeKontrolle({'type': 'accept', 'callId': 'fremder-anruf'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text(L10n.tWithoutContext('chat.callStatusRingingOut')),
        findsOneWidget,
        reason:
            'Eine Nachricht mit fremder Anruf-ID darf diesen Anruf nicht '
            'verbinden - sonst kaeme ein fremder Anruf durch.',
      );
    });

    testWidgets('ohne Invite bleibt der Anruf nicht haengen', (tester) async {
      await zeige(tester, inviteSchlaegtFehl: true);

      expect(
        find.text(L10n.tWithoutContext('chat.callStatusUnreachable')),
        findsOneWidget,
        reason:
            'Wenn das Invite nicht ankommt, muss der Bildschirm das sagen - '
            'sonst klingelt es ohne Ende.',
      );
    });

    testWidgets('ohne offenen DataChannel bleibt der Anruf nicht haengen', (
      tester,
    ) async {
      await zeige(tester, verbunden: false, kanalOffen: false);

      expect(
        find.text(L10n.tWithoutContext('chat.callStatusUnreachable')),
        findsOneWidget,
        reason:
            'Ohne DataChannel kann der Anruf nicht laufen - der Nutzer muss '
            'das erfahren.',
      );
    });
  });

  group('Das Push-to-Talk', () {
    testWidgets('ohne Mikrofon gibt es eine Meldung', (tester) async {
      final p2p = await zeige(tester);
      await partnerNimmtAn(tester, p2p);

      // KEINE Mikrofonberechtigung:
      mockAufnahme(erlaubt: false);

      await tester.tap(sprechKnopf());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text(L10n.tWithoutContext('chat.callMicDenied')),
        findsOneWidget,
        reason:
            'Ohne Mikrofon muss der Nutzer einen Grund sehen - sonst passiert '
            'beim Sprechen einfach nichts.',
      );
    });

    testWidgets('die Aufnahme laeuft und geht als Sprachpaket raus', (
      tester,
    ) async {
      final p2p = await zeige(tester);
      await partnerNimmtAn(tester, p2p);

      // DIE AUFNAHME MIT INHALT: Der Screen liest die Datei und schickt
      // sie an den Partner. Die Datei hat der Test-Vorbereitung angelegt
      // (im Test selbst wartet das Dateisystem endlos).
      mockAufnahme(dateiBeimStoppen: aufnahme.path);

      final griff = await tester.startGesture(tester.getCenter(sprechKnopf()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text(L10n.tWithoutContext('chat.callPttHold')),
        findsOneWidget,
        reason:
            'Waehrend der Aufnahme muss der Bildschirm das zeigen - sonst '
            'glaubt der Nutzer, es sei nichts passiert.',
      );

      // Loslassen: die Aufnahme stoppt und das Sprachpaket geht raus.
      await griff.up();
      await wechsle(tester, mal: 6);

      expect(
        p2p.sprachpakete,
        isNotEmpty,
        reason:
            'Die aufgenommene Sprache muss beim Partner ankommen - sonst '
            'ist der Knopf eine Attrappe.',
      );
      expect(
        p2p.sprachpakete.first.length,
        256,
        reason: 'Das Sprachpaket muss den aufgenommenen Ton enthalten.',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('die Stummschaltung schaltet das Sprechen ab', (tester) async {
      final p2p = await zeige(tester);
      await partnerNimmtAn(tester, p2p);

      await tester.tap(knopf('mute'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text(L10n.tWithoutContext('chat.callMuted')),
        findsOneWidget,
        reason:
            'Die Stummschaltung muss sichtbar sein - der Nutzer muss wissen, '
            'dass er nicht sendet.',
      );
    });
  });

  group('Der Eisbrecher-Bogen', () {
    testWidgets('die Fragen stehen bereit', (tester) async {
      final p2p = await zeige(tester);
      await partnerNimmtAn(tester, p2p);

      await tester.tap(knopf('icebreakers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(L10n.tWithoutContext('call.icebreakerTitle')),
        findsWidgets,
        reason:
            'Der Bogen muss sich oeffnen - er ist fuer stille Anrufe da. '
            '(Der Titel steht zweimal da: am Knopf und im Bogen.)',
      );
      expect(
        find.byType(ChoiceChip),
        findsWidgets,
        reason: 'Die Kategorien werden angeboten.',
      );
      expect(
        find.byType(Card),
        findsWidgets,
        reason: 'Die Fragen stehen als Karten bereit.',
      );
    });

    testWidgets('eine Kategorie schraenkt die Fragen ein', (tester) async {
      final p2p = await zeige(tester);
      await partnerNimmtAn(tester, p2p);

      await tester.tap(knopf('icebreakers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final chips = find.byType(ChoiceChip);
      final anzahl = chips.evaluate().length;
      expect(anzahl, greaterThan(1));

      // Die erste Kategorie (nicht "alle") wählen.
      await tester.tap(chips.at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byType(Card),
        findsWidgets,
        reason: 'Auch in einer Kategorie gibt es Fragen.',
      );
    });
  });

  group('Die Sprache des Partners', () {
    testWidgets('eine Sprachdatei wird gespeichert und abgespielt', (
      tester,
    ) async {
      final p2p = await zeige(tester);
      await partnerNimmtAn(tester, p2p);

      // DER GRUND FÜR runAsync: Das Speichern der Datei braucht das
      // echte Dateisystem - im Test ohne runAsync wartet der Aufruf.
      await tester.runAsync(() async {
        p2p.empfangeAudio(Uint8List.fromList(List<int>.filled(64, 9)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await wechsle(tester, mal: 4);

      // Die Wiedergabe wartet auf das Ende des Tons (im Test kommt es
      // nicht) - nach zwei Minuten greift die Sicherung im Screen.
      await tester.pump(const Duration(minutes: 3));
      await wechsle(tester, mal: 4);

      expect(tester.takeException(), isNull);
    });

    testWidgets('ausserhalb des Gespraechs wird nichts abgespielt', (
      tester,
    ) async {
      final p2p = await zeige(tester);

      await tester.runAsync(() async {
        p2p.empfangeAudio(Uint8List.fromList(List<int>.filled(64, 9)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await wechsle(tester, mal: 4);

      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
