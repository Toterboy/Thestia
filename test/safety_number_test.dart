import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/services/encryption_service.dart';

/// Tests für die Safety-Number-Berechnung (Audit B2).
///
/// Kernforderung: Die Nummer ist SYMMETRISCH – beide Kommunikationspartner
/// berechnen für dieselbe Session dieselbe Nummer. Nur dann funktioniert
/// der Out-of-Band-Vergleich (Telefon/persönlich) und ein unterschobenes
/// PreKey-Bundle (kompromittierter Server) wird erkannt.
void main() {
  Uint8List key(int seed) =>
      Uint8List.fromList(List<int>.generate(33, (i) => (seed + i) % 256));

  test('Symmetrie: Reihenfolge der Keys ist egal (beide Seiten gleich)', () {
    final our = key(1);
    final their = key(99);
    expect(
      EncryptionService.computeSafetyNumber(our, their),
      equals(EncryptionService.computeSafetyNumber(their, our)),
    );
  });

  test('Format: 30 Ziffern in 6 Blöcken à 5 (lesbar/vergleichbar)', () {
    final s = EncryptionService.computeSafetyNumber(key(1), key(2));
    expect(s, matches(RegExp(r'^\d{5}( \d{5}){5}$')));
  });

  test('Unterschiedliche Identitäten ergeben unterschiedliche Nummern', () {
    final s1 = EncryptionService.computeSafetyNumber(key(1), key(2));
    final s2 = EncryptionService.computeSafetyNumber(key(1), key(3));
    expect(s1, isNot(equals(s2)));
  });

  test('Angriffsszenario: unterschobener Key (MITM) erzeugt ABWEICHENDE '
      'Nummer -> wird im Out-of-Band-Vergleich erkannt', () {
    // Alice <-> Bob (echte Keys)
    final aliceBob =
        EncryptionService.computeSafetyNumber(key(1), key(2));
    // Alice <-> Angreifer (unterschobener Key) sieht für Alice anders aus
    final aliceMallory =
        EncryptionService.computeSafetyNumber(key(1), key(66));
    expect(aliceBob, isNot(equals(aliceMallory)));
  });

  test('Determinismus: gleiche Keys -> gleiche Nummer', () {
    final a = EncryptionService.computeSafetyNumber(key(42), key(7));
    final b = EncryptionService.computeSafetyNumber(key(42), key(7));
    expect(a, equals(b));
  });
}
