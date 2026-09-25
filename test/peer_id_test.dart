import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/peer_id.dart';

/// Tests für die Peer-ID-Validierung (Audit M1/M2).
///
/// Peer-IDs stammen teilweise aus fremd-kontrollierten Quellen (QR-Codes,
/// Deep-Links) und fließen in URL-Pfade, Function-Pfade und PostgREST-
/// Filter – nur wohlgeformte UUIDs dürfen durchgelassen werden.
void main() {
  group('isValidPeerId – gültige UUIDs', () {
    test('Kanonische UUID (kleingeschrieben) wird akzeptiert', () {
      expect(
        isValidPeerId('123e4567-e89b-42d3-a456-426614174000'),
        isTrue,
      );
    });

    test('UUID in Großbuchstaben wird akzeptiert', () {
      expect(
        isValidPeerId('123E4567-E89B-42D3-A456-426614174000'),
        isTrue,
      );
    });

    test('Nil-UUID wird akzeptiert', () {
      expect(
        isValidPeerId('00000000-0000-0000-0000-000000000000'),
        isTrue,
      );
    });
  });

  group('isValidPeerId – Angriffsvektoren werden abgelehnt', () {
    test('null und leer', () {
      expect(isValidPeerId(null), isFalse);
      expect(isValidPeerId(''), isFalse);
    });

    test('Pfad-Traversal aus QR-Payload', () {
      expect(isValidPeerId('../admin'), isFalse);
      expect(isValidPeerId('..%2Fadmin'), isFalse);
      expect(isValidPeerId('../../etc/passwd'), isFalse);
    });

    test('PostgREST-Filter-Injection', () {
      expect(isValidPeerId('123e4567),user_two_id.eq.'), isFalse);
      expect(isValidPeerId('x).or(1 eq 1'), isFalse);
      expect(isValidPeerId('*'), isFalse);
    });

    test('Zu kurz / zu lang / falsches Format', () {
      expect(isValidPeerId('abc'), isFalse);
      expect(isValidPeerId('123e4567e89b42d3a456426614174000'), isFalse); // ohne Bindestriche
      expect(
        isValidPeerId('123e4567-e89b-42d3-a456-426614174000-extra'),
        isFalse,
      );
      expect(isValidPeerId('123e4567-e89b-42d3-a456-42661417400g'), isFalse); // 'g' ist kein Hex
    });

    test('Zeilenumbrüche/Whitespace (Header/URL-Injection)', () {
      expect(isValidPeerId(' 123e4567-e89b-42d3-a456-426614174000'), isFalse);
      expect(
        isValidPeerId('123e4567-e89b-42d3-a456-426614174000\nX-Injected: 1'),
        isFalse,
      );
    });
  });
}
