import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/services/relay_service.dart';

void main() {
  group('Relay-Fallback (v0.9.1, Migration 093)', () {
    test('RelayMessage.fromJson mappt alle Felder', () {
      final msg = RelayMessage.fromJson({
        'id': 42,
        'sender': 'abc-123',
        'ciphertext': 'e30=',
        'msgType': 3,
        'kind': 'icebreaker',
        'createdAt': '2026-01-01T12:00:00.000Z',
        'text': 'Welche Stadt möchtest du unbedingt mal besuchen?',
      });
      expect(msg.id, 42);
      expect(msg.senderId, 'abc-123');
      expect(msg.kind, 'icebreaker');
      expect(msg.text, 'Welche Stadt möchtest du unbedingt mal besuchen?');
    });

    test('RelayMessage.fromJson ist tolerant (Defaults)', () {
      final msg = RelayMessage.fromJson({
        'id': 7,
        'sender': 'x',
      });
      expect(msg.kind, 'text');
      expect(msg.text, '');
    });
  });
}
