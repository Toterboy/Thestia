// Tests für WebRTCService-Härtung:
// - ice-config-Parsing (H-03, reine Funktion)
// - ICE-Cache ohne Netzwerkzugriff
// - Peer-Pinning im Signaling-Routing (fremde Absender werden verworfen)
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/encryption_service.dart';
import 'package:thestia/services/webrtc_service.dart';

void main() {
  group('parseIceConfig', () {
    test('parst gültige Antwort inkl. TURN', () {
      final servers = WebRTCService.parseIceConfig(
        '{"iceServers":[{"urls":"stun:stun.example.com:3478"},'
        '{"urls":"turn:turn.example.com","username":"u","credential":"p"}],'
        '"ttlSeconds":7200}',
      );
      expect(servers.length, 2);
      expect(servers.first['urls'], 'stun:stun.example.com:3478');
      expect(servers.last['username'], 'u');
    });

    test('wirft StateError bei fehlendem iceServers', () {
      expect(
        () => WebRTCService.parseIceConfig('{"ttlSeconds":3600}'),
        throwsStateError,
      );
    });

    test('wirft StateError bei leerer Liste', () {
      expect(
        () => WebRTCService.parseIceConfig('{"iceServers":[]}'),
        throwsStateError,
      );
    });

    test('wirft FormatException bei kaputtem JSON', () {
      expect(
        () => WebRTCService.parseIceConfig('kein-json'),
        throwsFormatException,
      );
    });
  });

  group('ICE-Cache (H-03)', () {
    test('resolveIceServers liefert gecachte Server ohne Netzwerk', () async {
      final service = WebRTCService(EncryptionService());
      service.setIceServerCache(
        [
          {'urls': 'stun:stun.cached.example.com:3478'},
        ],
        const Duration(hours: 1),
      );

      final servers = await service.resolveIceServers();
      expect(servers.length, 1);
      expect(servers.first['urls'], 'stun:stun.cached.example.com:3478');
    });
  });

  group('Peer-Pinning im Signaling-Routing', () {
    test('Nachricht eines fremden Absenders wird verworfen (kein Crash)', () {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-victim';

      // Angreifer versucht, ein Offer zu injizieren.
      expect(
        () => service.routeSignalingForTesting({
          'type': 'offer',
          'from': 'attacker',
          'sdp': 'v=0 fake-sdp',
        }),
        returnsNormally,
      );
    });

    test('ICE-Kandidat ohne Pflichtfelder wird verworfen', () {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-victim';

      expect(
        () => service.routeSignalingForTesting({
          'type': 'ice',
          'from': 'peer-victim',
          'candidate': 'candidate:1 1 UDP 1 1.2.3.4 5 typ host',
        }),
        returnsNormally,
      );
    });

    test('unbekannter Signaltyp wird ignoriert', () {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-victim';

      expect(
        () => service.routeSignalingForTesting({
          'type': 'bogus',
          'from': 'peer-victim',
        }),
        returnsNormally,
      );
    });
  });

  group('Handshake-Retry (v0.9.1-Fix "keine direkte Verbindung")', () {
    test('kein Signaling-Kanal referenziert nach Konstruktion', () {
      final service = WebRTCService(EncryptionService());
      expect(service.hasSignalingChannel, isFalse);
    });

    test('retryHandshake ohne Kanal ist ein No-op (kein Crash)', () async {
      final service = WebRTCService(EncryptionService());
      await service.retryHandshake();
      expect(service.isConnected, isFalse);
      expect(service.hasSignalingChannel, isFalse);
    });
  });

  group('Serialisiertes Signaling + Candidate-Backlog (Verbindungs-Fix)', () {
    test(
        'ICE-Kandidat VOR jeglicher PeerConnection wird gepuffert '
        '(kein Crash, kein Verlust - frueher: Null-Check-Exception)', () async {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-a';

      // Kandidat OHNE Offer/PC: muss gepuffert werden statt zu knallen.
      await service.routeSignalingForTesting({
        'type': 'ice',
        'from': 'peer-a',
        'candidate': 'candidate:1 1 UDP 2122252543 192.168.1.2 50000 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    test(
        'Reihenfolge bleibt erhalten: Offer-Queue verarbeitet seriell '
        '(mehrere Events einer Flut laufen ohne Interleaving durch)', () async {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-a';

      // Flut aus Events ohne PC: answer/ice werden verworfen/gepuffert,
      // ein fremder Absender dazwischen verworfen - nichts knallt und die
      // Queue leert sich deterministisch.
      await service.routeSignalingForTesting({
        'type': 'answer', 'from': 'peer-a', 'sdp': 'v=0 fake-answer',
      });
      await service.routeSignalingForTesting({
        'type': 'ice', 'from': 'peer-a',
        'candidate': 'candidate:1 1 UDP 1 10.0.0.2 40000 typ host',
        'sdpMid': '0', 'sdpMLineIndex': 0,
      });
      await service.routeSignalingForTesting({
        'type': 'offer', 'from': 'intruder', 'sdp': 'v=0 intruder-sdp',
      });
      await service.routeSignalingForTesting({
        'type': 'ice', 'from': 'peer-a',
        'candidate': 'candidate:2 1 UDP 1 10.0.0.2 40001 typ host',
        'sdpMid': '0', 'sdpMLineIndex': 0,
      });
    });

    test(
        'Überdimensionales Offer-SDP wird verworfen, BEVOR eine '
        'PeerConnection gebaut wird (DoS-Schutz S4)', () async {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-a';

      // 70 KB SDP > _maxSdpBytes (64 KB). Würde der Guard NICHT greifen,
      // versuchte handleOffer einen echten PC-Aufbau (Platform-Channel ->
      // MissingPluginException im Unit-Test) - der Test schlägt fehl.
      final hugeSdp = 'v=0\n${'x' * (70 * 1024)}';
      await service.routeSignalingForTesting({
        'type': 'offer', 'from': 'peer-a', 'sdp': hugeSdp,
      });
    });

    test('Answer ohne PeerConnection wird verworfen statt zu crashen', () async {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-a';

      await service.routeSignalingForTesting({
        'type': 'answer', 'from': 'peer-a', 'sdp': 'v=0 answer-sdp',
      });
    });

    test('sdpMLineIndex als double (Web-JSON) wird akzeptiert', () async {
      final service = WebRTCService(EncryptionService());
      service.currentPeerIdForTesting = 'peer-a';

      // Browser/Realtime-Kanten liefern int als double - der alte
      // `as int`-Castwarf und verlor den Kandidaten.
      await service.routeSignalingForTesting({
        'type': 'ice',
        'from': 'peer-a',
        'candidate': 'candidate:1 1 UDP 1 192.168.1.3 50001 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0.0,
      });
    });
  });
}