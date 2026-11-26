// Fuzzing der Peer-Hülle (die Nachricht kommt von der GEGENSEITE).
//
// WARUM DAS DIE WICHTIGSTE ZIEL IST (22.11.2026, Fuzzing): Die Hülle
// im Peer-zu-Peer-Kanal schickt die ANDERE PERSON. Sie ist also
// kontrolliert von jemandem, der der App schaden will - nicht von
// einem Serverfehler.
//
// DER BEFUND: Das Auslesen stand mit Casts im Dienst:
//   jsonDecode(text) as Map<String, dynamic>  -> wirft
//   data['type'] as String                   -> wirft
//   base64Decode(data['ciphertext'] as String) -> wirft (FormatException)
//   data['messageType'] as int               -> wirft
// Eine einzige kaputte Nachricht hat damit den Kanal abbrechen
// lassen. Jetzt steht das Auslesen in `SignalEnvelope.parse` - es
// wirft nie und verwirft, was nicht sauber ist.
//
// DER ORACLE: parse() wirft NIE, und es gibt eine Hülle nur dann
// zurück, wenn sie vollständig und plausibel ist.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/services/chat/signal_envelope.dart';

import 'fuzz_harness.dart';

/// Die Seeds der Läufe.
const _seeds = <int>[1, 42, 1337, 20261122];

/// Der normale Fall (was die App selbst schickt).
final _huelleSeed = <String, Object?>{
  'type': 'signal_message',
  'ciphertext': 'AQIDBAUGBwgJCgsMDQ4PEBESExQ=',
  'messageType': 3,
  'contentType': 'application/octet-stream',
  'metadata': <String, Object?>{'name': 'bild.jpg'},
};

void main() {
  group('Die Peer-Huelle ueberlebt jede Eingabe', () {
    for (final seed in _seeds) {
      test('parse wirft nie (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        for (var i = 0; i < Fuzz.durchlaeufe; i++) {
          final eingabe = fuzz.korpusVariante(_huelleSeed, 1 + i % 4);
          if (eingabe is! Map) continue;
          final text = jsonText(eingabe);
          try {
            final huelle = SignalEnvelope.parse(text);
            // Was zurückkommt, muss benutzbar sein.
            if (huelle != null) {
              expect(huelle.ciphertext, isNotEmpty);
              expect(huelle.typ, isA<SignalEnvelopeType>());
              expect(huelle.metadata?.length ?? 0, lessThanOrEqualTo(16));
            }
          } catch (e, stapel) {
            fail(
              'SignalEnvelope.parse ist an einer fremden Nachricht '
              'abgestürzt.\n'
              '${fundBeschreibung(seed, eingabe)}\n'
              'Fehler: $e\n'
              '$stapel',
            );
          }
        }
      });

      test('parse wirft auch bei kaputtem Text nie (Seed $seed)', () {
        final fuzz = Fuzz(seed);
        final texte = <String>[
          '',
          ' ',
          'kein json',
          '{',
          '[]',
          'null',
          '"text"',
          '{}',
          '{"type":"signal_message"}',
          '{"type":"signal_message","ciphertext":123}',
          '{"type":"signal_message","ciphertext":"###"}',
          '{"type":"signal_message","ciphertext":"AB=="}',
          '{"type":"unbekannt","ciphertext":"QUJD"}',
          '{"ciphertext":"QUJD"}',
          '\u0000\u0001\u0002',
          'x' * 600000,
        ];
        for (var i = 0; i < 40; i++) {
          texte.add(fuzz.korpusVariante(_huelleSeed, 1 + i % 4).toString());
        }
        for (final text in texte) {
          try {
            SignalEnvelope.parse(text);
          } catch (e, stapel) {
            fail(
              'SignalEnvelope.parse ist an kaputtem Text abgestürzt.\n'
              'Text: ${text.length > 200 ? "${text.substring(0, 200)}…" : text}\n'
              'Fehler: $e\n'
              '$stapel',
            );
          }
        }
      });
    }
  });

  group('Die Peer-Huelle wird geprueft, nicht geraten', () {
    test('eine gute Nachricht kommt an', () {
      final huelle = SignalEnvelope.parse(jsonEncode(_huelleSeed));
      expect(huelle, isNotNull);
      expect(huelle!.typ, SignalEnvelopeType.message);
      expect(huelle.ciphertext, 'AQIDBAUGBwgJCgsMDQ4PEBESExQ=');
      expect(huelle.messageType, 3);
    });

    test('eine Binaernachricht kommt an', () {
      final huelle = SignalEnvelope.parse(
        jsonEncode(<String, Object?>{
          'type': 'signal_binary',
          'ciphertext': 'QUJD',
          'messageType': 1,
          'contentType': 'image/jpeg',
          'metadata': <String, Object?>{'name': 'bild.jpg'},
        }),
      );
      expect(huelle, isNotNull);
      expect(huelle!.typ, SignalEnvelopeType.binary);
      expect(huelle.contentType, 'image/jpeg');
      expect(huelle.metadata?['name'], 'bild.jpg');
    });

    test('eine unbekannte Art wird verworfen', () {
      expect(
        SignalEnvelope.parse(
          jsonEncode(<String, Object?>{
            'type': 'sonderbefehl',
            'ciphertext': 'QUJD',
          }),
        ),
        isNull,
      );
    });

    test('ein kaputtes base64 wird verworfen', () {
      expect(
        SignalEnvelope.parse(
          jsonEncode(<String, Object?>{
            'type': 'signal_message',
            'ciphertext': 'nicht base64!!',
          }),
        ),
        isNull,
      );
    });

    test('zu viele Metadaten werden verworfen', () {
      final viele = <String, Object?>{for (var i = 0; i < 40; i++) 'k$i': i};
      final huelle = SignalEnvelope.parse(
        jsonEncode(<String, Object?>{
          'type': 'signal_binary',
          'ciphertext': 'QUJD',
          'metadata': viele,
        }),
      );
      expect(huelle, isNotNull);
      expect(
        huelle!.metadata,
        isNull,
        reason:
            'Der Peer darf die Metadaten nicht unbegrenzt gross machen '
            '(Audit S3).',
      );
    });

    test('eine zu grosse Huelle wird verworfen', () {
      expect(SignalEnvelope.parse('x' * (maxSignalEnvelopeBytes + 1)), isNull);
    });
  });
}
