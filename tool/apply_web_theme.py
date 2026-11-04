#!/usr/bin/env python3
"""Wendet das gemeinsame Web-Design auf alle Seiten in passkey-assets/ an.

NUTZERWUNSCH (27.10.2026): "Die Websites sollen einen Dark und Light Mode
als kleinen Button zum Umschalten besitzen" und "Alle Websites sollen ein
Abgerundetes Design bei Elementen wie Tabellen haben, um zum Design der
App zu passen."

Warum ein Skript und nicht vier Kopien: die vier Seiten teilen sich
dieselben Regeln. Von Hand gepflegt driftet die eine Seite irgendwann ab
- und die Seite mit dem Drift faellt genau dann auf, wenn niemand
hinsieht.

Das Skript ist WIEDERHOLBAR: apply_theme() erkennt an einem Marker, ob
eine Seite schon bearbeitet wurde, und tut sie sonst nur einmal an.

    python tool/apply_web_theme.py

Geaenderte Seiten: kinderschutz.html, konto-loeschen.html, impressum.html,
dating-sicherheit.html.
Die Datenschutzerklaerung wird NICHT hier bearbeitet - sie entsteht aus
docs/DATENSCHUTZ.md ueber tool/make_privacy_policy.py, das dieselben
Regeln aus tool/web_theme.py zieht.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tool'))

from web_theme import apply_theme, strip_theme  # noqa: E402

ASSETS = ROOT / 'passkey-assets'

# index.html ist die Captcha-Seite der App. Sie wird NICHT umgestaltet:
# sie muss zum App-Hintergrund passen, sonst blitzt beim Aufruf ein
# heller Fleck auf.
SEITEN = [
    'kinderschutz.html',
    'eltern.html',
    'eltern-einstellungen.html',
    'daten-loeschen.html',
    'konto-loeschen.html',
    'impressum.html',
    'dating-sicherheit.html',
]

# datenschutz.html und en/datenschutz.html werden GENERIERT
# (tool/make_privacy_policy.py) und bringen das Design schon mit -
# inklusive des Sprachknopfes, den der Generator selbst setzt. Sie
# duerfen hier NICHT laufen: strip_theme() wuerde die Kopfzeile
# entfernen und apply_theme() eine ohne Sprachknopf einsetzen.

# Die englischen Fassungen liegen unter en/ und tragen dieselben
# Dateinamen. "en/eltern/einstellungen.html" gehoert zu
# "eltern-einstellungen.html" - die Ordnerstruktur bildet die Adresse
# ab, damit "/en/eltern/einstellungen" und "/eltern/einstellungen"
# zueinander passen.
EN_SEITEN = [
    'en/impressum.html',
    'en/kinderschutz.html',
    'en/dating-sicherheit.html',
    'en/konto-loeschen.html',
    'en/daten-loeschen.html',
    'en/eltern.html',
    'en/eltern/einstellungen.html',
]

# Seite -> (deutsche Adresse, englische Adresse).
#
# Die Adressen ohne ".html" entstehen ueber die Rewrite-Regeln in
# _redirects. Sie stehen hier, damit der Sprachknopf nicht raten muss
# und weil beide Werkzeuge (Theme und _redirects) dieselbe Liste
# brauchen.
SEITEN_URL = {
    'index.html': ('/', '/en/'),
    'impressum.html': ('/impressum', '/en/impressum'),
    'kinderschutz.html': ('/kinderschutz', '/en/kinderschutz'),
    'dating-sicherheit.html': ('/dating-sicherheit', '/en/dating-sicherheit'),
    'konto-loeschen.html': ('/konto-loeschen', '/en/konto-loeschen'),
    'daten-loeschen.html': ('/daten-loeschen', '/en/daten-loeschen'),
    'datenschutz.html': ('/datenschutz', '/en/datenschutz'),
    'eltern.html': ('/eltern', '/en/eltern'),
    'eltern-einstellungen.html': (
        '/eltern/einstellungen', '/en/eltern/einstellungen'),
}


def sprachziel(rel: str) -> tuple[str, str]:
    """(Adresse der anderen Fassung, Kuerzel des Ziels) fuer eine Seite.

    [rel] ist der Pfad relativ zu passkey-assets/ - z. B.
    'impressum.html' oder 'en/impressum.html'.

    Fuer die englischen Seiten ist der Name die Datei OHNE den Ordner
    'en/' (z. B. 'en/eltern/einstellungen.html' -> 'eltern-einstellungen
    .html'), weil die Ordnerstruktur die Adresse abbildet.
    """
    if rel.startswith('en/'):
        rest = rel[3:]
        # 'en/eltern/einstellungen.html' gehoert zu 'eltern-einstellungen
        # .html' - der Pfad zwischen 'en/' und dem Dateinamen ist
        # genau die Adresse ohne '/en/'.
        basis = rest.replace('/', '-', 1) if '/' in rest else rest
        # 'eltern/einstellungen.html' -> 'eltern-einstellungen.html'
        if '/' in rest:
            teil = rest.split('/')
            basis = teil[0] + '-' + teil[-1]
        eintrag = SEITEN_URL.get(basis)
        if not eintrag:
            return '', ''
        return eintrag[0], 'DE'

    eintrag = SEITEN_URL.get(rel)
    if not eintrag:
        return '', ''
    return eintrag[1], 'EN'

# index.html: die Captcha-Seite. Sie hat ZWEI Ansichten (Sicherheitscheck
# fuer auth.thestia.de, Landing-Seite fuer die Wurzel-Domain) und bringt
# ihre eigene Kopfzeile mit. Deshalb bekommt sie nur das gemeinsame CSS,
# keine Kopfzeile und keine Inhalts-Huelle - die wuerde den
# Sicherheitscheck in eine Karte packen.
NUR_CSS = ['index.html', 'bestaetigt.html', 'en/index.html',
           'en/bestaetigt.html']


def main() -> int:
    # --force: Das Theme wird VORHER entfernt und neu eingespielt.
    #
    # Warum das noetig ist (31.10.2026): Das Design bekam eine neue
    # Regel - die Seite folgt jetzt der Systemeinstellung (Dark Mode)
    # und der Schalter dreht nur um. Wer das Design nachaendert,
    # schreibt die Aenderung in web_theme.py und spielt sie mit
    # --force auf alle Seiten ein.
    #
    # apply_theme() entfernt ein vorhandenes Theme zwar ohnehin zuerst -
    # der Schritt ist aber unsichtbar, wenn jemand die Seite
    # zwischendurch von Hand angefasst hat (zusaetzliches
    # Inline-CSS, eine eigene Kopfzeile). --force raeumt restlos auf:
    # jede Ausfuehrung ergibt dieselbe Seite.
    force = '--force' in sys.argv[1:]
    geaendert = 0
    for name in SEITEN + EN_SEITEN:
        pfad = ASSETS / name
        if not pfad.exists():
            print(f'  {name}: fehlt - uebersprungen')
            continue
        vorher = pfad.read_text(encoding='utf-8')
        quelle = strip_theme(vorher) if force else vorher
        ziel, sprache = sprachziel(name)
        nachher = apply_theme(quelle, sprach_ziel=ziel, sprache=sprache)
        if nachher == vorher:
            print(f'  {name}: bereits bearbeitet - unveraendert')
            continue
        pfad.write_text(nachher, encoding='utf-8', newline='\n')
        print(f'  {name}: Design angewendet')
        geaendert += 1
    for name in NUR_CSS:
        pfad = ASSETS / name
        if not pfad.exists():
            print(f'  {name}: fehlt - uebersprungen')
            continue
        vorher = pfad.read_text(encoding='utf-8')
        quelle = strip_theme(vorher, remove_chrome=False) if force else vorher
        nachher = apply_theme(quelle, insert_chrome=False)
        if nachher == vorher:
            print(f'  {name}: bereits bearbeitet - unveraendert')
            continue
        pfad.write_text(nachher, encoding='utf-8', newline='\n')
        print(f'  {name}: Design angewendet (nur CSS)')
        geaendert += 1

    print()
    print(f'{geaendert} Seite(n) angepasst.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
