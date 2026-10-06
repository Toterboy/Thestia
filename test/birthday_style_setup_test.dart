import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thestia/widgets/birthday_style.dart';

/// Tests fuer den Geburtstags-Stil und die neue Einrichtungs-Seite.
///
/// Anlass: der Stil wurde bei einer frischen Registrierung nie abgefragt
/// (erst beim App-Update), und die Vorschau war eine 128-px-Kachel -
/// gemeldet als "zeigt nur das kleine Bild".
void main() {
  group('BirthdayStyle', () {
    test('die fuenf Stile sind fest', () {
      expect(BirthdayStyle.values, [
        'classic',
        'midnight',
        'sage',
        'rose',
        'mono',
      ]);
    });

    test('unbekannter Slug faellt auf classic zurueck', () {
      // Der Wert kommt aus der DB (CHECK-Constraint) und aus altem
      // lokalem State. Ein unbekannter Slug darf das Profil nicht
      // unlesbar machen.
      expect(BirthdayStyle.orDefault(null), 'classic');
      expect(BirthdayStyle.orDefault(''), 'classic');
      expect(BirthdayStyle.orDefault('neon'), 'classic');
      expect(BirthdayStyle.orDefault('midnight'), 'midnight');
    });

    test('isKnown unterscheidet echte von fremden Slugs', () {
      for (final s in BirthdayStyle.values) {
        expect(BirthdayStyle.isKnown(s), isTrue, reason: s);
      }
      expect(BirthdayStyle.isKnown('neon'), isFalse);
      expect(BirthdayStyle.isKnown(''), isFalse);
    });

    test('labelKey bildet die Label-Familie', () {
      for (final s in BirthdayStyle.values) {
        expect(BirthdayStyle.labelKey(s), 'birthday.style.$s');
      }
    });
  });

  group('Einrichtungs-Struktur', () {
    final src =
        File('lib/screens/onboarding/settings_privacy_once_screen.dart')
            .readAsStringSync();

    test('die Seite mit dem Geburtstags-Stil existiert', () {
      expect(src.contains("questionKey: 'setupq.birthday'"), isTrue);
    });

    test('die Seite nutzt die GROSSE Vorschau', () {
      // Gegenprobe zur Absicht: ohne `large: true` waere es wieder die
      // 128-px-Kachel, und der gemeldete Fehler bestuende sich.
      expect(src.contains('large: true'), isTrue);
    });

    test('die Vorschau wird NICHT in die Profilseite gepackt', () {
      // Die Entscheidung war eine eigene Seite, nicht ein weiteres
      // Feld auf der Profilseite.
      final profileIdx = src.indexOf("questionKey: 'setupq.profile'");
      final birthdayIdx = src.indexOf("questionKey: 'setupq.birthday'");
      expect(profileIdx, greaterThan(-1));
      expect(birthdayIdx, greaterThan(-1));
      expect(birthdayIdx, greaterThan(profileIdx));
    });

    test('die Seitenanzahl stimmt mit den Seiten ueberein', () {
      // Zehn Seiten: Filter, Profil, Vorstellung, Geburtstag, Musik,
      // Gewohnheiten, Datenschutz/Theme, Passkey, 2FA, Richtlinien.
      // Stimmt eine der beiden Zahlen nicht, stimmt der Fortschritt nicht.
      expect(src.contains('static const int _pageCount = 10;'), isTrue);
      final count = RegExp(r'questionKey:').allMatches(src).length;
      expect(count, 10, reason: 'PageView braucht genau _pageCount Kinder');
    });

    test('die Passkey- und MFA-Sprungziele passen zur neuen Reihenfolge', () {
      // Zwei neue Seiten (Geburtstag, Musik) schieben beide Ziele um zwei.
      // Ein alter Zielindex wuerde den Nutzer auf die 2FA-Seite statt auf
      // den Passkey schicken.
      expect(src.contains('jumpToPage(7); // Passkey-Seite'), isTrue);
      expect(src.contains('jumpToPage(8); // 2FA-Seite'), isTrue);
      expect(src.contains('jumpToPage(5); // Passkey-Seite'), isFalse);
      expect(src.contains('jumpToPage(6); // 2FA-Seite'), isFalse);
    });

    test('der Geburtstags-Stil wird serverseitig gespeichert', () {
      // Nur lokal gespeichert waer nach dem Neustart weg - dasselbe
      // Muster wie beim fehlenden Profilbild-Write.
      expect(src.contains("'birthday_style': _birthdayStyle"), isTrue);
    });

    test('der Stil wird auch beim Abschluss gesichert', () {
      // Wer auf der Stilauswahl "Weiter" nicht tippt und stattdessen
      // ueber den Security-Nudge abschliesst, darf den Stil nicht
      // verlieren.
      expect(src.contains('await _saveBirthdayStyle();'), isTrue);
    });
  });

  group('L10n-Schluessel', () {
    final src = File('lib/l10n/app_strings.dart').readAsStringSync();

    test('setupq.birthday existiert in DE und EN', () {
      final deMarker = "  'de': {";
      final enMarker = "  'en': {";
      final de = src.substring(src.indexOf(deMarker), src.indexOf(enMarker));
      final en = src.substring(src.indexOf(enMarker));
      expect(de.contains("'setupq.birthday'"), isTrue);
      expect(en.contains("'setupq.birthday'"), isTrue);
      expect(de.contains("'setup.birthdaySub'"), isTrue);
      expect(en.contains("'setup.birthdaySub'"), isTrue);
    });

    test('jeder Stil hat ein Label in beiden Sprachen', () {
      final deMarker = "  'de': {";
      final enMarker = "  'en': {";
      final de = src.substring(src.indexOf(deMarker), src.indexOf(enMarker));
      final en = src.substring(src.indexOf(enMarker));
      for (final style in BirthdayStyle.values) {
        final key = "'birthday.style.$style'";
        expect(de.contains(key), isTrue, reason: 'DE $key');
        expect(en.contains(key), isTrue, reason: 'EN $key');
      }
    });

    test('setupq.music existiert in DE und EN', () {
      final deMarker = "  'de': {";
      final enMarker = "  'en': {";
      final de = src.substring(src.indexOf(deMarker), src.indexOf(enMarker));
      final en = src.substring(src.indexOf(enMarker));
      expect(de.contains("'setupq.music'"), isTrue);
      expect(en.contains("'setupq.music'"), isTrue);
    });
  });

  group('Musik-Schluessel (Slugs, keine Labels)', () {
    final setupSrc =
        File('lib/screens/onboarding/settings_privacy_once_screen.dart')
            .readAsStringSync();

    test('die Musik-Seite existiert', () {
      expect(setupSrc.contains("questionKey: 'setupq.music'"), isTrue);
    });

    test('sie benutzt das Slug-Widget, nicht die alten Labels', () {
      // Gegenprobe zur Absicht: `presetMusicGenres` sind deutsche
      // Labels. Die wanderten ungefiltert nach profiles.music_liked,
      // wo das Matching Slugs erwartet - die Angabe wirkte dann nicht.
      expect(setupSrc.contains('MusicTasteEditor'), isTrue);
      expect(setupSrc.contains('presetMusicGenres'), isFalse);
    });

    test('Lied und Band werden serverseitig gespeichert', () {
      expect(setupSrc.contains("'favorite_song': song"), isTrue);
      expect(setupSrc.contains("'favorite_band': band"), isTrue);
    });

    test('Musik wird auch beim Abschluss gesichert', () {
      // Wer nicht auf "Weiter" tippt und ueber den Security-Nudge
      // abschliesst, darf den Geschmack nicht verlieren.
      expect(setupSrc.contains('await _saveMusicTaste();'), isTrue);
    });
  });
}