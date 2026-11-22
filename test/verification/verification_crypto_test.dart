// Die Verschluesselung des Verifikations-Videos.
//
// ANLASS (22.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/verification/verification_crypto.dart 0 % Abdeckung. Das
// Video einer Verifizierung ist biometrische Daten im Sinne Art. 9 DSGVO
// (Gesicht und Stimme) - es wird auf dem Geraet mit AES-256-GCM
// verschluesselt, und NUR der Chiffrat kommt in den Bucket.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Roundtrip: verschluesseln und wieder entschluesseln ergibt
//     wieder die Originalbytes,
//   * Schluessel und IV stehen NICHT im Chiffrat (sonst waere die
//     Verschluesselung sinnlos),
//   * ein fremder Schluessel liefert Muell,
//   * die asynchrone Variante (im Hintergrund-Isolate) liefert dasselbe
//     Ergebnis.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'package:thestia/services/verification/verification_crypto.dart';

/// Steht der Block [block] als zusammenhaengender Teil in [gros]?
///
/// DER GRUND: `List.contains` sucht nur EIN Byte. Ein einzelnes
/// zufaellig gleiches Byte waere kein Beweis - der Schluessel muss
/// als GANZER Block im Chiffrat stehen, damit die Aussage stimmt.
bool _enthaeltBlock(List<int> gros, List<int> block) {
  if (block.isEmpty || block.length > gros.length) return false;
  for (var start = 0; start + block.length <= gros.length; start++) {
    var gleich = true;
    for (var i = 0; i < block.length; i++) {
      if (gros[start + i] != block[i]) {
        gleich = false;
        break;
      }
    }
    if (gleich) return true;
  }
  return false;
}

void main() {
  group('Die Verschluesselung des Verifikations-Videos', () {
    test('der Roundtrip liefert die Originalbytes zurueck', () {
      final videobytes = Uint8List.fromList(
        List<int>.generate(5000, (i) => i % 256),
      );

      final ergebnis = VerificationCrypto.encrypt(videobytes);
      final schluessel = base64Decode(ergebnis.keyB64);
      final iv = base64Decode(ergebnis.ivB64);

      final wieder = VerificationCrypto.decrypt(
        ergebnis.cipher,
        schluessel,
        iv,
      );

      expect(
        wieder,
        videobytes,
        reason:
            'Die Sichtung muss das Video unveraendert bekommen - sonst '
            'laesst sich die Verifizierung nicht pruefen.',
      );
    });

    test('der Chiffrat ist nicht der Klartext', () {
      final videobytes = Uint8List.fromList(List<int>.generate(100, (i) => i));

      final ergebnis = VerificationCrypto.encrypt(videobytes);

      expect(
        ergebnis.cipher.length,
        videobytes.length + 16,
        reason: 'GCM haengt die Authentifizierungsdaten an (16 Byte).',
      );
      expect(
        ergebnis.cipher,
        isNot(equals(videobytes)),
        reason:
            'Im Bucket darf nicht der Klartext liegen - sonst haette jeder '
            'mit Lesezugriff Gesicht und Stimme.',
      );
    });

    test('Schluessel und IV stehen nicht im Chiffrat', () {
      final ergebnis = VerificationCrypto.encrypt(
        Uint8List.fromList(List<int>.filled(64, 7)),
      );

      final schluessel = base64Decode(ergebnis.keyB64);
      final iv = base64Decode(ergebnis.ivB64);

      expect(schluessel.length, 32, reason: 'AES-256 = 32 Byte Schluessel.');
      expect(iv.length, 12, reason: 'GCM nutzt 12 Byte IV.');
      expect(
        _enthaeltBlock(ergebnis.cipher, schluessel),
        isFalse,
        reason:
            'Der Schluessel gehoert in die Schluesseltabelle, nicht in den '
            'Bucket - zusammen waere es dasselbe wie kein Schluessel.',
      );
      expect(_enthaeltBlock(ergebnis.cipher, iv), isFalse);
    });

    test('zwei Verschluesselungen desselben Videos sind verschieden', () {
      final videobytes = Uint8List.fromList(List<int>.filled(32, 3));

      final a = VerificationCrypto.encrypt(videobytes);
      final b = VerificationCrypto.encrypt(videobytes);

      expect(
        a.keyB64,
        isNot(b.keyB64),
        reason:
            'Jede Verschluesselung braucht einen neuen Schluessel - sonst '
            'koennte man gleiche Videos erkennen.',
      );
      expect(a.ivB64, isNot(b.ivB64));
    });

    test('ein fremder Schluessel wird abgewiesen', () {
      final videobytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

      final ergebnis = VerificationCrypto.encrypt(videobytes);

      final fremderSchluessel = Uint8List.fromList(List<int>.filled(32, 9));

      expect(
        () => VerificationCrypto.decrypt(
          ergebnis.cipher,
          fremderSchluessel,
          base64Decode(ergebnis.ivB64),
        ),
        throwsA(isA<InvalidCipherTextException>()),
        reason:
            'Mit dem falschen Schluessel darf das Video nicht lesbar sein - '
            'GCM weist die Manipulation ab.',
      );
    });

    test('die asynchrone Variante liefert dasselbe Ergebnis', () async {
      final videobytes = Uint8List.fromList(
        List<int>.generate(2000, (i) => (i * 7) % 256),
      );

      final ergebnis = await VerificationCrypto.encryptAsync(videobytes);

      final wieder = VerificationCrypto.decrypt(
        ergebnis.cipher,
        base64Decode(ergebnis.keyB64),
        base64Decode(ergebnis.ivB64),
      );

      expect(
        wieder,
        videobytes,
        reason:
            'Die Variante im Hintergrund-Isolate muss genauso arbeiten wie '
            'die synchrone - sonst waeren die Videos unterschiedlich '
            'verschluesselt.',
      );
    });

    test('das leere Video laesst sich verschluesseln', () {
      final ergebnis = VerificationCrypto.encrypt(Uint8List(0));

      expect(ergebnis.cipher.length, 16);
      expect(
        VerificationCrypto.decrypt(
          ergebnis.cipher,
          base64Decode(ergebnis.keyB64),
          base64Decode(ergebnis.ivB64),
        ),
        isEmpty,
      );
    });
  });
}
