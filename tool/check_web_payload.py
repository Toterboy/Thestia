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
                  '/konto-loeschen']

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

        for pfad in PFLICHT_PFADE:
            for variante in (pfad, pfad + '.html'):
                eintraege = regeln.get(variante)
                if not eintraege:
                    flag('_headers: kein Block fuer %s' % variante)
                    continue
                cache = [w for (n, w) in eintraege if n == 'cache-control']
                if not cache:
                    flag('_headers: %s ohne Cache-Control' % variante)
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

    # --- 4) robots.txt -----------------------------------------------
    print('\n4) robots.txt:')
    robots_pfad = ASSETS / 'robots.txt'
    if not robots_pfad.exists():
        flag('robots.txt fehlt - automatisierte Zugriffe laufen ueber '
             'jeden Pfad, auch ueber die CAPTCHA-Seite')
    else:
        inhalt = robots_pfad.read_text(encoding='utf-8')
        for pfad in PFLICHT_PFADE:
            if ('Allow: %s' % pfad) not in inhalt:
                flag('robots.txt: %s ist nicht erlaubt' % pfad)
        print('   vorhanden, %d Zeichen' % len(inhalt))

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
