// Die lokalen Speicher (Keystore und SharedPreferences).
//
// ANLASS (25.11.2026): Die Coverage-Messung zeigte für
// lib/services/storage/local_storage.dart nur 39,5 % Abdeckung. Der
// sichere Speicher trägt die sensiblen Voreinstellungen (Audit M-16:
// die Geschlechter- und Beziehungsvorlieben sind Art.-9-Daten) - und
// seine Fehler fallen nicht auf, sondern nur durch.
//
// DER WEG: Der Keystore ist die Attrappe aus
// test/support/plugin_mocks.dart (mockKeystore), die
// SharedPreferences sind der Test-Ersatz von Flutter.
//
// WAS HIER GEPRÜFT WIRD:
//   * ein Wert landet im sicheren Speicher und kommt wieder heraus,
//   * ein Boolean und eine Zahl kommen als TEXT zurück (nicht als
//     "1"/"true" aus dem Klartext),
//   * ein leerer oder unlesbarer Wert ergibt null (kein Absturz),
//   * die Migration aus dem Klartextspeicher löscht danach die
//     Klartextkopie (sonst wäre das Geheimnis doppelt gespeichert).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thestia/services/storage/local_storage.dart';

import '../support/plugin_mocks.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // DER KEYSTORE: Ohne den Ersatz sucht der Test auf dem CI-Runner
    // das echte Plugin (das findet dort keine libsecret-Sitzung).
    mockKeystore();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
  });

  group('Der sichere Speicher', () {
    test('ein Text kommt wieder heraus', () async {
      final speicher = SecurePreferencesStorage();

      await speicher.saveString('kontaktweg', 'datenschutz@thestia.de');

      expect(
        await speicher.getString('kontaktweg'),
        'datenschutz@thestia.de',
        reason: 'Der Wert muss wieder da sein - sonst waere er weg.',
      );
    });

    test('ein Boolean wird als Text gespeichert', () async {
      final speicher = SecurePreferencesStorage();

      await speicher.saveBool('benachrichtigungen', true);
      await speicher.saveBool('verlauf', false);

      expect(await speicher.getBool('benachrichtigungen'), isTrue);
      expect(
        await speicher.getBool('verlauf'),
        isFalse,
        reason: 'Ein "false" muss auch als false zurueckkommen.',
      );
    });

    test('eine Zahl kommt als Zahl zurueck', () async {
      final speicher = SecurePreferencesStorage();

      await speicher.saveInt('gelesen', 58);

      expect(await speicher.getInt('gelesen'), 58);
    });

    test('ein unbekannter Wert ergibt null', () async {
      final speicher = SecurePreferencesStorage();

      expect(await speicher.getString('gibtsnicht'), isNull);
      expect(await speicher.getBool('gibtsnicht'), isNull);
      expect(await speicher.getInt('gibtsnicht'), isNull);
    });

    test('ein unlesbarer Zahlentext ergibt null', () async {
      final speicher = SecurePreferencesStorage();

      // DER KAPUTTE WERT: Er kommt aus einer alten Fassung der App.
      await speicher.saveString('kaputt', 'keine zahl');

      expect(
        await speicher.getInt('kaputt'),
        isNull,
        reason:
            'Ein kaputter Wert darf keinen Absturz ausloesen - der Nutzer '
            'sieht sonst nur einen Fehler statt der App.',
      );
    });

    test('ein geloeschter Wert ist wirklich weg', () async {
      final speicher = SecurePreferencesStorage();
      await speicher.saveString('weg', 'da');

      await speicher.remove('weg');

      expect(
        await speicher.getString('weg'),
        isNull,
        reason:
            'Nach dem Loeschen darf der Wert nicht mehr da sein - sonst '
            'bleibt eine alte Einstellung stehen.',
      );
    });

    test('die Migration verschiebt den Wert und loescht die Kopie', () async {
      final speicher = SecurePreferencesStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alter_schluessel', 'der_alte_wert');

      await speicher.migrateStringFrom(prefs, 'alter_schluessel');

      expect(
        await speicher.getString('alter_schluessel'),
        'der_alte_wert',
        reason: 'Der Wert muss jetzt im sicheren Speicher stehen.',
      );
      expect(
        prefs.getString('alter_schluessel'),
        isNull,
        reason:
            'Die Klartextkopie muss weg - sonst steht das Geheimnis '
            'zweimal auf dem Geraet (und im Klartext lesbar).',
      );
    });

    test('die Migration laeuft nicht zweimal', () async {
      final speicher = SecurePreferencesStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alter_schluessel', 'der_alte_wert');

      await speicher.migrateStringFrom(prefs, 'alter_schluessel');
      // DER ZWEITE DURCHLAUF: Der Wert im sicheren Speicher wird nicht
      // mehr vom Klartext überschrieben.
      await prefs.setString('alter_schluessel', 'ein_neuer_wert');
      await speicher.migrateStringFrom(prefs, 'alter_schluessel');

      expect(
        await speicher.getString('alter_schluessel'),
        'der_alte_wert',
        reason:
            'Der sichere Stand ist der Gewinner - ein alter Klartextrest '
            'darf ihn nicht zuruecksetzen.',
      );
    });
  });

  group('Der Klartextspeicher', () {
    test('speichert und liest alle Arten', () async {
      final prefs = await SharedPreferences.getInstance();
      final speicher = SharedPreferencesStorage(prefs);

      await speicher.saveString('text', 'Hallo');
      await speicher.saveBool('flagge', true);
      await speicher.saveInt('zahl', 42);

      expect(await speicher.getString('text'), 'Hallo');
      expect(await speicher.getBool('flagge'), isTrue);
      expect(await speicher.getInt('zahl'), 42);
    });

    test('ein geloeschter Wert ist weg', () async {
      final prefs = await SharedPreferences.getInstance();
      final speicher = SharedPreferencesStorage(prefs);
      await speicher.saveString('weg', 'da');

      await speicher.remove('weg');

      expect(await speicher.getString('weg'), isNull);
    });
  });
}
