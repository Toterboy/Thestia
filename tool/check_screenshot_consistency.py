"""Prueft, dass ALLE Store-Screenshots dieselbe Schriftgroesse nutzen.

v0.9.2: 03_entdecken lief mit textScale 0.64, 04_anpassen mit 0.72,
die uebrigen mit 1.0. Auf dem Play Store fiel der Unterschied sofort
auf - drei Screens in derselben Serie, drei Schriftgroessen. Der
Nutzer meldete es als "die Schrift soll ueberall gleich gross sein".

Die Pruefung liest die textScale-Angaben direkt aus dem Render-Harness
und schlaegt an, sobald ein Wert von 1.0 abweicht. Sie greift nur, wenn
die Screenshots tatsaechlich neu gerendert wurden - in CI sind sie
gitignoriert und nicht vorhanden, dann wird uebersprungen.

Aufruf:  python tool/check_screenshot_consistency.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HARNESS = ROOT / 'test' / 'screenshots' / 'store_v091_shots_test.dart'
SHOTS = ROOT / 'fastlane' / 'metadata' / 'android' / 'de-DE' / 'images' / \
    'phoneScreenshots'

EXPECTED = 1.0

problems = []


def main():
    print('=' * 68)
    print('SCREENSHOT-KONSISTENZ')
    print('=' * 68)

    if not HARNESS.exists():
        print('Render-Harness nicht vorhanden '
              f'({HARNESS.relative_to(ROOT)}) - uebersprungen.')
        return 0

    src = HARNESS.read_text(encoding='utf-8')

    # Jeder _shot()-Aufruf auswerten. Wichtig: der Argumentblock endet
    # bei der Klammer, die zum Aufruf gehoert - NICHT bei der naechsten
    # _shot(). Ein Aufruf kann einen after:-Callback enthalten, der
    # selbst Klammern mitbringt und einen Block wieder aufspaltet
    # (5_eisbrecher). Klammerzzaehlen ist deshalb Pflicht; die erste
    # Fassung suchte nur bis zum naechsten _shot( und hat deshalb
    # Werte vom Folgescreen dem falschen Screenshot zugeordnet.
    calls = list(re.finditer(r"_shot\(\s*'([^']+)'", src))
    print(f'{len(calls)} _shot()-Aufrufe gefunden\n')

    for m in calls:
        name = m.group(1)
        # Argumente beginnen nach _shot( ... 'name' ... und enden bei
        # der schliessenden Klammer auf Tiefenzustand 0.
        i = m.start()
        depth = 0
        j = i
        while j < len(src):
            ch = src[j]
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    break
            elif ch == "'":
                # Stringliteral ueberspringen (enthaelt Klammern)
                j += 1
                while j < len(src) and src[j] != "'":
                    j += 2 if src[j] == '\\' else 1
            j += 1
        block = src[i:j]

        scale = re.search(r'textScale:\s*([0-9.]+)', block)
        value = float(scale.group(1)) if scale else EXPECTED
        ok = abs(value - EXPECTED) < 1e-6
        mark = 'OK ' if ok else 'ABWEICHUNG'
        print(f'  {name:<22} textScale={value:<5} {mark}')
        if not ok:
            problems.append(
                f'{name}: textScale={value} statt {EXPECTED} - die '
                f'Schrift wirkt im Store kleiner als in den anderen '
                f'Screens')

    print()
    if problems:
        for p in problems:
            print(' X', p)
        print(f'\n{len(problems)} Befund(e).')
        return 1
    print('OK  alle Screens nutzen dieselbe Schriftgroesse.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
