import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/webrtc_service.dart';

/// Tests fuer das Signaling ueber Supabase Realtime.
///
/// WARUM DIESE DATEI (06.11.2026): Das P2P hat nie funktioniert.
/// Ursache: Das realtime_client setzt in seiner send()-Methode
/// (realtime_channel.dart:792)
///
///   payload['type'] = 'broadcast';
///
/// und ueberschreibt damit das EIGENE Feld 'type' der App. Der
/// Empfaenger sah darum immer type == 'broadcast' statt
/// 'offer'/'answer'/'ice'/'relay-ping' - und der Schalter in
/// _handleSignal fiel bei jedem Fall in 'default'. JEDE
/// Signaling-Nachricht wurde stillschweigend verworfen, der
/// DataChannel oeffnete nie.
///
/// LIVE AM ECHTEN SERVER gemessen (zwei echte Clients, echter
/// Broadcast): die empfangene Nachricht war
///   {event: signal, from: 11111111-..., type: broadcast}
/// obwohl gesendet wurde: {type: relay-ping, from: 11111111-...}
///
/// DER TEST NACHSTELLT DEN CLIENT: [wieRealtime] macht genau das, was
/// das Paket beim Senden macht. So laesst sich der Fehler nachstellen
/// und der Fix absichern - ohne echten Server.
void main() {
  /// Wie der realtime_client es beim Senden macht
  /// (realtime_channel.dart:792): er setzt 'type' auf 'broadcast' und
  /// 'event' auf den Ereignisnamen.
  Map<String, dynamic> wieRealtime(Map<String, dynamic> nutzlast) => {
    ...nutzlast,
    'type': 'broadcast',
    'event': 'signal',
  };

  group('Die Nachrichtenart im Feld "kind"', () {
    test('eine Nachricht vom Peer wird verarbeitet', () async {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-1';
      var pings = 0;
      final abo = service.relayPing.listen((_) => pings++);
      addTearDown(abo.cancel);

      await service.routeSignalingForTesting(
        wieRealtime({'kind': 'relay-ping', 'from': 'peer-1'}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        pings,
        1,
        reason: 'die Nachricht wurde verworfen - dann passt das Feld '
            '"kind" nicht zur Realtime-Client-Vereinbarung',
      );
    });

    test('das alte Feld "type" geht verloren (der urspruengliche Bug)',
        () async {
      // Der Client ueberschreibt 'type' mit 'broadcast' - die Nachricht
      // kommt also als type='broadcast' an und der Schalter in
      // _handleSignal verwirft sie. Genau das war der Grund, warum P2P
      // nie aufging.
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-1';
      var pings = 0;
      final abo = service.relayPing.listen((_) => pings++);
      addTearDown(abo.cancel);

      await service.routeSignalingForTesting(
        wieRealtime({'type': 'relay-ping', 'from': 'peer-1'}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        pings,
        0,
        reason:
            'eine Nachricht mit dem Feld "type" kam an - dann wuerde der '
            'Realtime-Client sie doch nicht ueberschreiben',
      );
    });

    test('ein fremder Absender wird verworfen', () async {
      // Der Fix darf die Haertung NICHT aufweichen.
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-1';
      var pings = 0;
      final abo = service.relayPing.listen((_) => pings++);
      addTearDown(abo.cancel);

      await service.routeSignalingForTesting(
        wieRealtime({'kind': 'relay-ping', 'from': 'attacker'}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(pings, 0, reason: 'eine fremde Nachricht kam durch');
    });
  });

  group('Die Answer-Race nach einem Retry', () {
    test('eine Answer zu einem alten Offer wird erkannt', () {
      // Szenario: Der Initiator schliesst die PeerConnection und
      // erzeugt ein neues Offer (Generation 2). Eine noch fliegende
      // Answer der alten Runde (Generation 1) darf die NEUE
      // PeerConnection nicht setzen - sonst wird die echte Answer
      // verworfen und die Verbindung ist unreparierbar.
      expect(
        WebRTCService.isStaleAnswer({'gen': 1}, 2),
        isTrue,
        reason: 'die alte Answer wurde nicht als veraltet erkannt',
      );
      expect(WebRTCService.isStaleAnswer({'gen': 2}, 2), isFalse);
    });

    test('eine Answer ohne Generation wird angenommen', () {
      // Toleranz: eine aeltere App-Version schickt keine Generation
      // mit - sonst wuerden Alt- und Neu-Version nicht miteinander
      // sprechen.
      expect(WebRTCService.isStaleAnswer({}, 2), isFalse);
      expect(WebRTCService.isStaleAnswer({'sdp': 'x'}, 7), isFalse);
    });
  });
}
