// Der Speicher der freiwilligen Kontaktdaten.
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte fuer
// lib/services/storage/secure_contact_share_store.dart nur 33 %
// Abdeckung.
//
// DATENSCHUTZ: Telefonnummer und Handles liegen ausschliesslich im
// Keystore (Android) bzw. in der Keychain (iOS) - sie gehen NIE zum
// Server. Dieser Speicher ist also der einzige Ort, an dem sie stehen.
//
// DER WEG: Der Keystore ist die Attrappe aus
// test/support/plugin_mocks.dart (mockKeystore).
//
// WAS HIER GEPRUEFT WIRD:
//   * die Kontaktdaten kommen wieder heraus (unveraendert),
//   * ohne gespeicherte Daten gibt es ein leeres Profil (kein Fehler),
//   * kaputte Daten blockieren die App nicht,
//   * das Loeschen nimmt die Daten wirklich weg.
import 'package:flutter_test/flutter_test.dart';

import 'package:thestia/models/profile/contact_share_profile.dart';
import 'package:thestia/services/storage/secure_contact_share_store.dart';

import '../support/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: Ohne den Ersatz sucht der Test auf dem CI-Runner
    // das echte Plugin (das findet dort keine libsecret-Sitzung).
    mockKeystore();
  });

  setUp(() {
    // Jeder Test startet mit einem leeren Speicher.
    keystoreInhalt.clear();
  });

  group('Der Kontakt-Speicher', () {
    test('die Daten kommen wieder heraus', () async {
      final speicher = SecureContactShareStore();
      const profil = ContactShareProfile(
        phone: '+49 151 12345678',
        entries: <ContactShareEntry>[
          ContactShareEntry(app: 'signal', label: 'Signal', handle: 'lena.er'),
        ],
      );

      await speicher.save(profil);
      final geladen = await speicher.load();

      expect(geladen.phone, '+49 151 12345678');
      expect(geladen.entries, hasLength(1));
      expect(geladen.entries.first.handle, 'lena.er');
      expect(
        keystoreInhalt['contact_share_profile'],
        isNotNull,
        reason:
            'Die Daten muessen im Keystore stehen - das ist der einzige '
            'Ort, an dem sie liegen duerfen.',
      );
    });

    test('ohne gespeicherte Daten gibt es ein leeres Profil', () async {
      final speicher = SecureContactShareStore();

      final geladen = await speicher.load();

      expect(geladen.phone, isEmpty);
      expect(geladen.entries, isEmpty);
    });

    test('kaputte Daten blockieren die App nicht', () async {
      final speicher = SecureContactShareStore();
      // DER KAPUTTE WERT: Er kommt aus einer alten Fassung der App.
      keystoreInhalt['contact_share_profile'] = 'kein json';

      final geladen = await speicher.load();

      expect(
        geladen.phone,
        isEmpty,
        reason:
            'Ein kaputter Eintrag darf die App nicht blockieren - der '
            'Nutzer muss die Kontaktdaten neu eintragen koennen.',
      );
    });

    test('das Loeschen nimmt die Daten weg', () async {
      final speicher = SecureContactShareStore();
      await speicher.save(const ContactShareProfile(phone: '+49 151 12345678'));

      await speicher.clear();

      expect(
        (await speicher.load()).phone,
        isEmpty,
        reason:
            'Nach dem Loeschen muss der Wert weg sein - sonst bleiben die '
            'Kontaktdaten auf dem Geraet, obwohl der Nutzer sie entfernt '
            'hat.',
      );
    });
  });
}
