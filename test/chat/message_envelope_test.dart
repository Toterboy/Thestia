// Tests fuer die neue Nachrichten-Huelle (v0.10.1).
//
// BEFUND (11.11.2026): Ohne eine stabile Nachrichten-ID konnte die
// Nachricht nicht "fuer alle geloescht" werden (die beiden Seiten
// hatten verschiedene IDs). Die Huelle traegt die ID des Senders.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/message_envelope.dart';

void main() {
  group('Die Nachrichten-Huelle', () {
    test('baut und zerlegt eine Textnachricht', () {
      final draht = buildEnvelope(
        id: 'm_123_0',
        kind: WireKind.text,
        text: 'Hallo',
      );
      final gepackt = parseEnvelope(draht);
      expect(gepackt.fromNewFormat, isTrue);
      expect(gepackt.id, 'm_123_0');
      expect(gepackt.kind, WireKind.text);
      expect(gepackt.text, 'Hallo');
    });

    test('behaelt den Eisbrecker als Art', () {
      final draht = buildEnvelope(
        id: 'm_1',
        kind: WireKind.icebreaker,
        text: 'Was machst du?',
      );
      final gepackt = parseEnvelope(draht);
      expect(gepackt.kind, WireKind.icebreaker);
      expect(gepackt.text, 'Was machst du?');
    });

    test('der Text darf ein "|" enthalten', () {
      final draht = buildEnvelope(
        id: 'm_2',
        kind: WireKind.text,
        text: 'a | b | c',
      );
      final gepackt = parseEnvelope(draht);
      expect(gepackt.id, 'm_2');
      expect(gepackt.text, 'a | b | c');
    });

    test('eine alte Nachricht (ohne Huelle) bleibt Text', () {
      final gepackt = parseEnvelope('Hallo aus einer alten App');
      expect(gepackt.fromNewFormat, isFalse);
      expect(gepackt.id, isEmpty);
      expect(gepackt.text, 'Hallo aus einer alten App');
    });

    test('eine kaputte Huelle wird als Text behandelt (nicht verloren)', () {
      final gepackt = parseEnvelope('__T2__|unvollstaendig');
      expect(gepackt.fromNewFormat, isFalse);
      expect(gepackt.text, contains('unvollstaendig'));
    });

    test('eine Huelle mit unbekannter Art bleibt erhalten', () {
      final gepackt = parseEnvelope('__T2__|m_3|x|Text');
      expect(gepackt.fromNewFormat, isFalse);
      expect(gepackt.text, contains('Text'));
    });

    test('zwei Wege mit derselben ID ergeben dieselbe Nachricht', () {
      // Das ist der Punkt: derselbe Text ueber P2P und ueber das Relay
      // muss auf beiden Geraeten dieselbe ID haben - sonst erscheint die
      // Nachricht doppelt und ein Loeschen erreicht die Gegenseite nicht.
      final ueberP2p = parseEnvelope(
        buildEnvelope(id: 'm_42', kind: WireKind.text, text: 'Hallo'),
      );
      final ueberRelay = parseEnvelope(
        buildEnvelope(id: 'm_42', kind: WireKind.text, text: 'Hallo'),
      );
      expect(ueberP2p.id, ueberRelay.id);
    });
  });
}
