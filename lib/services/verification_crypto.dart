import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Verschluesselung des Verifikations-Videos (v0.10.0).
///
/// BISHER lag das Video unverschluesselt im Bucket
/// `verification-videos`. Der Bucket ist privat, aber "privat" heisst
/// nicht "verschluesselt": jeder mit Lesezugriff auf den Bucket
/// haette die rohen MP4-Bytes - Gesicht und Stimme, also biometrische
/// Daten im Sinne Art. 9 DSGVO.
///
/// JETZT: Das Video wird auf dem Geraet mit AES-256-GCM verschluesselt
/// und NUR der Chiffrat kommt in den Bucket. Der Schluessel geht an
/// den Server, landet aber in einer Tabelle, auf die der Client
/// keinen Zugriff hat. Nur die Edge Function mit Admin-Status kann
/// ihn lesen und das Video fuer die Sichtung entschluesseln.
///
/// Das Muster ist bewusst dasselbe wie bei den Profilfotos
/// (avatar_crypto.dart) - gleiche Algorithmen, gleiche Beweislast.
class VerificationCrypto {
  VerificationCrypto._();

  static const int _keyLength = 32;
  static const int _ivLength = 12;
  static final Random _random = Random.secure();

  /// Verschluesselt Videobytes. Liefert Chiffrat plus Schluessel und IV
  /// (Base64) fuer die getrennte Uebertragung.
  ///
  /// Schluessel und IV werden NICHT mit dem Chiffrat zusammen gespeichert
  /// - das waere dasselbe wie kein Schluessel. Der Schluessel geht in
  /// die Schluesseltabelle, der Chiffrat in den Bucket.
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
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );
    final cipher = gcm.process(plaintext);

    return (
      cipher: cipher,
      keyB64: base64Encode(key),
      ivB64: base64Encode(iv),
    );
  }

  /// Verschluesselung fuer einen grossen Block: AES-GCM in pure Dart
  /// dauert bei mehreren MB spuerbar. Der Aufrufer laesst das deshalb
  /// in einem Hintergrund-Isolate laufen (compute()).
  static Uint8List encryptArgs((Uint8List, Uint8List, Uint8List) args) {
    final (plaintext, key, iv) = args;
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );
    return gcm.process(plaintext);
  }

  /// Entschluesselt (serverseitig nicht noetig - das macht die Function).
  /// Hier fuer Tests und Roundtrip-Pruefungen.
  static Uint8List decrypt(
    Uint8List cipher,
    Uint8List key,
    Uint8List iv,
  ) {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return gcm.process(cipher);
  }
}
