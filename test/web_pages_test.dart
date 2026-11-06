import 'dart:io';

import 'package:image/image.dart' as img;

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
        expect(
          anzahl,
          1,
          reason:
              '$name: das Design ist $anzahl-fach eingespielt. '
              'Ein zweites Mal bedeutet zwei Farbpaletten und zwei '
              'Umschalt-Knoepfe.',
        );
      }
    });

    test('Jede Seite hat genau einen Umschalt-Knopf', () {
      for (final name in seiten) {
        final html = File('${assets.path}/$name').readAsStringSync();
        expect(
          RegExp(r'id="modus-umschalter"').allMatches(html).length,
          1,
          reason:
              '$name: es muss genau EIN Umschalter sein. Zwei davon '
              'waeren zwei Schalter fuer denselben Zustand.',
        );
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
        expect(
          html,
          contains('prefers-color-scheme: dark'),
          reason:
              '$name: ohne die System-Abfrage startet die Seite '
              'immer hell, egal was der Browser eingestellt hat.',
        );
        expect(
          html,
          contains(':root:has(#modus-umschalter:checked)'),
          reason:
              '$name: der Schalter muss die Palette umdrehen - '
              'sonst ist er tot.',
        );
      }
    });

    test('Die Farbpalette ist fuer jeden der vier Zustaende definiert', () {
      // Vier Zustaende: System hell/dunkel x Schalter aus/an. Jeder
      // braucht seinen eigenen Satz Variablen - sonst fehlt in einem
      // Zustand eine Farbe und die Seite sieht halb umgefuehrt aus.
      final html = File('${assets.path}/index.html').readAsStringSync();
      for (final farbe in [
        '--bg',
        '--fg',
        '--muted',
        '--card',
        '--card-fg',
        '--line',
        '--accent',
      ]) {
        final anzahl = RegExp('$farbe\\s*:').allMatches(html).length;
        expect(
          anzahl,
          greaterThanOrEqualTo(4),
          reason:
              '$farbe ist nur $anzahl-fach definiert. Es werden '
              'vier Zustaende gebraucht: System hell/dunkel x '
              'Schalter aus/an.',
        );
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
          RegExp(r'''<img[^>]+src\s*=\s*["']https?://''').hasMatch(html),
          isFalse,
          reason: '$name: laedt ein Bild automatisch von draussen.',
        );
        expect(
          // WICHTIG (04.11.2026): Ein <link rel="canonical"> bindet KEIN
          // Stylesheet ein - der Browser laedt daraus nichts. Ohne diese
          // Ausnahme wird die eigene kanonische Adresse als "fremde
          // Ressource" gewertet.
          RegExp(
            r'''<link(?![^>]*rel\s*=\s*["']canonical["'])'''
            r'''[^>]+href\s*=\s*["']https?://''',
            caseSensitive: false,
          ).hasMatch(html),
          isFalse,
          reason: '$name: bindet ein fremdes Stylesheet ein.',
        );
        expect(
          RegExp(r'''<script[^>]+src\s*=\s*["']https?://''').hasMatch(html),
          isFalse,
          reason: '$name: bindet ein fremdes Skript ein.',
        );
      }
    });

    test('Die Pflichtseiten sind statisch - kein Skript', () {
      for (final name in pflichtseiten) {
        final html = File('${assets.path}/$name').readAsStringSync();
        expect(
          html.contains('<script'),
          isFalse,
          reason:
              '$name: ein Skript waere ein Grund, die Seite nicht '
              'mehr ohne Weiteres als statische Datei zu halten.',
        );
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
          expect(
            File(pfad).existsSync(),
            isTrue,
            reason:
                '$name verweist auf "$url" - die Datei gibt es '
                'nicht. Der Besucher sieht ein leeres Bild.',
          );
        }
      }
    });
  });

  group('Die Screenshot-Galerie auf thestia.de', () {
    test('Die Startseite verweist auf das GitHub-Repository', () {
      final html = File('${assets.path}/index.html').readAsStringSync();
      expect(
        html,
        contains('https://github.com/Toterboy/Thestia'),
        reason:
            'Das Repository muss auf der Startseite stehen - es '
            'ist der Quellcode der App und das Argument dafuer, dass '
            'sie Open Source ist.',
      );
    });

    test('Jede Kachel hat ein Bild im Publish-Verzeichnis', () {
      final html = File('${assets.path}/index.html').readAsStringSync();
      // Die Pfade sind RELATIV (04.11.2026): so zeigt /en/ die
      // englischen Bilder und / die deutschen. Absolute Pfade
      // (/screenshots/...) wuerden auf der englischen Seite die
      // deutschen Bilder zeigen.
      final bilder = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["']''')
          .allMatches(html)
          .map((m) => m.group(1)!)
          .where(
            (u) =>
                u.startsWith('screenshots/') || u.startsWith('/screenshots/'),
          )
          .toList();
      expect(
        bilder.length,
        greaterThanOrEqualTo(8),
        reason: 'Die Galerie soll alle acht Screenshots zeigen.',
      );

      for (final url in bilder) {
        // Relativ zum Ordner der HTML-Datei aufloesen.
        final pfad = url.startsWith('/')
            ? '${assets.path}$url'
            : '${assets.path}/$url';
        expect(File(pfad).existsSync(), isTrue, reason: 'Bild fehlt: $url');
        // Die Obergrenze aus tool/check_web_payload.py (200 KB). Wer
        // das Publish-Verzeichnis hochlaedt, darf nicht an der
        // Groessengrenze scheitern.
        final kb = File(pfad).lengthSync() / 1024;
        expect(
          kb,
          lessThan(200),
          reason: '$url wiegt $kb KB - ueber der Grenze von 200 KB.',
        );
      }
    });

    test('Jedes Bild hat einen Alternativtext', () {
      // Ohne alt-Text ist das Bild fuer einen Screenreader nichts. Der
      // Text sagt, was auf dem Bild zu sehen ist - nicht "Bild" oder
      // "Screenshot".
      final html = File('${assets.path}/index.html').readAsStringSync();
      final ohneAlt = RegExp(r'<img(?![^>]*\balt\s*=)[^>]*>');
      expect(
        ohneAlt.hasMatch(html),
        isFalse,
        reason: 'Ein Bild ohne alt-Text ist fuer Screenreader leer.',
      );
    });

    test('Die Kacheln liegen in der Reihenfolge der Screens', () {
      // 01 Willkommen, 02 Aktuelles, 03 Chat, 04 Entdecken,
      // 05 Anpassen, 06 Hell/Dunkel, 07 Eisbrecher, 08 Datenschutz.
      final html = File('${assets.path}/index.html').readAsStringSync();
      // Nur die <img>-Elemente: das og:image in den Meta-Angaben
      // nennt ebenfalls "screenshots/01_..." und wuerde die Liste
      // sonst um einen Eintrag verlaengern.
      final reihenfolge = RegExp(
        r'''<img[^>]+src\s*=\s*["'][^"']*screenshots/(\d\d)_''',
      ).allMatches(html).map((m) => m.group(1)!).toList();
      expect(
        reihenfolge,
        ['01', '02', '03', '04', '05', '06', '07', '08'],
        reason:
            'Die Kacheln muessen in der Reihenfolge der Screens '
            'stehen - auf der Seite ist das die Reihenfolge, in der '
            'man die App kennenlernt.',
      );
    });
  });

  group('Die Seiten fuer die Play-Anforderungen', () {
    // Google Play verlangt fuer "Daten loeschen" eine oeffentlich
    // erreichbare Seite, die drei Dinge erfuellt:
    //
    //   1. Sie bezieht sich auf die App oder den Entwicklernamen aus
    //      dem Store-Eintrag.
    //   2. Sie zeigt gut sichtbar die Schritte, mit denen Nutzer die
    //      Loeschung ihrer Daten (oder ihres Kontos) anfordern.
    //   3. Sie nennt die Art der zu loeschenden oder aufzubewahrenden
    //      Daten und eine etwaige zusaetzliche Aufbewahrungsdauer.
    //
    // Diese Tests halten fest, dass die Seite das weiterhin tut - sie
    // waere sonst nach der naechsten Textaenderung stillschweigend
    // unvollstaendig.
    String datenLoeschen() =>
        File('${assets.path}/daten-loeschen.html').readAsStringSync();
    String eltern() => File('${assets.path}/eltern.html').readAsStringSync();

    test('Die Loesch-Seite nennt die App und den Entwickler', () {
      final h = datenLoeschen();
      expect(
        h,
        contains('Thestia'),
        reason: 'Die Seite muss sich auf die App beziehen.',
      );
      expect(
        h,
        contains('Thoralf Illg'),
        reason:
            'Die Seite muss den Entwicklernamen aus dem '
            'Store-Eintrag nennen.',
      );
    });

    test(
      'Die Loesch-Seite zeigt die Schritte fuer die App UND den Browser',
      () {
        final h = datenLoeschen();
        expect(
          h,
          contains('Daten löschen'),
          reason: 'Der Eintrag in der App muss benannt sein.',
        );
        expect(
          h,
          contains('Datenschutz &amp; Account'),
          reason: 'Der Weg in der App muss konkret beschrieben sein.',
        );
        expect(
          h,
          contains('/konto-loeschen'),
          reason: 'Der Weg im Browser muss verlinkt sein.',
        );
        expect(
          h,
          contains('support@thestia.de'),
          reason: 'Der Weg per E-Mail muss benannt sein.',
        );
      },
    );

    test('Die Loesch-Seite nennt die geloeschten Datenarten', () {
      final h = datenLoeschen();
      for (final art in [
        'Profilfotos',
        'Standortdaten',
        'Profilangaben',
        'Likes',
        'Funken',
        'Nachrichten',
        'Geräte',
        'Stimmung',
        'Meldungen',
      ]) {
        expect(
          h,
          contains(art),
          reason: 'Die Datenart "$art" muss auf der Seite stehen.',
        );
      }
    });

    test('Die Loesch-Seite nennt die Aufbewahrungsdauern', () {
      final h = datenLoeschen();
      expect(
        h,
        contains('Aufbewahrung'),
        reason: 'Die Seite muss die Aufbewahrung thematisieren.',
      );
      for (final dauer in const [
        '24 Stunden',
        '30 Tage',
        '90 Tage',
        '180 Tage',
      ]) {
        expect(
          h,
          contains(dauer),
          reason: 'Die Aufbewahrungsdauer "$dauer" muss genannt werden.',
        );
      }
      expect(
        h,
        contains('unwiderruflich'),
        reason: 'Die Unwiderruflichkeit muss benannt werden.',
      );
    });

    test('Die Eltern-Seite nennt die Schritte, die Daten und die Rechte', () {
      final h = eltern();
      expect(h, contains('Thestia'));
      expect(h, contains('Thoralf Illg'));
      // Die Schritte fuer die Eltern.
      expect(h, contains('E-Mail'));
      expect(h, contains('bestätigen'));
      // Die Daten, die verarbeitet werden.
      expect(h, contains('PIN'));
      expect(h, contains('Aufbewahrung'));
      // Die Rechte des Kindes.
      expect(h, contains('18. Geburtstag'));
      expect(h, contains('widerrufen'));
    });

    test('Beide Seiten sind von der Startseite aus erreichbar', () {
      // "Bei thestia.de auffindbar" - die Landing-Seite verlinkt beide.
      final h = File('${assets.path}/index.html').readAsStringSync();
      expect(h, contains('href="/daten-loeschen"'));
      expect(h, contains('href="/eltern"'));
    });

    test('Die Unterseiten sind erreichbar (Rewrite-Regeln)', () {
      final redirects = File('${assets.path}/_redirects').readAsStringSync();
      expect(redirects, contains('/daten-loeschen'));
      expect(redirects, contains('/eltern/einstellungen'));
    });
  });

  group('Die Zweisprachigkeit (NUTZERWUNSCH 03.11.2026)', () {
    // "Jede der Websites soll auf Englisch und Deutsch verfuegbar sein.
    //  Standardmaessig auf Deutsch."
    //
    // Diese Tests halten fest, dass jede Seite einen Sprachknopf hat,
    // dass er auf die andere Fassung zeigt und dass die andere Fassung
    // auch wirklich existiert. Sonst koennte der Knopf ins Leere
    // zeigen - und niemand faellt es, bis ein Besucher darauf klickt.
    const seiten = [
      'impressum',
      'kinderschutz',
      'dating-sicherheit',
      'konto-loeschen',
      'daten-loeschen',
      'datenschutz',
      'eltern',
    ];

    String lese(String pfad) => File('${assets.path}/$pfad').readAsStringSync();

    test('Jede deutsche Seite hat einen Sprachknopf auf die englische', () {
      for (final s in seiten) {
        final h = lese('$s.html');
        expect(
          h,
          contains('class="sprach-knopf"'),
          reason: 'Die Seite $s braucht einen Sprachknopf.',
        );
        expect(
          h,
          contains('href="/en/$s"'),
          reason: 'Der Sprachknopf auf $s muss auf /en/$s zeigen.',
        );
        expect(
          h,
          contains('>EN</a>'),
          reason:
              'Der Knopf zeigt das ZIEL: auf der deutschen Seite '
              'steht "EN".',
        );
      }
    });

    test('Jede englische Seite hat einen Sprachknopf zurueck ins Deutsche', () {
      for (final s in seiten) {
        final h = lese('en/$s.html');
        expect(
          h,
          contains('class="sprach-knopf"'),
          reason: 'Die englische Seite $s braucht einen Sprachknopf.',
        );
        expect(
          h,
          contains('href="/$s"'),
          reason:
              'Der Sprachknopf auf en/$s muss zurueck auf /$s '
              'zeigen.',
        );
        expect(
          h,
          contains('>DE</a>'),
          reason:
              'Der Knopf zeigt das ZIEL: auf der englischen Seite '
              'steht "DE".',
        );
      }
    });

    test('Die englischen Fassungen existieren alle', () {
      for (final s in seiten) {
        expect(
          File('${assets.path}/en/$s.html').existsSync(),
          isTrue,
          reason: 'Die englische Fassung von $s fehlt.',
        );
      }
    });

    test('Die englischen Seiten sind auf Englisch (lang="en")', () {
      for (final s in seiten) {
        expect(
          lese('en/$s.html'),
          contains('<html lang="en">'),
          reason: 'Die englische Seite $s muss lang="en" setzen.',
        );
      }
      for (final s in seiten) {
        expect(
          lese('$s.html'),
          contains('<html lang="de">'),
          reason: 'Die deutsche Seite $s muss lang="de" setzen.',
        );
      }
    });

    test('Der Elternbereich liegt in beiden Sprachen unter /eltern', () {
      // /eltern ist die oeffentliche Seite, /eltern/einstellungen der
      // persoenliche Bereich des Elternteils (nur mit dem Token).
      expect(lese('eltern.html'), contains('/eltern/einstellungen'));
      expect(lese('en/eltern.html'), contains('/en/eltern/einstellungen'));
      expect(
        File('${assets.path}/en/eltern/einstellungen.html').existsSync(),
        isTrue,
      );
    });

    test('Die Startseite hat in beiden Sprachen einen Sprachknopf', () {
      expect(lese('index.html'), contains('href="/en/"'));
      expect(lese('en/index.html'), contains('href="/"'));
    });

    test('Die Rewrite-Regeln kennen die englischen Adressen', () {
      final r = lese('_redirects');
      for (final s in seiten) {
        expect(
          r,
          contains('/en/$s'),
          reason: 'Die Adresse /en/$s braucht eine Rewrite-Regel.',
        );
      }
      expect(r, contains('/en/eltern/einstellungen'));
    });

    test('Die Seiten folgen der Systemeinstellung fuer Hell/Dunkel', () {
      // Das Theme richtet sich nach prefers-color-scheme; der Schalter
      // dreht nur um. Ohne diese Regel waere die Seite IMMER hell - oder
      // immer dunkel, je nachdem, was der Rechner gerade eingestellt hat.
      for (final s in ['impressum', 'kinderschutz']) {
        expect(
          lese('$s.html'),
          contains('prefers-color-scheme'),
          reason: 'Die Seite $s muss der Systemeinstellung folgen.',
        );
      }
    });
  });

  group('Die veroeffentlichten Artefakte', () {
    test('Die Sitemap enthaelt kein Geheimnis', () {
      // docs/ADMIN-UUID.md enthaelt die Admin-UUID und darf nicht
      // veroeffentlicht werden. Das Publish-Verzeichnis wird per
      // Drag-and-Drop hochgeladen - dort darf sie nicht liegen.
      final verboten = ['46f3f558-b134-4d25-946b-4e052a8ab3b5'];
      for (final datei in assets.listSync(recursive: true).whereType<File>()) {
        if (![
          '.html',
          '.md',
          '.json',
          '.txt',
          '.toml',
        ].contains(datei.path.split('.').last)) {
          continue;
        }
        final inhalt = datei.readAsStringSync();
        for (final geheimnis in verboten) {
          expect(
            inhalt.contains(geheimnis),
            isFalse,
            reason: '${datei.path} enthaelt ein Geheimnis.',
          );
        }
      }
    });
  });

  group('Die Startseite (Landing)', () {
    String html() => File('${assets.path}/index.html').readAsStringSync();

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
      expect(
        regel,
        isNotNull,
        reason: 'Die Galerie-Ueberschrift braucht ihre eigene Regel.',
      );
      expect(
        regel!.group(1),
        contains('border-top: none'),
        reason:
            'Die Galerie-Ueberschrift erbt sonst den Trennstrich '
            'der h2-Regel.',
      );
    });

    test('Die unterste der sieben Kacheln steht mittig', () {
      // NUTZERWUNSCH (31.10.2026): "Unten bei den 5 Kacheln soll die
      // untere mittig sein und nicht linksbuendig."
      //
      // Seit dem 03.11.2026 sind es sieben Kacheln (neu: Daten loeschen
      // und Eltern & Jugendliche). Bei ungerader Kachelzahl und zwei
      // Spalten bleibt eine Kachel allein in der letzten Zeile. Sie
      // soll dort mittig stehen.
      final h = html();
      expect(
        RegExp(r'class="held-link"').allMatches(h).length,
        7,
        reason: 'Es sind sieben Kacheln - die letzte steht allein.',
      );
      expect(
        h,
        contains('grid-column: 1 / -1'),
        reason:
            'Die letzte Kachel muss die ganze Zeile einnehmen, '
            'damit sie mittig stehen kann.',
      );
      expect(
        h,
        contains('justify-self: center'),
        reason: 'Die letzte Kachel muss mittig stehen.',
      );
    });

    test('Die Galerie ist ein Flex-Container - die unteren Bilder '
        'stehen mittig', () {
      // NUTZERWUNSCH (31.10.2026): "Zudem sollen die unteren beiden
      // Bilder zentriert werden."
      //
      // Bei acht Bildern und drei Spalten bleiben zwei in der letzten
      // Reihe. Im GRID stehen die linksbuendig - jede Zeile wird
      // einzeln gefuellt. Mit Flex und `justify-content: center`
      // richtet Flex jede Zeile einzeln aus, und die letzte Reihe mit
      // zwei Bildern steht damit mittig.
      final h = html();
      final regel = RegExp(r'\.galerie-raster\s*\{([^}]*)\}').firstMatch(h);
      expect(
        regel,
        isNotNull,
        reason: 'Die Galerie braucht ihre eigene Regel.',
      );
      expect(
        regel!.group(1),
        contains('justify-content: center'),
        reason:
            'Ohne justify-content: center stehen die unteren '
            'beiden Bilder linksbuendig.',
      );
    });

    test('Die Galerie-Regeln stehen nur EINMAL im Dokument', () {
      // Die Galerie-Regeln standen einmal in index.html UND einmal im
      // Theme. Die Kopie in index.html stand VOR dem Theme und brachte
      // `display: grid` - das Theme (mit Flex) kam danach und war
      // wirkungslos. Die unteren Bilder standen deshalb linksbuendig.
      //
      // Regeln, die an mehreren Stellen stehen, driften auseinander.
      final h = html();
      expect(
        RegExp(r'\.galerie-raster\s*\{').allMatches(h).length,
        1,
        reason:
            'Die .galerie-raster-Regel steht mehrfach im Dokument - '
            'die spaeter gefundene gewinnt, die frueher gefundene '
            'ist wirkungslos.',
      );
    });
  });

  group('Die Galerie-Bilder', () {
    test('Sie zeigen die Kacheln, nicht den Geraete-Screen', () {
      // NUTZERWUNSCH (31.10.2026): "Es sollen nur die Screenshots
      // benutzt werden, die mit Kacheln sind, also keine, die eine
      // Statusleiste oder so haben."
      //
      // Geprueft an den Pixeln: In der Kacheln-Variante ist der
      // oberste Streifen reiner Markenverlauf. Beim Geraete-Screen
      // stuende dort die nachgeahmte Statusleiste (Uhrzeit, WLAN,
      // Akku) auf weissem Grund.
      final bilder = Directory('${assets.path}/screenshots')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList();
      expect(bilder.length, 8, reason: 'Es sind acht Galerie-Bilder.');

      for (final f in bilder) {
        final px = obersteZeilenSindWeiss(f);
        expect(
          px,
          lessThan(0.15),
          reason:
              '${f.path.split(Platform.pathSeparator).last}: Die '
              'obersten Zeilen sind zu ${(px * 100).toStringAsFixed(0)}% '
              'weiss - dort steht der Geraete-Screen mit Statusleiste, '
              'nicht die Kachel.',
        );
      }
    });
  });
}

/// Anteil der weissen Pixel in den obersten 60 Zeilen eines Bildes.
///
/// Der App-Screen ist weiss (255,255,255). Der Markenverlauf der
/// Kachel ist rosa bis violett. Steht oben eine nachgeahmte
/// Statusleiste, ist der Streifen weiss.
///
/// 60 Zeilen entsprechen bei der Kachel (540 x 960) gut dem Bereich,
/// in dem die Statusleiste stuende.
double obersteZeilenSindWeiss(File datei) {
  final bild = img.decodeJpg(datei.readAsBytesSync());
  if (bild == null) {
    throw StateError('${datei.path} konnte nicht gelesen werden.');
  }
  final zeilen = bild.height < 60 ? bild.height : 60;
  var weiss = 0;
  var gesamt = 0;
  for (var y = 0; y < zeilen; y++) {
    for (var x = 0; x < bild.width; x++) {
      final p = bild.getPixel(x, y);
      gesamt++;
      if (p.r > 235 && p.g > 235 && p.b > 235) weiss++;
    }
  }
  return gesamt == 0 ? 0 : weiss / gesamt;
}
