// Unit-Tests für die BackupCrypto-Schicht (PBKDF2-Key-Derivation +
// AES-256-GCM-Ver-/Entschlüsselung).
//
// [BackupCrypto] ist die saubere Test-Schicht der Backup-Verschlüsselung:
// - Genau EINE Implementierung der Krypto-Logik (in lib/services/backup_crypto.dart)
// - Wird vom [EncryptionService.createEncryptedBackup] / [restoreFromBackup]
//   in Produktion genutzt — es gibt keine parallele Test-API mehr.
// - Hat KEINE Abhängigkeit zu Hive, Supabase oder Flutter-Platform-Channels
//   und läuft damit komplett isoliert als reines Unit-Test.
//
// Es werden ausschließlich synthetische Test-Fixtures verwendet, keine
// Produktionsschlüssel oder echten User-Daten.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/backup_crypto.dart';

void main() {
  // Klartext-Fixture: identifizierbar als Test-Daten.
  const testPlaintext =
      'TEST_FIXTURE_identityKeyPair_base64_encoded_string_for_encryption_test';

  // Passwort-Fixture: NICHT aus der Produktion, offensichtlich als Test.
  const testPassword = 'TEST_ONLY_p4ssw0rd-not-used-anywhere-else!';

  group('AES-256-GCM Backup-Krypto', () {
    test('Encrypt → Decrypt Roundtrip liefert Original-Wert zurück', () {
      final encrypted = BackupCrypto.encrypt(testPlaintext, testPassword);
      final decrypted = BackupCrypto.decrypt(encrypted, testPassword);
      expect(decrypted, equals(testPlaintext));
    });

    test('Leerer Klartext wird mit FormatException abgelehnt', () {
      // Leere Klartexte sind semantisch nicht sinnvoll (ein leeres Backup
      // enthält keine identifizierbaren Daten) und werden daher abgelehnt,
      // um stille Fehlbedienungen zu vermeiden.
      expect(
        () => BackupCrypto.encrypt('', testPassword),
        throwsA(isA<FormatException>()),
      );
    });

    test('Roundtrip funktioniert für langen Klartext (> 1 KB)', () {
      final longText = 'X' * 2048;
      final encrypted = BackupCrypto.encrypt(longText, testPassword);
      final decrypted = BackupCrypto.decrypt(encrypted, testPassword);
      expect(decrypted, equals(longText));
    });

    test('Roundtrip funktioniert für Unicode-Klartext', () {
      const unicode = 'äöüß💛🔐 Test mit Umlauten und Emojis';
      final encrypted = BackupCrypto.encrypt(unicode, testPassword);
      final decrypted = BackupCrypto.decrypt(encrypted, testPassword);
      expect(decrypted, equals(unicode));
    });

    test(
      'Unterschiedliche Klartexte mit gleichem Passwort ergeben '
      'unterschiedliche Chiffrate',
      () {
        const text1 = 'TEST_FIXTURE_message_alpha';
        const text2 = 'TEST_FIXTURE_message_beta';
        final c1 = BackupCrypto.encrypt(text1, testPassword);
        final c2 = BackupCrypto.encrypt(text2, testPassword);
        expect(c1, isNot(equals(c2)));
      },
    );

    test(
      'Gleicher Klartext mit gleichem Passwort erzeugt durch zufälligen IV '
      'unterschiedliche Chiffrate',
      () {
        // AES-GCM erfordert einen eindeutigen IV pro Verschlüsselung.
        // Selbst bei identischem Input + Passwort MUSS das Chiffrat
        // unterschiedlich sein.
        final c1 = BackupCrypto.encrypt(testPlaintext, testPassword);
        final c2 = BackupCrypto.encrypt(testPlaintext, testPassword);
        final c3 = BackupCrypto.encrypt(testPlaintext, testPassword);
        expect(c1, isNot(equals(c2)));
        expect(c2, isNot(equals(c3)));
        expect(c1, isNot(equals(c3)));
      },
    );

    test('Chiffrat ist gültiges Base64', () {
      final encrypted = BackupCrypto.encrypt(testPlaintext, testPassword);
      // Muss fehlerfrei dekodierbar sein.
      expect(() => base64Decode(encrypted), returnsNormally);
    });

    test('Chiffrat enthält Salt + IV + mindestens 16-Byte-Tag (AES-GCM)', () {
      final encrypted = BackupCrypto.encrypt(testPlaintext, testPassword);
      final decoded = base64Decode(encrypted);
      // salt (16) + iv (12) + ciphertext + tag (16).
      // Minimum für Klartext mit 0 Bytes wäre 16+12+16 = 44 Bytes.
      expect(
        decoded.length,
        greaterThanOrEqualTo(44),
        reason: 'AES-GCM-Output muss Salt+IV+Tag enthalten.',
      );
    });

    test('Falsches Passwort führt zu kontrolliertem Fehler', () {
      final encrypted = BackupCrypto.encrypt(testPlaintext, testPassword);
      expect(
        () => BackupCrypto.decrypt(encrypted, 'TEST_ONLY_wrong_password'),
        throwsA(isA<Exception>()),
        reason: 'AES-GCM Auth-Tag-Mismatch muss Exception werfen, '
            'nicht still fehlschlagen.',
      );
    });

    test('Manipulierter Ciphertext wirft kontrollierte Exception', () {
      final encrypted = BackupCrypto.encrypt(testPlaintext, testPassword);
      // Mittendrin ein Byte flippen → Auth-Tag-Mismatch.
      final bytes = base64Decode(encrypted);
      // Salt (16) + IV (12) sind unkritisch; ab Byte 28 beginnt Ciphertext+Tag.
      bytes[30] = bytes[30] ^ 0xFF;
      final manipulated = base64Encode(bytes);
      expect(
        () => BackupCrypto.decrypt(manipulated, testPassword),
        throwsA(isA<Exception>()),
        reason: 'Manipulierter Ciphertext darf nicht still entschlüsselt '
            'werden — GCM-Auth-Tag-Mismatch muss werfen.',
      );
    });

    test('Verkürzter Backup-String wirft FormatException', () {
      // Zu kurz, um Salt + IV + Tag zu enthalten.
      const tooShort = 'VEVTVA=='; // "TEST" base64-kodiert
      expect(
        () => BackupCrypto.decrypt(tooShort, testPassword),
        throwsA(isA<FormatException>()),
        reason: 'Strukturell ungültige Backups müssen FormatException werfen.',
      );
    });

    test('Inkorrektes Base64 wirft FormatException', () {
      const notBase64 = '###NICHT-BASE64###';
      expect(
        () => BackupCrypto.decrypt(notBase64, testPassword),
        throwsA(isA<FormatException>()),
      );
    });

    test('Roundtrip mit verschiedenen Passwörtern bleibt stabil', () {
      const passwords = [
        'TEST_pw_a',
        'TEST_pw_b',
        'TEST_pw_c',
      ];
      for (final pw in passwords) {
        final enc = BackupCrypto.encrypt(testPlaintext, pw);
        final dec = BackupCrypto.decrypt(enc, pw);
        expect(dec, equals(testPlaintext), reason: 'Passwort: $pw');
      }
    });

    test('Zwei Verschlüsselungen mit gleichem Input ergeben '
        'unterschiedliche Chiffrate (IV + Salt Frische)', () {
      final c1 = BackupCrypto.encrypt('A', testPassword);
      final c2 = BackupCrypto.encrypt('A', testPassword);
      expect(c1, isNot(equals(c2)));
    });

    test('Roundtrip mit Sonderzeichen im Passwort (Emoji, Umlaute, '
        'Steuerzeichen, >100 Zeichen)', () {
      // Sonderzeichen-Passwörter: Emoji, Umlaute, Steuerzeichen, Leerzeichen.
      final specialPasswords = [
        'TEST_pässwörd_mit_Ümläutén',
        'TEST_pw_with_emoji_🔥_and_💛_and_🔐',
        'TEST_pw_with_newline_\n_and_tab_\t',
        r'TEST_pw with spaces and \$pecial ch@rs!',
        'TEST_${'A' * 150}', // 155 Zeichen (>100)
        'TEST_日本語パスワード',
      ];
      for (final pw in specialPasswords) {
        final enc = BackupCrypto.encrypt(testPlaintext, pw);
        final dec = BackupCrypto.decrypt(enc, pw);
        expect(dec, equals(testPlaintext),
            reason: 'Roundtrip mit Passwort: ${pw.length} Zeichen');
      }
    });
  });
}
