import 'package:flutter_test/flutter_test.dart';

import 'package:wisp/services/mfa_service.dart';

/// Tests fuer den Standard-otpauth-URI, den die 2FA-Einrichtung der
/// Authenticator-App uebergibt (QR-Inhalt + manuelle Eingabe).
void main() {
  group('MfaService.buildOtpAuthUri', () {
    test('enthaelt Secret, Issuer und Standard-Parameter', () {
      final uri = MfaService.buildOtpAuthUri('ABCDEF234567', email: null);

      expect(uri, startsWith('otpauth://totp/'));
      expect(uri, contains('secret=ABCDEF234567'));
      expect(uri, contains('issuer=Wisp'));
      expect(uri, contains('algorithm=SHA1'));
      expect(uri, contains('digits=6'));
      expect(uri, contains('period=30'));
    });

    test('nutzt Email als Konto und encodiert Sonderzeichen', () {
      final uri = MfaService.buildOtpAuthUri(
        'SECRET123',
        email: 'test+tag@beispiel.de',
      );

      // Pfad: otpauth://totp/WispDating:<account>
      expect(uri, contains(RegExp('otpauth://totp/WispDating:test%2Btag%40beispiel\\.de')));
      expect(uri, isNot(contains('+tag@beispiel.de?')));
    });

    test('ohne Email faellt auf generischen Kontonamen zurueck', () {
      final uri = MfaService.buildOtpAuthUri('XYZ', email: null);
      expect(uri, contains('otpauth://totp/WispDating:Nutzer'));
    });

    test('leerer Email-String faellt ebenfalls zurueck', () {
      final uri = MfaService.buildOtpAuthUri('XYZ', email: '');
      expect(uri, contains('otpauth://totp/WispDating:Nutzer'));
    });

    test('ist KEIN SVG-Daten-URI mehr (Regression: Supabase qrCode)', () {
      // Urspruenglich wurde totp.qrCode (data:image/svg+xml;base64,...)
      // an QrImageView durchgereicht - das konnte nicht als QR gerendert
      // werden. Der URI muss immer ein echter otpauth-URI sein.
      final uri = MfaService.buildOtpAuthUri('ABC', email: 'a@b.de');
      expect(uri, isNot(startsWith('data:')));
      expect(uri, startsWith('otpauth://'));
    });
  });
}
