"""Prueft die veroeffentlichten Webseiten auf Bandbreite und Verhalten.

Begruendung
-----------
Am 28.10.2026 kam die Meldung: "Ich verliere credits von netlify,
wenn ich die Websiten besuche."

Gemessen wurde danach:

  * ein Besuch von /impressum kostet 1 Anfrage und 6.087 Byte
    (Brotli) - das sind 0,000006 Credits. Besuche koennen Credits
    also nicht auffressen.
  * Die Domain zeigt per CNAME direkt auf Netlify: jeder Bot-Hit
    ist ein Netlify-Request.
  * Netlify lieferte mit "cache-control: public, max-age=0,
    must-revalidate" aus - der Browser MUSS bei jedem Reload
    nachfragen.

Was dieser Pruefer absichert:

  1. Jede Seite bleibt klein (Obergrenze). Eine Seite, die
     unbeabsichtigt um das Zehnfache waechst, faellt hier auf.
  2. Jede Seite traegt eine Cache-Angabe mit max-age > 0 fuer
     BEIDE Schreibweisen des Pfads (mit und ohne .html) - sonst
     fragt der Browser bei jedem Besuch nach.
  3. robots.txt existiert und laesst die Pflichtseiten zu.
  4. Keine Seite laedt Ressourcen von fremden Servern (das waere
     Bandbreite bei Dritten UND ein Datenschutzproblem).
  5. Kein Skript (Projektregel "statische Seite").
  6. Der Umschalt-Knopf kommt auf jeder Seite genau einmal vor -
     zwei davon waeren zwei Knöpfe fuer denselben Schalter.

Aufruf:  python tool/check_web_payload.py
Exit 0 = alles in Ordnung, Exit 1 = mindestens ein Befund.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'passkey-assets'

# Die Seiten, die oeffentlich erreichbar sein muessen.
SEITEN = ['datenschutz.html', 'impressum.html', 'kinderschutz.html',
          'konto-loeschen.html']

# Obergrenze je Seite (unkomprimiert). Der groesste Wert liegt bei
# gut 60 KB; die Grenze ist doppelt so weit weg, damit ein
# sinnvoller Zuwachs nicht auffaellt, ein Unfall aber schon.
MAX_SEITE = 120 * 1024

# Obergrenze je Datei im Publish-Verzeichnis.
MAX_DATEI = 200 * 1024

# Die Pflichtseiten - genau die, die Play verlangt.
PFLICHT_PFADE = ['/datenschutz', '/impressum', '/kinderschutz',
                  '/konto-loeschen', '/daten-loeschen', '/eltern']

# Die englischen Fassungen (NUTZERWUNSCH 03.11.2026: jede Seite auf
# Deutsch und Englisch).
#
# Sie liegen unter /en/ und brauchen dieselben Cache-Angaben - sonst
# fragt der Browser bei jedem Besuch nach. In robots.txt genuegt die
# Praefix-Regel "Allow: /en/", deshalb stehen die einzelnen Pfade hier
# nicht in der robots-Pruefung.
EN_PFLICHT_PFADE = ['/en/', '/en/datenschutz', '/en/impressum',
                     '/en/kinderschutz', '/en/konto-loeschen',
                     '/en/daten-loeschen', '/en/eltern',
                     '/en/eltern/einstellungen']

# Pfade, die NICHT gecacht werden duerfen (BEFUND 04.11.2026).
#
# Das Eltern-Portal bekommt den Berechtigungs-Token aus der URL. Eine
# Cache-Zeit wuerde die Seite zwischenspeichern und der Token
# landete im Netlify-Zugriffslog - und im Referer jedes internen
# Klicks. "no-store" ist hier die richtige Angabe.
KEIN_CACHE = {'/eltern/einstellungen', '/eltern/einstellungen.html',
              '/en/eltern/einstellungen', '/en/eltern/einstellungen.html'}

problems = []


def flag(text):
    problems.append(text)


def main() -> int:
    print('=' * 70)
    print('WEB-PAYLOAD UND VERHALTEN DER PUBLISH-SEITEN')
    print('=' * 70)

    if not ASSETS.is_dir():
        print('FEHLER: Publish-Verzeichnis fehlt: %s' % ASSETS)
        return 1

    # --- 1) Groessen ------------------------------------------------
    print('\n1) Groessen im Publish-Verzeichnis:')
    gesamt = 0
    for p in sorted(ASSETS.rglob('*')):
        if not p.is_file():
            continue
        groesse = p.stat().st_size
        gesamt += groesse
        rel = p.relative_to(ASSETS).as_posix()
        if groesse > MAX_DATEI:
            flag('%s: %d Byte - groesser als %d Byte' % (
                rel, groesse, MAX_DATEI))
        print('   %8d B  %s' % (groesse, rel))
    print('   %8d B  SUMME' % gesamt)

    # --- 2) Seiten pruefen -------------------------------------------
    print('\n2) Seiten:')
    for name in SEITEN:
        p = ASSETS / name
        if not p.exists():
            flag('%s fehlt' % name)
            continue
        html = p.read_text(encoding='utf-8')
        groesse = p.stat().st_size
        if groesse > MAX_SEITE:
            flag('%s: %d Byte - groesser als %d Byte' % (
                name, groesse, MAX_SEITE))

        # Kein Skript (Projektregel).
        if '<script' in html.lower():
            flag('%s: enthaelt ein <script>' % name)

        # Keine AUTOMATISCH geladenen Ressourcen von fremden Servern.
        #
        # Wichtig ist der Unterschied zu einem Link: ein <a href> wird
        # angeklickt - das kostet uns keine Bandbreite und ist ein
        # normaler Verweis (z. B. auf das Play-Entwicklerprofil im
        # Impressum). Automatisch geladen wird dagegen alles mit src=
        # sowie Stylesheets und url() im CSS - das waere Bandbreite
        # bei Dritten und ein Datenschutzproblem.
        for m in re.finditer(r'\ssrc\s*=\s*"(https?://[^"]+)"', html):
            flag('%s: laedt automatisch von draussen: %s' % (name, m.group(1)))
        for m in re.finditer(
                r'<link[^>]+href\s*=\s*"(https?://[^"]+)"', html, re.I):
            flag('%s: bindet ein fremdes Stylesheet ein: %s'
                 % (name, m.group(1)))
        for m in re.finditer(r'url\(\s*["\']?(https?://[^)"\']+)', html):
            flag('%s: laedt im CSS von draussen: %s' % (name, m.group(1)))
        for m in re.finditer(r'@import\s+["\'](https?://[^"\']+)', html):
            flag('%s: importiert von draussen: %s' % (name, m.group(1)))

        # Genau ein Umschalt-Knopf.
        anzahl = len(re.findall(r'id="modus-umschalter"', html))
        if anzahl != 1:
            flag('%s: %d Umschalter (erwartet: genau 1)' % (name, anzahl))

        # Die Seite traegt ihr Design selbst (CSS im Dokument).
        if 'Web-Design (tool/web_theme.py)' not in html:
            flag('%s: traegt das gemeinsame Design nicht' % name)

        print('   OK  %-22s %7d B' % (name, groesse))

        # Links nach draussen sind erlaubt (Klick, kein automatischer
        # Ladevorgang) - aber sie werden hier genannt, damit man sie
        # bewusst entschieden hat.
        fremde = []
        for m in re.finditer(r'<a[^>]+href\s*=\s*"(https?://[^"]+)"', html):
            url = m.group(1)
            if not re.match(r'https?://([a-z0-9-]+\.)*thestia\.de', url):
                fremde.append(url)
        if fremde:
            print('        Verweise nach draussen (Klick, kein Ladevorgang): '
                  + ', '.join(sorted(set(fremde))))

    # --- 2b) Landing-Seite und Suchmaschinen ---------------------------
    #
    # BEFUND (04.11.2026): In der Google-Suche stand als Beschreibung
    # von "Thestia" die Fehlermeldung des Sicherheitschecks. Ursache:
    # Die Landing-Seite hatte KEINE Meta-Beschreibung, also baute Google
    # den Snippet aus dem Seiteninhalt - und auf auth.thestia.de ist der
    # einzige Text im DOM genau diese Fehlermeldung.
    #
    # Zusaetzlich sperrte die robots.txt (Disallow: /, gedacht fuer die
    # CAPTCHA-Seite) auch thestia.de - die oeffentliche Seite war damit
    # gar nicht indexierbar. Beides wird hier geprueft.
    print('\n2b) Landing-Seite und Suchmaschinen:')
    LANDING = [('index.html', 'https://thestia.de/'),
               ('en/index.html', 'https://thestia.de/en/')]
    for name, canonical in LANDING:
        p = ASSETS / name
        if not p.exists():
            flag('%s fehlt' % name)
            continue
        html = p.read_text(encoding='utf-8')

        m = re.search(r'<meta\s+name="description"\s+content="([^"]*)"', html)
        if not m:
            flag('%s: keine meta description - Google baut die '
                 'Beschreibung dann aus dem Seiteninhalt (das war die '
                 'Fehlermeldung des Sicherheitschecks)' % name)
        elif len(m.group(1)) < 60:
            flag('%s: meta description ist zu kurz (%d Zeichen)'
                 % (name, len(m.group(1))))

        m = re.search(r'<link\s+rel="canonical"\s+href="([^"]*)"', html)
        if not m:
            flag('%s: kein canonical - die Kopie auf auth.thestia.de '
                 'wuerde mitindexiert' % name)
        elif m.group(1) != canonical:
            flag('%s: canonical ist %s, erwartet %s'
                 % (name, m.group(1), canonical))

        # Die Bilder, auf die die Seite zeigt, muessen existieren.
        fehlend = 0
        for rel in re.findall(r'src="(screenshots/[^"]+)"', html):
            if not (p.parent / rel).is_file():
                flag('%s: Bild %s fehlt (die Seite zeigte leere '
                     'Kaesten)' % (name, rel))
                fehlend += 1
        if fehlend == 0:
            print('   OK  %-22s Beschreibung, canonical und Bilder' % name)

    # Sitemap und die beiden robots-Dateien.
    if not (ASSETS / 'sitemap.xml').is_file():
        flag('sitemap.xml fehlt')
    else:
        print('   OK  sitemap.xml')
    if not (ASSETS / 'robots-auth.txt').is_file():
        flag('robots-auth.txt fehlt - der Auth-Host braucht eine eigene '
             'robots.txt, sonst sperrt die normale Datei auch thestia.de')
    else:
        print('   OK  robots-auth.txt (eigene Sperre fuer den Auth-Host)')

    # Die Netlify-Regel, die dem Auth-Host die eigene robots.txt gibt.
    toml = (ASSETS / 'netlify.toml')
    if not toml.is_file() or 'auth.thestia.de/robots.txt' not in \
            toml.read_text(encoding='utf-8'):
        flag('netlify.toml: der Host-Rewrite auf robots-auth.txt fehlt - '
             'ohne ihn gilt die normale robots.txt auch fuer '
             'auth.thestia.de')
    else:
        print('   OK  netlify.toml (Host-Rewrite fuer robots.txt)')

    # --- 3) Cache-Angaben --------------------------------------------
    print('\n3) Cache-Angaben (_headers):')
    headers_pfad = ASSETS / '_headers'
    if not headers_pfad.exists():
        flag('_headers fehlt - ohne die Datei fragt der Browser bei '
             'jedem Besuch nach')
    else:
        inhalt = headers_pfad.read_text(encoding='utf-8')
        # Pfad -> Cache-Zeile
        regeln = {}
        aktueller = None
        for zeile in inhalt.split('\n'):
            if not zeile.strip() or zeile.strip().startswith('#'):
                continue
            if not (zeile.startswith(' ') or zeile.startswith('\t')):
                aktueller = zeile.strip()
                regeln.setdefault(aktueller, [])
                continue
            if aktueller and ':' in zeile:
                name, wert = zeile.split(':', 1)
                regeln[aktueller].append((name.strip().lower(),
                                          wert.strip()))

        for pfad in PFLICHT_PFADE + EN_PFLICHT_PFADE:
            varianten = [pfad, pfad + '.html']
            # Die Startseite der englischen Fassung ist /en/index.html -
            # die Datei /en/.html gibt es nicht.
            if pfad.endswith('/'):
                varianten = [pfad, pfad + 'index.html']
            for variante in varianten:
                eintraege = regeln.get(variante)
                if not eintraege:
                    flag('_headers: kein Block fuer %s' % variante)
                    continue
                cache = [w for (n, w) in eintraege if n == 'cache-control']
                if not cache:
                    flag('_headers: %s ohne Cache-Control' % variante)
                    continue
                # BEFUND 04.11.2026: Das Eltern-Portal ist die EINZIGE
                # Ausnahme. Dort steht der Berechtigungs-Token in der
                # URL (?token=...). Eine Cache-Zeit wuerde die Seite
                # mit dem Token in der Cache-Adresse zwischenspeichern -
                # und der Token landet im Netlify-Zugriffslog. Deshalb
                # "no-store" statt max-age.
                #
                # Der Inhalt der Seite ist fuer alle Nutzer identisch
                # (der Token wird nur clientseitig gelesen) - es geht
                # nicht um die Inhalte, sondern um das Cache-LOG.
                if variante in KEIN_CACHE:
                    if 'no-store' not in cache[0]:
                        flag('_headers: %s muss "no-store" haben - dort '
                             'steht der Berechtigungs-Token in der URL'
                             % variante)
                    continue
                max_age = re.search(r'max-age=(\d+)', cache[0])
                if not max_age or int(max_age.group(1)) == 0:
                    flag('_headers: %s hat max-age=0 - der Browser '
                         'fragt bei jedem Besuch nach' % variante)
        # Doppelte Pfade sind mehrdeutig.
        doppelt = [p for p in regeln if
                   len(re.findall(r'(?m)^%s\s*$' % re.escape(p),
                                  inhalt)) > 1]
        for p in doppelt:
            flag('_headers: %s steht mehrfach da' % p)
        print('   %d Pfade mit Regeln' % len(regeln))

        # BEFUND 04.11.2026: Auf KEINER Seite waren Sicherheits-Header
        # gesetzt. Live gemessen fehlten X-Frame-Options,
        # X-Content-Type-Options, Referrer-Policy, Permissions-Policy
        # und ein CSP-HEADER.
        #
        # Zwei Angriffsszenarien, die dadurch moeglich waren:
        #   * Clickjacking der CAPTCHA-Seite (auth.thestia.de liess
        #     sich in jedem iframe einbetten).
        #   * Clickjacking des Eltern-Portals: /eltern/einstellungen
        #     enthaelt "Freigabe bestaetigen" und "Freigabe
        #     widerrufen" - geframt und ueberlagert kann ein
        #     Angreifer einen Elternteil dazu bringen, die elterliche
        #     Freigabe zu bestaetigen oder zu widerrufen.
        #
        # Der "/*"-Block in _headers gilt fuer jede Datei; Netlify
        # wendet alle passenden Bloecke an.
        sicherheits_header = [
            'X-Content-Type-Options',
            'Referrer-Policy',
            'X-Frame-Options',
            'Permissions-Policy',
            'Strict-Transport-Security',
            'Content-Security-Policy',
        ]
        alle_header = ' '.join(
            '%s %s' % (n, w) for zeilen_ in regeln.values()
            for (n, w) in zeilen_).lower()
        for h in sicherheits_header:
            if h.lower() not in alle_header:
                flag('_headers: %s fehlt (global auf "/*" setzen) - ohne '
                     'den Header ist die Seite u.a. frambar' % h)
        # frame-ancestors kann nur im HEADER stehen, nicht in einer
        # meta-CSP (per Spezifikation dort nicht erlaubt).
        if 'frame-ancestors' not in alle_header:
            flag('_headers: Content-Security-Policy ohne frame-ancestors '
                 '- die Seiten sind sonst in fremde iframes einbettbar')

    # --- 4) robots.txt -----------------------------------------------
    print('\n4) robots.txt:')
    robots_pfad = ASSETS / 'robots.txt'
    if not robots_pfad.exists():
        flag('robots.txt fehlt - automatisierte Zugriffe laufen ueber '
             'jeden Pfad, auch ueber die CAPTCHA-Seite')
    else:
        inhalt = robots_pfad.read_text(encoding='utf-8')
        # "Allow: /" erlaubt alles - dann braucht es die einzelnen
        # Allow-Zeilen nicht (das ist der Stand seit 04.11.2026: die
        # oeffentliche Seite soll indexierbar sein, und die CAPTCHA-
        # Sperre liegt jetzt in robots-auth.txt fuer den Auth-Host).
        alles_erlaubt = re.search(r'(?m)^Allow:\s*/\s*$', inhalt) is not None
        for pfad in PFLICHT_PFADE:
            if alles_erlaubt:
                continue
            if ('Allow: %s' % pfad) not in inhalt:
                flag('robots.txt: %s ist nicht erlaubt' % pfad)
        print('   vorhanden, %d Zeichen%s'
              % (len(inhalt), ' (alles erlaubt)' if alles_erlaubt else ''))

    # Die Sperre fuer den Auth-Host: dort muss die CAPTCHA-Seite
    # weiterhin ausgeschlossen bleiben.
    auth_robots = ASSETS / 'robots-auth.txt'
    if auth_robots.is_file():
        inhalt = auth_robots.read_text(encoding='utf-8')
        if not re.search(r'(?m)^Disallow:\s*/\s*$', inhalt):
            flag('robots-auth.txt: sperrt nichts - der Sicherheitscheck '
                 'waere wieder crawlbar (Netlify-Credits, Turnstile)')
        else:
            print('   robots-auth.txt sperrt den Sicherheitscheck')

    # --- Ergebnis ----------------------------------------------------
    print()
    if problems:
        print('FEHLER:')
        for p in problems:
            print('  X %s' % p)
        return 1
    print('OK: Webseiten klein, gecacht, ohne fremde Ressourcen.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
