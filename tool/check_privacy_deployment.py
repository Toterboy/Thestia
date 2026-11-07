# tool/check_privacy_deployment.py
"""
Prueft, ob der PUBLISH-ORDNER (passkey-assets/) mit dem live
ausgelieferten Stand uebereinstimmt - und vor allem: WELCHE Dateien
hochgeladen werden muessen.

WARUM ES DAS GIBT
-----------------
`passkey-assets/` wird auf Netlify per Drag-and-Drop hochgeladen, nicht
aus dem Repo deployed. Zwei Kopien, keine Kopplung - und das ist bereits
zweimal schiefgegangen:

  1) Die live ausgelieferte Datenschutzerklaerung war aelter als das
     Repo (Version 5 gegen Version 6). Die veroeffentlichte Fassung
     beschrieb eine App, die es nicht mehr gibt.
  2) Das Impressum stand wochenlang mit offenen Platzhaltern
     ("[ANBIETER]") online.

Zusaetzlich zur Pruefung: WELCHE Dateien abweichen. Vorher stand am
Ende nur "Netlify: passkey-assets/ neu hochladen" - das hiess: den
GANZEN Ordner. Das war bei jeder kleinen Aenderung Arbeit ohne Anlass.

HINWEIS (02.11.2026): Fuer diesen Ordner gibt es ZWEI Wege, und
die Dokumentation widerspricht sich (docs/PLAY-REGELN-CHECK.md sagt
"haengt am Repository", der Kommentar in .github/workflows/ci.yml
sagt "per Drag & Drop"). Die Praxis: ein Push aus dem Repository wird
uebernommen, der Deploy kann aber etliche Minuten dauern (Netlify
reiht Builds ein). Deshalb nennt dieser Check die Dateien einzeln -
damit klar ist, was zurueckbleibt, egal welcher Weg genutzt wird.

Die Werkzeuge, die den Ordner erzeugen (tool/make_web_screenshots.py,
tool/apply_web_theme.py), sind inzwischen WIEDERHOLBAR: ein zweiter
Durchlauf aendert nichts (geprueft von
tool/check_web_theme_idempotenz.py). Deshalb weicht der Ordner jetzt nur
dort von live ab, wo sich wirklich etwas geaendert hat - und genau diese
Dateien werden hier benannt.

    python tool/check_privacy_deployment.py

Exit-Code 1 bei Abweichung. Ohne Netz (offline) wird die Pruefung
uebersprungen, nicht als Fehler gewertet - ein Offline-Lauf soll den
Build nicht blockieren.

Die Live-Adresse ist ueber THESTIA_PRIVACY_URL (Datenschutz) und
THESTIA_SITE_URL (Basis) ueberschreibbar.
"""

import os
import re
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, 'passkey-assets')
LOCAL = os.path.join(ASSETS, 'datenschutz.html')
DEFAULT_URL = 'https://auth.thestia.de/datenschutz.html'
BASIS_DEFAULT = 'https://auth.thestia.de'

# Der oeffentliche Host. thestia.de und auth.thestia.de sind EIN
# Netlify-Projekt, aber mit unterschiedlichen robots.txt: der
# oeffentliche Host ist indexierbar, der Auth-Host gesperrt (dort
# liegt der Sicherheitscheck).
#
# WARUM (06.11.2026): Der Pruefer verglich robots.txt gegen den
# Auth-Host - und meldete dadurch IMMER eine Abweichung, obwohl alles
# stimmte. Die Datei gehoert gegen den Host geprueft, auf dem sie
# ausgeliefert wird.
OEFFENTLICH_DEFAULT = 'https://thestia.de'

# Datei -> Host, auf dem sie ausgeliefert wird. Alles andere liegt
# auf dem Auth-Host.
HOST_PRO_DATEI = {
    'robots.txt': 'oeffentlich',
    'robots-auth.txt': 'auth',
}

# Dateien, die Netlify NICHT ausliefert, sondern beim Deploy liest.
# Sie koennen nicht gegen live geprueft werden (404) - sie gehoeren
# aber trotzdem in jeden Upload, wenn sie sich geaendert haben.
KONFIGURATION = {'_headers', '_redirects', 'netlify.toml'}

