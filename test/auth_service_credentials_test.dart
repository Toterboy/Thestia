// Unit-Tests für das gesalzene Credential-Hashing in [AuthService].
//
// Getestet wird [AuthService.hashCredentialsForTest] bzw.
// [AuthService.verifyCredentialsForTest] — dieselben Funktionen, die in
// [AuthService.register] und [AuthService.login] genutzt werden.
//
// Format seit Security-Fix M10: `<saltHex>$<sha256(salt + email + \x00 + password)>`
// mit kryptografisch sicherem Zufalls-Salt (Random.secure).
//
// Es werden ausschließlich synthetische Test-Fixtures verwendet, keine
// Produktions-E-Mails oder echten Passwörter.

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/auth_service.dart';

void main() {
  group('Gesalzenes Credential-Hashing (salt\$hash)', () {
    const testEmailA = 'TEST_FIXTURE_user_a@example.test';
    const testEmailB = 'TEST_FIXTURE_user_b@example.test';
    const testPasswordA = 'TEST_ONLY_p4ssw0rd_A';
    const testPasswordB = 'TEST_ONLY_p4ssw0rd_B';

    test('Format: saltHex + \$ + sha256Hex (32 + 1 + 64 Zeichen)', () {
      final stored = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      expect(stored, hasLength(32 + 1 + 64));
      expect(stored.contains(r'$'), isTrue);
      final parts = stored.split(r'$');
      expect(parts, hasLength(2));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(parts[0]), isTrue);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(parts[1]), isTrue);
    });

    test('Verifikation mit korrekten Zugangsdaten gelingt', () {
      final stored = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      expect(
        AuthService.verifyCredentialsForTest(stored, testEmailA, testPasswordA),
        isTrue,
      );
    });

    test('Verifikation mit falschem Passwort scheitert', () {
      final stored = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      expect(
        AuthService.verifyCredentialsForTest(stored, testEmailA, testPasswordB),
        isFalse,
      );
    });

    test('Verifikation mit falscher E-Mail scheitert', () {
      final stored = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      expect(
        AuthService.verifyCredentialsForTest(stored, testEmailB, testPasswordA),
        isFalse,
      );
    });

    test('Salting: gleicher Input erzeugt unterschiedliche Hashes '
        '(Zufalls-Salt, kein Rainbow-Table-Angriff)', () {
      final h1 = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      final h2 = AuthService.hashCredentialsForTest(testEmailA, testPasswordA);
      expect(h1, isNot(equals(h2)));
    });

    test('Beschädigte/kompatibilitätsfeindliche Stored-Strings werden '
        'abgelehnt (fail-closed)', () {
      const email = testEmailA;
      const password = testPasswordA;
      expect(AuthService.verifyCredentialsForTest('', email, password), isFalse);
      expect(AuthService.verifyCredentialsForTest('nureinhash', email, password), isFalse);
      expect(
        AuthService.verifyCredentialsForTest('zz\$deadbeef', email, password),
        isFalse,
      );
      expect(
        AuthService.verifyCredentialsForTest('abc${'a' * 64}', email, password),
        isFalse,
      );
    });

    test('Unicode-E-Mail und -Passwort werden korrekt verarbeitet', () {
      const unicodeEmail = 'TEST_FIXTURE_müller@äöü.test';
      const unicodePw = 'TEST_pässwörd🔐';
      final stored = AuthService.hashCredentialsForTest(unicodeEmail, unicodePw);
      expect(
        AuthService.verifyCredentialsForTest(stored, unicodeEmail, unicodePw),
        isTrue,
      );
    });
  });
}
