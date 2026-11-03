"""Prueft, dass BEIDE Store-Listen vollstaendig sind - und nicht dieselben.

BEFUND (03.11.2026): Die englische Liste war unvollstaendig. Sie
hatte keine Phone-Screenshots, und die Tablet-Bilder waren Kopien der
deutschen - die Skripte kopierten dieselben Dateien in beide Sprachen.
Wer die englische Liste oeffnete, sah ein englisches Feature-Graphic
ueber deutschen Screenshots mit deutschen Headlines.

Ein Bild, das in zwei Sprachen spricht, ist schlimmer als gar keins:
Es verspricht dem englischsprachigen Besucher etwas, das die App in
seiner Sprache nicht zeigt.

Geprueft wird je Sprache:

  1. Vollstaendigkeit: 8 Phone-Screenshots, 8 Tablet-Bilder (7 Zoll),
     8 Tablet-Bilder (10 Zoll), Icon und Feature-Graphic.
  2. Eigenstaendigkeit: kein Bild in en-US ist byte-gleich mit dem
     deutschen Gegenstueck. Sonst ist eine der beiden Listen eine
     Kopie - und die falsche.

Aufruf:  python tool/check_store_listing_languages.py
"""

import hashlib
import pathlib
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = pathlib.Path(__file__).resolve().parent.parent
FASTLANE = ROOT / 'fastlane' / 'metadata' / 'android'

SPRACHEN = ['de-DE', 'en-US']

# Die erwartete Zahl je Ordner. Acht Screens (siehe
# tool/make_store_screenshots.py, SHOTS).
ERWARTET = 8

ORDNER = [
    ('images/phoneScreenshots', ERWARTET),
    ('images/tabletScreenshots/7in', ERWARTET),
    ('images/tabletScreenshots/10in', ERWARTET),
]

DATEIEN = [
    'images/icon.png',
    'images/featureGraphic.png',
    'title.txt',
    'short_description.txt',
    'full_description.txt',
]


def sha256(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> int:
    print('=' * 68)
    print('STORE-LISTING: SPRACHEN')
    print('=' * 68)

    problems = []
    pro_sprache = {}

    for sprache in SPRACHEN:
        basis = FASTLANE / sprache
        print('\n%s' % sprache)
        if not basis.is_dir():
            problems.append(f'{sprache}: der Ordner fehlt ganz')
            continue

        for rel, anzahl in ORDNER:
            ordner = basis / rel
            if not ordner.is_dir():
                problems.append(f'{sprache}: {rel} fehlt')
                print('  X %-34s fehlt' % rel)
                continue
            pngs = sorted(ordner.glob('*.png'))
            if len(pngs) != anzahl:
                problems.append(
                    f'{sprache}: {rel} hat {len(pngs)} Bilder, '
                    f'erwartet {anzahl}')
            else:
                print('  OK %-34s %d Bilder' % (rel, len(pngs)))
            pro_sprache[(sprache, rel)] = {p.name: sha256(p) for p in pngs}

        for rel in DATEIEN:
            p = basis / rel
            if not p.is_file():
                problems.append(f'{sprache}: {rel} fehlt')
                print('  X %-34s fehlt' % rel)
            elif p.stat().st_size == 0:
                problems.append(f'{sprache}: {rel} ist leer')
                print('  X %-34s leer' % rel)
            else:
                print('  OK %-34s %d Bytes' % (rel, p.stat().st_size))

    # Eigenstaendigkeit: kein Bild der einen Sprache darf byte-gleich
    # mit dem der anderen sein.
    print()
    if len(SPRACHEN) == 2:
        a, b = SPRACHEN
        gleich = []
        for rel, _anzahl in ORDNER:
            ha = pro_sprache.get((a, rel), {})
            hb = pro_sprache.get((b, rel), {})
            for name, h in ha.items():
                if name in hb and hb[name] == h:
                    gleich.append(f'{rel}/{name}')
        if gleich:
            for g in gleich:
                problems.append(
                    f'{b}: {g} ist byte-gleich mit {a} - die englische '
                    f'Liste ist eine Kopie der deutschen')
            print('X %d Bild(er) in %s sind identisch mit %s'
                  % (len(gleich), b, a))
            for g in gleich[:8]:
                print('    %s' % g)
        else:
            print('OK  kein Bild in %s ist eine Kopie aus %s' % (b, a))

    print()
    if problems:
        for p in problems:
            print(' X', p)
        print()
        print('%d Befund(e).' % len(problems))
        return 1

    print('OK  beide Store-Listen sind vollstaendig und eigenstaendig.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