# Woerter, die nur in einer Version vorkommen. Sie machen den Unterschied
# lesbar, statt nur "Hash weicht ab" zu sagen.
MARKERS = [
    ('Version 6 (v0.10.0)', 'neuer Stand: Ort/Stadt wird nicht erhoben'),
    ('Version 5 (v0.9.2)', 'alter Stand: beschreibt die v0.9.2-Standortlogik'),
    ('5-km-Raster', 'neuer Stand: Koordinaten werden auf ein 5-km-Raster gerundet'),
    ('5-km-Schritten', 'alter Stand: Entfernung in 5-km-Schritten'),
]

# Die Pflichtseiten mit eigenem Platzhalter-Risiko.
PFLICHTSEITEN = [
    ('impressum.html', 'Impressum (Par. 5 DDG)'),
    ('kinderschutz.html', 'Kinderschutz und Meldestelle'),
    ('konto-loeschen.html', 'Konto-Loesch-URL (Play-Pflichtfeld)'),
]


def norm(text: str) -> str:
    """Vereinheitlicht fuer den Vergleich.

    WICHTIG (01.11.2026): Die Script- und Style-Bloecke werden
    NICHT mehr weggeworfen. Vorher geschah das - und damit blieb jede
    Verhaltensaenderung im JavaScript unsichtbar: die Aenderung an
    index.html (der Turnstile-Token wird nicht mehr angezeigt) wurde
    als "nur Formatierung" eingestuft, obwohl sich die Seite sichtbar
    anders verhaelt.

    Weggeworfen werden nur die TAGS; der Inhalt bleibt, der
    Leerraum wird vereinheitlicht. Damit bleibt der Vergleich
    unempfindlich gegenueber Zeilenumbruechen - erkennt aber
    Aenderungen im Text, im CSS und im JavaScript.
    """
    # Die VERWEISE der Tags mitnehmen. Ein href ist eine echte
    # Aenderung, auch wenn der Linktext gleich bleibt - so ist der
    # Wechsel von auth.thestia.de auf thestia.de sichtbar geworden.
    verweise = re.findall(
        r'(?:href|src)\s*=\s*["\']([^"\']*)["\']', text, re.I)
    text = re.sub(r'<[^>]+>', ' ', text)
    text = re.sub(r'&[a-z]+;', ' ', text)
    return (re.sub(r'\s+', ' ', text).strip() + ' || ' +
            ' '.join(sorted(verweise)))


def hole(url: str):
    """Holt eine URL. Liefert (status, bytes)."""
    try:
        req = urllib.request.Request(
            url, headers={'User-Agent': 'thesia-privacy-check/1.0'})
        with urllib.request.urlopen(req, timeout=25) as res:
            return res.status, res.read()
    except urllib.error.HTTPError as e:
        return e.code, b''
    except Exception:
        return -1, b''


def veroeffentlichte_dateien():
    """Alle Dateien im Publish-Ordner, die tatsaechlich ausgeliefert werden."""
    ergebnis = []
    for wurzel, _dirs, dateien in os.walk(ASSETS):
        for name in sorted(dateien):
            pfad = os.path.join(wurzel, name)
            rel = os.path.relpath(pfad, ASSETS).replace('\\', '/')
            if name in KONFIGURATION:
                continue
            ergebnis.append((rel, pfad))
    return sorted(ergebnis)


# Verweise in den Seiten. Ein Link auf ../SECURITY.md sieht im
# Repository richtig aus - auf der Website fuehrt er ins Leere,
# weil die Datei nicht im Publish-Ordner liegt.
LINK_HTML = re.compile(r'(?:href|src)\s*=\s*["\']([^"\']+)["\']', re.I)
LINK_MD = re.compile(r'\]\(([^)]+)\)')


def tote_verweise(basis: str) -> list:
    """Relative Verweise, die weder im Ordner liegen noch live sind."""
    tote = []
    for pfad in sorted(os.listdir(ASSETS)):
        if not (pfad.endswith('.html') or pfad.endswith('.md')):
            continue
        voll = os.path.join(ASSETS, pfad)
        with open(voll, 'rb') as f:
            text = f.read().decode('utf-8', 'replace')
        ziele = (set(LINK_HTML.findall(text)) if pfad.endswith('.html')
                 else set(LINK_MD.findall(text)))
        for ziel in sorted(ziele):
            if ziel.startswith(('http://', 'https://', 'mailto:', '#',
                                'data:', 'javascript:', '/')):
                continue
            datei = ziel[3:] if ziel.startswith('../') else ziel
            if os.path.exists(os.path.join(ASSETS, datei)):
                continue
            code, _ = hole(f'{basis}/{datei}')
            if code != 200:
                tote.append(f'{pfad}: {ziel}')
    return tote


