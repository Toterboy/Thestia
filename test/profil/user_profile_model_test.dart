// Das Nutzerprofil: Verifikationsstand, ehrliches Lesen und Gleichheit.
//
// ANLASS (19.11.2026): `lib/models/user_profile.dart` war nur zu 91 %
// abgedeckt. Gerade die R\u00fcckfall-Wege sind wichtig: kommt ein
// unerwarteter Wert vom Server, darf die App nicht abstuerzen und
// nicht die falsche Stufe anzeigen.
//
// WAS HIER GEPRUEFT WIRD:
//   * der Verifikationsstand wird aus der Projektion gelesen, mit
//     Rueckfall auf das alte `is_verified`,
//   * der gespeicherte Zustand wird gelesen (ENUM-Name oder Serverwert),
//   * Wahrheitswerte kommen als bool ODER als Text ("true") an,
//   * zwei Profile mit gleichem Inhalt sind gleich (und haben denselben
//     Hash - sonst wuerde der Cache sie als verschieden halten).
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/user_profile.dart';

void main() {
  group('Der Verifikationsstand aus der Projektion', () {
    test('die drei Serverwerte werden gelesen', () {
      expect(
        VerificationState.fromJson(<String, dynamic>{
          'verification_state': 'verified',
        }),
        VerificationState.verified,
      );
      expect(
        VerificationState.fromJson(<String, dynamic>{
          'verification_state': 'under_review',
        }),
        VerificationState.underReview,
      );
      expect(
        VerificationState.fromJson(<String, dynamic>{
          'verification_state': 'unverified',
        }),
        VerificationState.unverified,
      );
    });

    test('fehlt das Feld, entscheidet das alte is_verified', () {
      expect(
        VerificationState.fromJson(const <String, dynamic>{}),
        VerificationState.unverified,
      );
      expect(
        VerificationState.fromJson(const <String, dynamic>{}, isVerified: true),
        VerificationState.verified,
        reason:
            'Ohne die Projektion darf das verifizierte Abzeichen nicht '
            'verloren gehen.',
      );
    });

    test('ein unbekannter Wert faellt auf is_verified zurueck', () {
      expect(
        VerificationState.fromJson(<String, dynamic>{
          'verification_state': 'quatsch',
        }),
        VerificationState.unverified,
      );
      expect(
        VerificationState.fromJson(<String, dynamic>{'verification_state': 42}),
        VerificationState.unverified,
      );
    });

    test('nur der freigegebene Stand gibt den Vollzugang frei', () {
      expect(VerificationState.verified.grantsFullAccess, isTrue);
      expect(VerificationState.underReview.grantsFullAccess, isFalse);
      expect(VerificationState.unverified.grantsFullAccess, isFalse);
    });
  });

  group('Das Lesen des Profils', () {
    test('ein Text "true" wird als Wahrheit gelesen', () {
      // DER GRUND: Ein Cache kann "true" als TEXT liefern. Ein
      // `as bool?` wuerde dann die ganze Profilerzeugung sprengen.
      final profil = UserProfile.fromJson(<String, dynamic>{
        'id': 'u1',
        'name': 'Lena',
        'is_verified': 'true',
        'is_location_suspicious': 'false',
      });
      expect(profil.isVerified, isTrue);
      expect(profil.isLocationSuspicious, isFalse);
    });

    test('unbekannte Wahrheitswerte bleiben false', () {
      final profil = UserProfile.fromJson(<String, dynamic>{
        'id': 'u1',
        'name': 'Lena',
        'is_verified': 'vielleicht',
      });
      expect(profil.isVerified, isFalse);
    });

    test('der Verifikationsstand wird aus dem Feld gelesen', () {
      final profil = UserProfile.fromJson(<String, dynamic>{
        'id': 'u1',
        'name': 'Lena',
        'verification_state': 'under_review',
      });
      expect(profil.verificationState, VerificationState.underReview);
      expect(profil.verificationState.grantsFullAccess, isFalse);
    });

    test('das Lieblingsband wird in der oeffentlichen Sicht getrimmt', () {
      // DER GRUND: In der oeffentlichen Projektion kommt der Wert vom
      // Server - mit Leerzeichen drum. Ohne Trim steht " Kontra Kugel "
      // in der Anzeige.
      final profil = UserProfile.fromPublicView(<String, dynamic>{
        'id': 'u1',
        'name': 'Lena',
        'favorite_band': '  Kontra Kugel  ',
      });
      expect(profil.favoriteBand, 'Kontra Kugel');
    });
  });

  group('Zwei Profile mit gleichem Inhalt', () {
    test('sind gleich und haben denselben Hash', () {
      // DER GRUND: Der Cache (Hive) vergleicht Profile. Sind zwei
      // gleiche Profile ungleich, schreibt der Cache jedes Mal neu.
      const a = UserProfile(
        id: 'u1',
        name: 'Lena',
        bio: 'Hallo',
        mood: 'happy',
      );
      const b = UserProfile(
        id: 'u1',
        name: 'Lena',
        bio: 'Hallo',
        mood: 'happy',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('ein Unterschied macht sie verschieden', () {
      const a = UserProfile(id: 'u1', name: 'Lena', bio: '');
      const b = UserProfile(id: 'u1', name: 'Mira', bio: '');
      expect(a == b, isFalse);
    });

    test('ein anderes Objekt ist nicht gleich', () {
      const a = UserProfile(id: 'u1', name: 'Lena', bio: '');
      // Als Object verglichen - sonst meint der Analyser, der Vergleich
      // sei schon beim Lesen sinnlos (und wuerde den Test bemangeln).
      final Object anders = 'u1';
      expect(a == anders, isFalse);
    });
  });
}
