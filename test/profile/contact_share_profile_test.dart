// Tests für das Modell der freiwilligen Kontaktdaten
// ("Connect to others").
//
// WARUM überhaupt ein Test: Die Telefonnummer ist personenbezogen und
// verlässt das Gerät nie. Deshalb sind zwei Dinge besonders wichtig:
//  1) eine offensichtlich kaputte Nummer wird NICHT gespeichert und
//     NICHT geteilt (sonst schickt jemand "123" an Fremde),
//  2) der Speicher-Stand muss verlustfrei zurückkommen - sonst
//     verliert die Person ihre Angaben beim nächsten Start.
import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/models/profile/contact_share_profile.dart';

void main() {
  group('Telefonnummer', () {
    test('normale Nummern werden akzeptiert', () {
      expect(ContactShareProfile.isValidPhone('+49 170 1234567'), isTrue);
      expect(ContactShareProfile.isValidPhone('0170/1234567'), isTrue);
      expect(ContactShareProfile.isValidPhone('(030) 123456'), isTrue);
    });

    test('zu kurz, zu lang oder mit Buchstaben wird abgelehnt', () {
      // Zu kurz: ein Tippfehler soll nicht wie eine Nummer durchgehen.
      expect(ContactShareProfile.isValidPhone('12345'), isFalse);
      // Zu lang: maximal 15 Ziffern nach E.164.
      expect(ContactShareProfile.isValidPhone('1234567890123456'), isFalse);
      // Buchstaben: keine erfundenen Nummern erfinden.
      expect(ContactShareProfile.isValidPhone('0170 abcdef'), isFalse);
      // Leere Eingabe.
      expect(ContactShareProfile.isValidPhone(''), isFalse);
    });

    test('die Normalisierung behaelt die Schreibweise', () {
      expect(
        ContactShareProfile.normalizePhone('  +49 170 1234567 '),
        '+49 170 1234567',
      );
    });
  });

  group('Speicher-Stand', () {
    test('JSON-Rundlauf verliert nichts', () {
      const profil = ContactShareProfile(
        phone: '+49 170 1234567',
        entries: [
          ContactShareEntry(
            app: 'signal',
            label: 'Signal',
            handle: '@thorst',
            recommended: true,
          ),
          ContactShareEntry(
            app: 'custom',
            label: 'Telegram',
            handle: '@thorst',
            custom: true,
          ),
        ],
      );

      final wieder = ContactShareProfile.fromJsonString(profil.toJsonString());

      expect(wieder.phone, profil.phone);
      expect(wieder.entries.length, 2);
      expect(wieder.entries[0].app, 'signal');
      expect(wieder.entries[0].handle, '@thorst');
      expect(wieder.entries[0].recommended, isTrue);
      expect(wieder.entries[1].custom, isTrue);
    });

    test('kaputter JSON-Stand fuehrt zu einem leeren Profil', () {
      final profil = ContactShareProfile.fromJsonString('kein json');
      expect(profil.phone, isEmpty);
      expect(profil.entries, isEmpty);
      expect(profil.isEmpty, isTrue);
    });

    test('Eintraege ohne Handle sind ungueltig', () {
      const ohneHandle = ContactShareEntry(
        app: 'signal',
        label: 'Signal',
        handle: '   ',
      );
      expect(ohneHandle.isValid, isFalse);
    });
  });
}
