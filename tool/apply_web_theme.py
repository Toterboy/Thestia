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

Geaenderte Seiten: kinderschutz.html, konto-loeschen.html, impressum.html.
Die Datenschutzerklaerung wird NICHT hier bearbeitet - sie entsteht aus
docs/DATENSCHUTZ.md ueber tool/make_privacy_policy.py, das dieselben
Regeln aus tool/web_theme.py zieht.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tool'))

from web_theme import apply_theme  # noqa: E402

ASSETS = ROOT / 'passkey-assets'

# index.html ist die Captcha-Seite der App. Sie wird NICHT umgestaltet:
# sie muss zum App-Hintergrund passen, sonst blitzt beim Aufruf ein
# heller Fleck auf.
SEITEN = ['kinderschutz.html', 'konto-loeschen.html', 'impressum.html']

# index.html: die Captcha-Seite. Sie hat ZWEI Ansichten (Sicherheitscheck
# fuer auth.thestia.de, Landing-Seite fuer die Wurzel-Domain) und bringt
# ihre eigene Kopfzeile mit. Deshalb bekommt sie nur das gemeinsame CSS,
# keine Kopfzeile und keine Inhalts-Huelle - die wuerde den
# Sicherheitscheck in eine Karte packen.
NUR_CSS = ['index.html']


def main() -> int:
    geaendert = 0
    for name in SEITEN:
        pfad = ASSETS / name
        if not pfad.exists():
            print(f'  {name}: fehlt - uebersprungen')
            continue
        vorher = pfad.read_text(encoding='utf-8')
        nachher = apply_theme(vorher)
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
        nachher = apply_theme(vorher, insert_chrome=False)
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
