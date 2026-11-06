import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Reine Kryptographie-Schicht für verschlüsselte Backups.
///
/// Kapselt die kryptographische Logik (PBKDF2-Key-Derivation, AES-256-GCM
/// Ver-/Entschlüsselung) ohne jede Abhängigkeit zu Hive, Supabase oder
/// anderen Storage-Schichten.
///
/// Wird sowohl vom [EncryptionService.createEncryptedBackup] /
/// [restoreFromBackup] (Produktion) als auch von Unit-Tests direkt
/// verwendet — es gibt genau EINE Implementierung der Krypto-Logik.
///
/// Sicherheits-Parameter:
/// - KDF: PBKDF2-HMAC-SHA256, 600.000 Iterationen, 16-Byte-Salt
/// - Verschlüsselung: AES-256-GCM, 12-Byte-IV, 16-Byte-Auth-Tag
/// - Backup-Format (Base64-kodiert):
///   `salt (16) || iv (12) || ciphertext || gcm-tag (16)`
class BackupCrypto {
  BackupCrypto._();

  /// PBKDF2-Iterationen. 600.000 entspricht den OWASP-Empfehlungen für
  /// PBKDF2-HMAC-SHA256 (Stand 2023+).
  static const int pbkdf2Iterations = 600000;

  /// Salt-Länge in Bytes (16 = 128 Bit, NIST-empfohlen).
  static const int saltLength = 16;

  /// AES-GCM-IV-Länge in Bytes (12 = 96 Bit, NIST-empfohlen).
  static const int ivLength = 12;

  /// Ziel-Schlüssellänge in Bytes (32 = 256 Bit für AES-256).
  static const int keyLength = 32;

  /// GCM-Tag-Länge in Bit (128 = 16 Bytes, Standard).
  static const int tagLengthBits = 128;

  /// Verschlüsselt [plaintext] (UTF-8) mit einem aus [password] abgeleiteten
  /// AES-256-GCM-Schlüssel. Liefert `salt || iv || ciphertext || tag` als
  /// Base64-String.
  ///
  /// Wirft [FormatException], wenn die Eingabe leer ist.
  static String encrypt(String plaintext, String password) {
    if (plaintext.isEmpty) {
      throw const FormatException('Klartext darf nicht leer sein.');
    }
    final salt = _randomBytes(saltLength);
    final iv = _randomBytes(ivLength);
    final key = _deriveKey(password, salt);

    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), tagLengthBits, iv, Uint8List(0)),
      );
    final ciphertext = gcm.process(Uint8List.fromList(utf8.encode(plaintext)));

    final combined = Uint8List(salt.length + iv.length + ciphertext.length)
      ..setAll(0, salt)
      ..setAll(salt.length, iv)
      ..setAll(salt.length + iv.length, ciphertext);

    return base64Encode(combined);
  }

  /// Entschlüsselt einen mit [encrypt] erzeugten Base64-Backup-String.
  ///
  /// Wirft:
  /// - [FormatException] bei strukturell ungültigen Eingaben
  ///   (zu kurz, kein gültiges Base64)
  /// - [InvalidBackupException] bei Auth-Tag-Mismatch (falsches Passwort
  ///   oder manipulierte Daten). GCM garantiert, dass dies kontrolliert
  ///   fehlschlägt — kein stiller Datenverlust.
  static String decrypt(String backupBase64, String password) {
    final Uint8List combined;
    try {
      combined = base64Decode(backupBase64);
    } on FormatException catch (e) {
      throw FormatException('Backup ist kein gültiges Base64: ${e.message}');
    }

    if (combined.length < saltLength + ivLength + tagLengthBits ~/ 8) {
      throw const FormatException('Backup Daten sind beschädigt oder zu kurz.');
    }

    final salt = combined.sublist(0, saltLength);
    final iv = combined.sublist(saltLength, saltLength + ivLength);
    final ciphertext = combined.sublist(saltLength + ivLength);
    final key = _deriveKey(password, salt);

    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), tagLengthBits, iv, Uint8List(0)),
      );

    final Uint8List decrypted;
    try {
      decrypted = gcm.process(ciphertext);
    } catch (e) {
      throw InvalidBackupException(
        'Backup konnte nicht entschlüsselt werden. '
        'Falsches Passwort oder manipulierte Daten.',
      );
    }

    return utf8.decode(decrypted);
  }

  /// Leitet einen 256-Bit-AES-Key via PBKDF2-HMAC-SHA256 ab.
  static Uint8List _deriveKey(String password, List<int> salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(
      Pbkdf2Parameters(Uint8List.fromList(salt), pbkdf2Iterations, keyLength),
    );
    return Uint8List.fromList(
      derivator.process(Uint8List.fromList(utf8.encode(password))),
    );
  }

  /// Erzeugt kryptographisch sichere Zufallsbytes via Fortuna (PRNG aus
  /// PointyCastle), geseedet mit `Random.secure()` (kryptographisch starker
  /// Zufallsgenerator der Plattform, z. B. /dev/urandom).
  static Uint8List _randomBytes(int length) {
    final rng = SecureRandom('Fortuna')
      ..seed(
        KeyParameter(
          Uint8List.fromList(
            List<int>.generate(32, (_) => Random.secure().nextInt(256)),
          ),
        ),
      );
    return Uint8List.fromList(rng.nextBytes(length));
  }
}

/// Wird geworfen, wenn das Backup strukturell korrekt ist, aber die
/// Authentizitätsprüfung (GCM-Tag) fehlschlägt. Mögliche Ursachen:
/// - Falsches Passwort
/// - Manipulierte Backup-Daten
/// - Korrupte Backup-Datei
class InvalidBackupException implements Exception {
  InvalidBackupException(this.message);
  final String message;
  @override
  String toString() => 'InvalidBackupException: $message';
}
