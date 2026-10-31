import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Publish-Verzeichnis des Netlify-Projekts fuer thestia.de.
final Directory assets = Directory('${Directory.current.path}/passkey-assets');

/// Alle oeffentlich ausgelieferten Seiten.
///
/// index.html und bestaetigt.html sind eingeschlossen: sie tragen das
/// Design ebenfalls (nur ohne Kopfzeile und Inhalts-Huelle, weil sie
/// eigene Ansichten haben).
const List<String> seiten = [
  'index.html',
  'datenschutz.html',
  'dating-sicherheit.html',
  'impressum.html',
  'kinderschutz.html',
  'konto-loeschen.html',
  'bestaetigt.html',
];

/// Die Seiten, die als Pflichtseite im Play Console eingetragen sind.
///
/// Diese MUESSEN statisch sein: kein Skript, keine externen Requests.
const List<String> pflichtseiten = [
  'datenschutz.html',
  'impressum.html',
  'kinderschutz.html',
  'konto-loeschen.html',
];

void main() {
  group('Web-Design', () {
    test('Jede Seite traegt das gemeinsame Design genau einmal', () {
      for (final name in seiten) {
        final html = File('${assets.path}/$name').readAsStringSync();
        final anzahl = 'Web-Design (tool/web_theme.py)'.allMatches(html).length;
        expect(anzahl, 1,
            reason: '$name: das Design ist $anzahl-fach eingespielt. '
                'Ein zweites Mal bedeutet zwei Farbpaletten und zwei '
                'Umschalt-Knoepfe.');
      }
    });

    test('Jede Seite hat genau einen Umschalt-Knopf', () {
      for (final name in seiten) {
        final html = File('${assets.path}/$name').readAsStringSync();
        expect(RegExp(r'id="modus-umschalter"').allMatches(html).length, 1,
            reason: '$name: es muss genau EIN Umschalter sein. Zwei davon '
                'waeren zwei Schalter fuer denselben Zustand.');
      }
    });

    test('Die Seiten folgen der Systemeinstellung (Dark Mode)', () {
      // Der Wunsch: "Die Websites sollen ALLE erkennen, ob der User den
      // Darkmode oder Whitemode nutzt und entsprechend direkt in der
      // richtigen Variante angezeigt werden. Der Button soll dennoch
      // bleiben."
      //
      // Dafuer braucht es eine Media-Query fuer den Systemzustand - und
      // eine zweite fuer den Schalter, der umdreht.
      for (final name in seiten) {
        final html = File('${assets.path}/$name').readAsStringSync();
        expect(html, contains('prefers-color-scheme: dark'),
            reason: '$name: ohne die System-Abfrage startet die Seite '
                'immer hell, egal was der Browser eingestellt hat.');
        expect(html, contains(':root:has(#modus-umschalter:checked)'),
            reason: '$name: der Schalter muss die Palette umdrehen - '
                'sonst ist er tot.');
      }
    });

    test('Die Farbpalette ist fuer jeden der vier Zustaende definiert', () {
      // Vier Zustaende: System hell/dunkel x Schalter aus/an. Jeder
      // braucht seinen eigenen Satz Variablen - sonst fehlt in einem
      // Zustand eine Farbe und die Seite sieht halb umgefuehrt aus.
      final html =
          File('${assets.path}/index.html').readAsStringSync();
      for (final farbe in ['--bg', '--fg', '--muted', '--card', '--card-fg',
        '--line', '--accent']) {
        final anzahl = RegExp('$farbe\\s*:').allMatches(html).length;
        expect(anzahl, greaterThanOrEqualTo(4),
            reason: '$farbe ist nur $anzahl-fach definiert. Es werden '
                'vier Zustaende gebraucht: System hell/dunkel x '
                'Schalter aus/an.');
      }
    });

    test('Keine Seite laedt Ressourcen von fremden Servern', () {
      // Wichtig ist der Unterschied zu einem Link: ein <a href> wird
      // angeklickt - das kostet keine Bandbreite. Automatisch geladen
      // wird alles mit src= sowie fremde Stylesheets - das waere
      // Bandbreite bei Dritten und ein Datenschutzproblem.
      for (final name in seiten) {
        final html = File('${assets.path}/$name').readAsStringSync();
        // Nur die TAGS zaehlen - nicht beliebige Zeichenketten. Die
        // Captcha-Seite laedt Turnstile per Skript ("s.src = ..."); das
        // ist noetig und wird nicht automatisch geladen.
        expect(
          RegExp(r'''<img[^>]+src\s*=\s*["']https?://''')
              .hasMatch(html),
          isFalse,
          reason: '$name: laedt ein Bild automatisch von draussen.',
        );
        expect(
          RegExp(r'''<link[^>]+href\s*=\s*["']https?://''',
                  caseSensitive: false)
              .hasMatch(html),
          isFalse,
          reason: '$name: bindet ein fremdes Stylesheet ein.',
        );
        expect(
          RegExp(r'''<script[^>]+src\s*=\s*["']https?://''')
              .hasMatch(html),
          isFalse,
          reason: '$name: bindet ein fremdes Skript ein.',
        );
      }
    });

    test('Die Pflichtseiten sind statisch - kein Skript', () {
      for (final name in pflichtseiten) {
        final html = File('${assets.path}/$name').readAsStringSync();
        expect(html.contains('<script'), isFalse,
            reason: '$name: ein Skript waere ein Grund, die Seite nicht '
                'mehr ohne Weiteres als statische Datei zu halten.');
      }
    });

    test('Kein Bild verweist auf eine Datei, die es nicht gibt', () {
      // Ein toter Bildverweis faellt auf thestia.de sofort auf - und
      // faellt erst auf, wenn jemand die Seite oeffnet. Deshalb hier.
      final re = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["']''');
      for (final name in seiten) {
        final html = File('${assets.path}/$name').readAsStringSync();
        for (final m in re.allMatches(html)) {
          final url = m.group(1)!;
          if (url.startsWith('http')) continue;
          // Pfade mit einem fuehrenden Schraegstrich sind relativ zur
          // Wurzel des Publish-Verzeichnisses.
          final pfad = '${assets.path}${url.startsWith('/') ? url : '/$url'}';
          expect(File(pfad).existsSync(), isTrue,
              reason: '$name verweist auf "$url" - die Datei gibt es '
                  'nicht. Der Besucher sieht ein leeres Bild.');
        }
      }
    });
  });

  group('Die Screenshot-Galerie auf thestia.de', () {
    test('Die Startseite verweist auf das GitHub-Repository', () {
      final html = File('${assets.path}/index.html').readAsStringSync();
      expect(html, contains('https://github.com/Toterboy/Thestia'),
          reason: 'Das Repository muss auf der Startseite stehen - es '
              'ist der Quellcode der App und das Argument dafuer, dass '
              'sie Open Source ist.');
    });

    test('Jede Kachel hat ein Bild im Publish-Verzeichnis', () {
      final html = File('${assets.path}/index.html').readAsStringSync();
      final bilder = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["']''')
          .allMatches(html)
          .map((m) => m.group(1)!)
          .where((u) => u.startsWith('/screenshots/'))
          .toList();
      expect(bilder.length, greaterThanOrEqualTo(8),
          reason: 'Die Galerie soll alle acht Screenshots zeigen.');

      for (final url in bilder) {
        final pfad = '${assets.path}$url';
        expect(File(pfad).existsSync(), isTrue,
            reason: 'Bild fehlt: $url');
        // Die Obergrenze aus tool/check_web_payload.py (200 KB). Wer
        // das Publish-Verzeichnis hochlaedt, darf nicht an der
        // Groessengrenze scheitern.
        final kb = File(pfad).lengthSync() / 1024;
        expect(kb, lessThan(200),
            reason: '$url wiegt $kb KB - ueber der Grenze von 200 KB.');
      }
    });

    test('Jedes Bild hat einen Alternativtext', () {
      // Ohne alt-Text ist das Bild fuer einen Screenreader nichts. Der
      // Text sagt, was auf dem Bild zu sehen ist - nicht "Bild" oder
      // "Screenshot".
      final html = File('${assets.path}/index.html').readAsStringSync();
      final ohneAlt = RegExp(r'<img(?![^>]*\balt\s*=)[^>]*>');
      expect(ohneAlt.hasMatch(html), isFalse,
          reason: 'Ein Bild ohne alt-Text ist fuer Screenreader leer.');
    });

    test('Die Kacheln liegen in der Reihenfolge der Screens', () {
      // 01 Willkommen, 02 Aktuelles, 03 Chat, 04 Entdecken,
      // 05 Anpassen, 06 Hell/Dunkel, 07 Eisbrecher, 08 Datenschutz.
      final html = File('${assets.path}/index.html').readAsStringSync();
      final reihenfolge = RegExp(r'/screenshots/(\d\d)_')
          .allMatches(html)
          .map((m) => m.group(1)!)
          .toList();
      expect(reihenfolge,
          ['01', '02', '03', '04', '05', '06', '07', '08'],
          reason: 'Die Kacheln muessen in der Reihenfolge der Screens '
              'stehen - auf der Seite ist das die Reihenfolge, in der '
              'man die App kennenlernt.');
    });
  });

  group('Die veroeffentlichten Artefakte', () {
    test('Die Sitemap enthaelt kein Geheimnis', () {
      // docs/ADMIN-UUID.md enthaelt die Admin-UUID und darf nicht
      // veroeffentlicht werden. Das Publish-Verzeichnis wird per
      // Drag-and-Drop hochgeladen - dort darf sie nicht liegen.
      final verboten = ['46f3f558-b134-4d25-946b-4e052a8ab3b5'];
      for (final datei in assets.listSync(recursive: true).whereType<File>()) {
        if (!['.html', '.md', '.json', '.txt', '.toml'].contains(datei.path
            .split('.').last)) {
          continue;
        }
        final inhalt = datei.readAsStringSync();
        for (final geheimnis in verboten) {
          expect(inhalt.contains(geheimnis), isFalse,
              reason: '${datei.path} enthaelt ein Geheimnis.');
        }
      }
    });
  });

  group('Die Startseite (Landing)', () {
    String html() =>
        File('${assets.path}/index.html').readAsStringSync();

    test('Die Galerie-Ueberschrift hat keinen Trennstrich', () {
      // NUTZERWUNSCH (31.10.2026): "Bei thestia.de soll der Strich
      // zwischen dem oberen Bereich mit den Buttons (Im Play Store
      // etc.) und der Ueberschrift Ein Blick in die App weg."
      //
      // Der Strich kommt aus der h2-Regel des gemeinsamen Designs
      // (border-top). Auf den Textseiten trennt er die Abschnitte -
      // hier aber die Karte mit den Buttons von der Galerie, die
      // zusammengehoeren.
      final h = html();
      expect(h, contains('.galerie-titel'));
      // Die Regel muss border-top ausdruecklich abschalten.
      final regel = RegExp(r'\.galerie-titel\s*\{([^}]*)\}').firstMatch(h);
      expect(regel, isNotNull,
          reason: 'Die Galerie-Ueberschrift braucht ihre eigene Regel.');
      expect(regel!.group(1), contains('border-top: none'),
          reason: 'Die Galerie-Ueberschrift erbt sonst den Trennstrich '
              'der h2-Regel.');
    });

    test('Die unterste der fuenf Kacheln steht mittig', () {
      // NUTZERWUNSCH (31.10.2026): "Unten bei den 5 Kacheln soll die
      // untere mittig sein und nicht linksbuendig."
      //
      // Bei fuenf Kacheln und zwei Spalten bleibt eine Kachel allein
      // in der letzten Zeile. Sie soll dort mittig stehen.
      final h = html();
      expect(RegExp(r'class="held-link"').allMatches(h).length, 5,
          reason: 'Es sind fuenf Kacheln - die letzte steht allein.');
      expect(h, contains('grid-column: 1 / -1'),
          reason: 'Die letzte Kachel muss die ganze Zeile einnehmen, '
              'damit sie mittig stehen kann.');
      expect(h, contains('justify-self: center'),
          reason: 'Die letzte Kachel muss mittig stehen.');
    });
  });
}