def main() -> int:
    url = os.environ.get('THESTIA_PRIVACY_URL', DEFAULT_URL)
    basis = os.environ.get('THESTIA_SITE_URL', BASIS_DEFAULT)
    # Der oeffentliche Host (fuer die indexierbare robots.txt).
    offen = os.environ.get('THESTIA_PUBLIC_URL', OEFFENTLICH_DEFAULT)

    if not os.path.exists(LOCAL):
        print(f'FEHLER: {LOCAL} existiert nicht.')
        return 1

    print('=' * 74)
    print('PUBLISH-ORDNER: Repo vs. live ausgeliefert')
    print('=' * 74)
    print(f'  lokal : {ASSETS}')
    print(f'  live  : {basis}')
    print()

    dateien = veroeffentlichte_dateien()
    if not dateien:
        print('FEHLER: der Publish-Ordner ist leer.')
        return 1

    hochzuladen = []
    gleich = []
    nur_formatierung = []
    nicht_live = []
    nicht_erreichbar = []

    print(f'{"Datei":<34} {"Repo":>9} {"live":>9}  Status')
    print('-' * 74)

    for rel, pfad in dateien:
        with open(pfad, 'rb') as f:
            lokal = f.read()
        # Je Datei der Host, auf dem sie ausgeliefert wird: der
        # oeffentliche Host traegt die indexierbare robots.txt, der
        # Auth-Host die sperrende (robots-auth.txt). Beides gegen
        # denselben Host zu pruefen ergaebe IMMER eine Abweichung
        # (BEFUND 06.11.2026).
        if HOST_PRO_DATEI.get(rel) == 'oeffentlich':
            ziel_basis = offen
        else:
            ziel_basis = basis
        code, live = hole(f'{ziel_basis}/{rel}')

        if code == -1:
            nicht_erreichbar.append(rel)
            print(f'{rel:<34} {len(lokal):>9} {"-":>9}  live nicht erreichbar')
            continue
        if code == 404:
            nicht_live.append(rel)
            print(f'{rel:<34} {len(lokal):>9} {"-":>9}  nicht live (404)')
            continue
        if code != 200:
            nicht_erreichbar.append(rel)
            print(f'{rel:<34} {len(lokal):>9} {"-":>9}  HTTP {code}')
            continue

        if lokal == live:
            gleich.append(rel)
            print(f'{rel:<34} {len(lokal):>9} {len(live):>9}  identisch')
            continue

        # Textseiten: nur Formatierung (Zeilenumbrueche) oder Inhalt?
        if rel.endswith(('.html', '.txt', '.md', '.json')):
            n_lokal = norm(lokal.decode('utf-8', 'replace'))
            n_live = norm(live.decode('utf-8', 'replace'))
            if n_lokal == n_live:
                nur_formatierung.append(rel)
                print(f'{rel:<34} {len(lokal):>9} {len(live):>9}  '
                      f'nur Formatierung (Inhalt gleich)')
                continue

        hochzuladen.append(rel)
        print(f'{rel:<34} {len(lokal):>9} {len(live):>9}  ABWEICHUNG')

    # ------------------------------------------------------------------
    # Die Datenschutzerklaerung im Detail: welche Woerter fehlen live?
    # ------------------------------------------------------------------
    print()
    print('=' * 74)
    print('DATENSCHUTZERKLAERUNG: was unterscheidet sich im Text?')
    print('=' * 74)
    with open(LOCAL, 'rb') as f:
        lokal_text = f.read().decode('utf-8', 'replace')
    code, live_bytes = hole(url)
    live_text = live_bytes.decode('utf-8', 'replace') if code == 200 else ''
    nl, nv = norm(lokal_text), norm(live_text)
    if not live_text:
        print('  live nicht erreichbar - Detail nicht vergleichbar.')
    elif nl == nv:
        print('  OK  live und Repo sind inhaltlich identisch.')
    else:
        for marker, bedeutung in MARKERS:
            in_lokal = marker in nl
            in_live = marker in nv
            if in_lokal != in_live:
                ort = 'live' if in_live else 'Repo'
                print(f'  - {marker!r}: nur im {ort} ({bedeutung})')

    # ------------------------------------------------------------------
    # Platzhalter: im Repo (darf nicht hochgeladen werden) und live
    # ------------------------------------------------------------------
    print()
    print('=' * 74)
    print('PLATZHALTER')
    print('=' * 74)
    fehler = 0

    print()
    print('1) Im Repo (darf nicht hochgeladen werden):')
    for datei, _ in PFLICHTSEITEN:
        pfad = os.path.join(ASSETS, datei)
        if not os.path.exists(pfad):
            continue
        with open(pfad, 'rb') as f:
            inhalt = f.read().decode('utf-8', 'replace')
        treffer = sorted(set(re.findall(r'\[[A-Z]{3,}\]', inhalt)))
        if treffer:
            print(f'   FEHLT {datei}: {", ".join(treffer)}')
            fehler += 1
        else:
            print(f'   OK    {datei}')

    print()
    print('2) Live:')
    for datei, was in PFLICHTSEITEN:
        code, inhalt_bytes = hole(f'{basis}/{datei}')
        if code != 200:
            print(f'   FEHLT {was}: nicht erreichbar (HTTP {code})')
            fehler += 1
            continue
        inhalt = inhalt_bytes.decode('utf-8', 'replace')
        treffer = sorted(set(re.findall(r'\[[A-Z]{3,}\]', inhalt)))
        if treffer:
            print(f'   FEHLT {was}: PLATZHALTER LIVE: {", ".join(treffer)}')
            fehler += 1
            continue
        pfad = os.path.join(ASSETS, datei)
        if os.path.exists(pfad):
            with open(pfad, 'rb') as f:
                lokal_inhalt = f.read().decode('utf-8', 'replace')
            if norm(lokal_inhalt) != norm(inhalt):
                print(f'   FEHLT {was}: live weicht vom Repo ab')
                fehler += 1
                continue
        print(f'   OK    {was}')

    # ------------------------------------------------------------------
    # Tote Verweise: sie sehen im Repository richtig aus und fuehren
    # auf der Website ins Leere.
    # ------------------------------------------------------------------
    print()
    print('=' * 74)
    print('VERWEISE')
    print('=' * 74)
    tote = tote_verweise(basis)
    if tote:
        print(f'   FEHLT {len(tote)} Verweis(e) zeigt ins Leere:')
        for x in tote:
            print(f'     X {x}')
        fehler += len(tote)
    else:
        print('   OK    alle relativen Verweise zeigen auf existierende Seiten.')

    # ------------------------------------------------------------------
    # Die Antwort auf die eigentliche Frage: was muss hochgeladen werden?
    # ------------------------------------------------------------------
    print()
    print('=' * 74)
    print('ZU UPLOADEN')
    print('=' * 74)

    if nicht_erreichbar:
        print()
        print('Nicht geprueft (live nicht erreichbar):')
        for d in nicht_erreichbar:
            print('   ', d)

    if hochzuladen:
        print()
        print(f'{len(hochzuladen)} Datei(en) weichen vom live-Stand ab -')
        print('DIE MUESSEN hochgeladen werden:')
        for d in hochzuladen:
            print('   ', d)
    else:
        print()
        print('Keine Datei weicht inhaltlich vom live-Stand ab.')

    if nur_formatierung:
        print()
        print(f'{len(nur_formatierung)} Datei(en) sind inhaltlich gleich,')
        print('aber nicht byte-identisch (nur Zeilenumbrueche). Die Seite')
        print('sieht live genauso aus - ein Upload ist also NICHT noetig.')
        print('Wer sie einmal hochlaedt, hat danach einen sauberen Zustand:')
        for d in nur_formatierung:
            print('   ', d)

    if nicht_live:
        print()
        print('Im Repo, aber nicht live (404) - beim Upload mitnehmen,')
        print('damit sie online sind:')
        for d in nicht_live:
            print('   ', d)

    print()
    print('Konfigurationsdateien (Netlify liest sie beim Deploy, sie')
    print('werden nicht ausgeliefert):')
    for name in sorted(KONFIGURATION):
        if os.path.exists(os.path.join(ASSETS, name)):
            print('   ', name)

    if hochzuladen or nur_formatierung or nicht_live or fehler:
        print()
        print('Netlify - die Datei(en) unten sind noch nicht live.')
        print('  Weg 1: der Deploy aus dem Repository zieht nach. Er kann')
        print('         etliche Minuten dauern (Netlify reiht Builds ein).')
        print('  Weg 2: Site -> Deploys -> Add new deploy -> Deploy')
        print('         manually und den Inhalt von passkey-assets/')
        print('         hochziehen (den ORDNER, nicht die Einzeldateien).')
        print('  Pruefen danach mit: python tool/check_privacy_deployment.py')
        return 1

    print()
    print('OK  der Publish-Ordner ist live identisch. Es muss nichts')
    print('hochgeladen werden.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
