import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/utils/cert_pinning.dart';

/// Unit-Tests für die Cert-Pinning-Konfiguration (DER-Hashes).
void main() {
  test('Alle konfigurierten DER-Pins sind gültiges Base64', () {
    for (final pin in CertPinning.pinnedCertHashes) {
      expect(
        () => base64Decode(pin),
        returnsNormally,
        reason: 'Pin $pin ist kein gültiges Base64.',
      );
    }
  });

  test('Alle DER-Pins haben SHA-256-Länge (32 Bytes)', () {
    for (final pin in CertPinning.pinnedCertHashes) {
      final bytes = base64Decode(pin);
      expect(
        bytes.length,
        equals(32),
        reason: 'Pin $pin hat ${bytes.length} Bytes, erwartet 32.',
      );
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

  // ---------------------------------------------------------------------
  // Der Rotations-Fallback (Audit 16.11.2026)
  //
  // BEFUND: Der Fallback war DAUERHAFT offen. Ein Leaf-Pin-Mismatch
  // wurde still auf CA-Ebene degradiert - der Leaf-Pin war damit
  // faktisch optional (ein CA-Kompromiss waere sofort MITM-faehig).
  // Live belegt: der gepinnte Leaf-Pin war am 24.10.2026 veraltet, und
  // die App lief nur noch ueber diesen Fallback.
  // ---------------------------------------------------------------------
  group('Das Rotationsfenster', () {
    test('ein Pin-Mismatch ist ausserhalb des Fensters fatal', () {
      // Weit vor dem Ablauf des gepinnten Leafs: kein Fallback.
      expect(
        CertPinning.pinMismatchAllowed(
          host: 'jftuigjbmmuvrckbchqo.supabase.co',
          now: DateTime.utc(2026, 11, 16),
        ),
        isFalse,
        reason:
            'Ausserhalb des Rotationsfensters darf ein falscher Leaf-Pin '
            'NICHT durch den Aussteller-Fallback aufgefangen werden.',
      );
    });

    test('im Rotationsfenster ist der Fallback offen', () {
      final fenster = CertPinning.rotationWindowFor(
        'jftuigjbmmuvrckbchqo.supabase.co',
      );
      expect(fenster, isNotNull);
      expect(
        CertPinning.pinMismatchAllowed(
          host: 'jftuigjbmmuvrckbchqo.supabase.co',
          now: fenster!.from.add(const Duration(days: 1)),
        ),
        isTrue,
        reason:
            'Um das Ablaufdatum rotieren die Zertifikate - dort muss der '
            'Fallback offen sein, sonst bricht die App beim Rotieren ab.',
      );
    });

    test('nach dem Fenster ist der Fallback wieder zu', () {
      final fenster = CertPinning.rotationWindowFor(
        'jftuigjbmmuvrckbchqo.supabase.co',
      );
      expect(
        CertPinning.pinMismatchAllowed(
          host: 'jftuigjbmmuvrckbchqo.supabase.co',
          now: fenster!.to.add(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('fuer einen unbekannten Host gibt es keinen Fallback', () {
      expect(
        CertPinning.pinMismatchAllowed(
          host: 'evil-supabase.co',
          now: DateTime.utc(2026, 12, 1),
        ),
        isFalse,
      );
    });
  });

  group('Der gepinnte Leaf ist nicht veraltet', () {
    test('der Leaf-Pin laeuft nicht bald ab', () {
      // BEFUND (Audit 16.11.2026): Der gepinnte Leaf-Pin war am
      // 24.10.2026 veraltet - die App lief nur noch ueber den
      // (dauerhaft offenen) Aussteller-Fallback. Dieser Test verhindert,
      // dass das wieder passiert: laeuft der Pin in unter 30 Tagen ab,
      // muss er vor dem Release erneuert werden.
      final bis = CertPinning.pinnedLeafValidUntil(
        'jftuigjbmmuvrckbchqo.supabase.co',
      );
      expect(bis, isNotNull, reason: 'Der Leaf-Pin braucht ein Ablaufdatum.');
      final tage = bis!.difference(DateTime.now()).inDays;
      expect(
        tage,
        greaterThan(30),
        reason:
            'Der gepinnte Leaf-Pin laeuft in nur $tage Tagen ab - bitte vor '
            'dem Release erneuern (dart run tool/rotate_cert_pins.dart).',
      );
    });
  });
}
