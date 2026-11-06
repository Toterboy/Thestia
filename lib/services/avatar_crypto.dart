import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Clientseitige Verschlüsselung für Profilbilder (v0.8.1, Datenschutz).
///
/// Das Bild wird VOR dem Upload AES-256-GCM-verschlüsselt. Der Server
/// (Supabase Storage) sieht ausschließlich Ciphertext - auch bei einem
/// Bucket-Leak oder internem Zugriff sind die Bilder unlesbar. Der
/// Schlüssel wird zufällig pro Upload generiert und clientseitig im
/// `photos`-Eintrag mitgeführt (`path|key|iv`), denn JEDER berechtigte
/// Betrachter (Matches) muss das Bild entschlüsseln können.
///
/// Sicherheits-Parameter (identisch zu [BackupCrypto]):
/// - AES-256-GCM, 12-Byte-IV, 16-Byte-Auth-Tag
/// - Zufalls-Schlüssel (32 Byte) aus einem kryptografisch sicheren RNG
class AvatarCrypto {
  AvatarCrypto._();

  static const int _keyLength = 32;
  static const int _ivLength = 12;
  static final Random _random = Random.secure();

  /// Trennzeichen im `photos`-Eintrag: `storage/path|keyBase64|ivBase64`.
  static const String separator = '|';

  /// Verschlüsselt Bildbytes. Liefert Ciphertext + Schlüssel/IV (Base64).
  static ({Uint8List cipher, String keyB64, String ivB64}) encrypt(
    Uint8List plaintext,
  ) {
    final key = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => _random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => _random.nextInt(256)),
    );

    final gcm = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final cipher = gcm.process(plaintext);

    return (cipher: cipher, keyB64: base64Encode(key), ivB64: base64Encode(iv));
  }

  /// Entschlüsselt Ciphertext mit Schlüssel/IV. Wirft bei Manipulation
  /// (GCM-Auth-Tag-Mismatch) - der Aufrufer zeigt dann den Platzhalter.
  static Uint8List decrypt(Uint8List cipher, Uint8List key, Uint8List iv) {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return gcm.process(cipher);
  }

  /// Isolate-fähige Hülle für [decrypt] (v0.8.1 FREEZE-FIX): AES-GCM in
  /// pure Dart über 1-2 MB dauert spürbar - Avatar-Entschlüsselung läuft
  /// deshalb per compute() im Hintergrund-Isolate.
  static Uint8List decryptArgs((Uint8List, Uint8List, Uint8List) args) {
    final (cipher, key, iv) = args;
    return decrypt(cipher, key, iv);
  }

  /// Baut den photos-Eintrag: `path|key|iv`.
  static String encodeRef(String path, String keyB64, String ivB64) =>
      '$path$separator$keyB64$separator$ivB64';

  /// Ist der Eintrag verschlüsselt (hat Schlüsselanteile)?
  static bool isEncryptedRef(String ref) => ref.contains(separator);

  /// Zerlegt den Eintrag. Liefert null bei Struktur-Fehlern (Fallback
  /// auf Klartext-Anzeige).
  static ({String path, Uint8List key, Uint8List iv})? parseRef(String ref) {
    final parts = ref.split(separator);
    if (parts.length != 3) return null;
    try {
      return (
        path: parts[0],
        key: base64Decode(parts[1]),
        iv: base64Decode(parts[2]),
      );
    } catch (_) {
      return null;
    }
  }

  /// Nur der Storage-Pfad (ohne Schlüsselanteile) - für deleteAvatar.
  static String pathOf(String ref) => ref.split(separator).first;
}
