import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/utils/cert_pinning.dart';

/// Unit-Tests für die Cert-Pinning-Konfiguration (DER-Hashes).
void main() {
  test('Alle konfigurierten DER-Pins sind gültiges Base64', () {
    for (final pin in CertPinning.pinnedCertHashes) {
      expect(() => base64Decode(pin), returnsNormally,
          reason: 'Pin $pin ist kein gültiges Base64.');
    }
  });

  test('Alle DER-Pins haben SHA-256-Länge (32 Bytes)', () {
    for (final pin in CertPinning.pinnedCertHashes) {
      final bytes = base64Decode(pin);
      expect(bytes.length, equals(32),
          reason: 'Pin $pin hat ${bytes.length} Bytes, erwartet 32.');
    }
  });

  test('Mindestens 3 DER-Pins (Leaf + Intermediate + Root)', () {
    expect(CertPinning.pinnedCertHashes.length, greaterThanOrEqualTo(3));
  });

  test('Alle DER-Pins sind untereinander verschieden', () {
    final unique = CertPinning.pinnedCertHashes.toSet();
    expect(unique.length, equals(CertPinning.pinnedCertHashes.length));
  });

  test('isPinnedHost erkennt gepinnte Hosts (case-insensitiv, v0.9.0)', () {
    expect(
      CertPinning.isPinnedHost('jftuigjbmmuvrckbchqo.supabase.co'),
      isTrue,
    );
    expect(
      CertPinning.isPinnedHost('JFTUIGJBMMUVRCKBCHQO.SUPABASE.CO'),
      isTrue,
    );
    expect(CertPinning.isPinnedHost('router.huggingface.co'), isTrue);
    expect(CertPinning.isPinnedHost('evil-supabase.co'), isFalse);
    expect(CertPinning.isPinnedHost('supabase.co'), isFalse);
    expect(CertPinning.isPinnedHost(''), isFalse);
  });
}
