import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// Verschlüsselung des Verifikations-Videos (v0.10.0).
///
/// BISHER lag das Video unverschlüsselt im Bucket
/// `verification-videos`. Der Bucket ist privat, aber "privat" heißt
/// nicht "verschlüsselt": jeder mit Lesezugriff auf den Bucket
/// hätte die rohen MP4-Bytes - Gesicht und Stimme, also biometrische
/// Daten im Sinne Art. 9 DSGVO.
///
/// JETZT: Das Video wird auf dem Gerät mit AES-256-GCM verschlüsselt
/// und NUR der Chiffrat kommt in den Bucket. Der Schlüssel geht an
/// den Server, landet aber in einer Tabelle, auf die der Client
/// keinen Zugriff hat. Nur die Edge Function mit Admin-Status kann
/// ihn lesen und das Video für die Sichtung entschlüsseln.
///
/// Das Muster ist bewusst dasselbe wie bei den Profilfotos
/// (avatar_crypto.dart) - gleiche Algorithmen, gleiche Beweislast.
class VerificationCrypto {
  VerificationCrypto._();

  static const int _keyLength = 32;
  static const int _ivLength = 12;
  static final Random _random = Random.secure();

  /// Verschlüsselt Videobytes. Liefert Chiffrat plus Schlüssel und IV
  /// (Base64) für die getrennte Übertragung.
  ///
  /// Schlüssel und IV werden NICHT mit dem Chiffrat zusammen gespeichert
  /// - das wäre dasselbe wie kein Schlüssel. Der Schlüssel geht in
  /// die Schlüsseltabelle, der Chiffrat in den Bucket.
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

  /// Verschlüsselt Videobytes OHNE den UI-Thread zu blockieren.
  ///
  /// NUTZERWUNSCH (01.11.2026): "Die App laggt extrem, wenn ich die
  /// Videörifizierung mache."
  ///
  /// AES-GCM in pure Dart braucht bei 5-25 MB mehrere Sekunden. Auf
  /// dem UI-Isolate friert die App dabei sichtbar ein - die Kamera,
  /// der Spinner und jede Berührung stehen still.
  ///
  /// compute() legt die Arbeit in ein Hintergrund-Isolate. Das Muster
  /// stand schon hier (encryptArgs) - es wurde nur nie benutzt.
  static Future<({Uint8List cipher, String keyB64, String ivB64})> encryptAsync(
    Uint8List plaintext,
  ) async {
    final key = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => _random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => _random.nextInt(256)),
    );
    final cipher = await compute(encryptArgs, (plaintext, key, iv));
    return (cipher: cipher, keyB64: base64Encode(key), ivB64: base64Encode(iv));
  }

  /// Verschlüsselung für einen großen Block: AES-GCM in pure Dart
  /// dauert bei mehreren MB spürbar. Der Aufrufer lässt das deshalb
  /// in einem Hintergrund-Isolate laufen (compute()).
  static Uint8List encryptArgs((Uint8List, Uint8List, Uint8List) args) {
    final (plaintext, key, iv) = args;
    final gcm = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return gcm.process(plaintext);
  }

  /// Entschlüsselt (serverseitig nicht nötig - das macht die Function).
  /// Hier für Tests und Roundtrip-Prüfungen.
  static Uint8List decrypt(Uint8List cipher, Uint8List key, Uint8List iv) {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return gcm.process(cipher);
  }
}
