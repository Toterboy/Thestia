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

WAS IN DER CI NICHT VORHANDEN IST (und deshalb kein Fehler ist):

Die Phone-Screenshots sind REGENERIERBARE BUILD-ARTEFAKTE und stehen
deshalb nicht im Repository (`.gitignore`:
`fastlane/metadata/android/*/images/phoneScreenshots/`). In einem
frischen Checkout - also in der CI - fehlen sie. Das ist kein Mangel,
sondern die Natur eines Artefakts.

Deshalb gilt:

  * Fehlen die Phone-Screenshots in BEIDEN Sprachen, ist das kein
    Befund. Der Ordner wird als "nicht erzeugt" gemeldet.
  * Fehlen sie in nur EINER Sprache, IST das ein Befund: dann ist eine
    Liste unvollstaendig und die andere nicht - genau der Zustand, der
    zur Korrektur fuehrt.
  * Die Tablet-Bilder und die Metadaten-Dateien sind versioniert und
    muessen immer da sein.

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

# Ordner, die versioniert sind -> ihr Fehlen ist immer ein Befund.
VERSIONIERT = [
    ('images/tabletScreenshots/7in', ERWARTET),
    ('images/tabletScreenshots/10in', ERWARTET),
]

# Ordner, die regenerierbare Artefakte sind -> in der CI nicht da.
ARTEFAKT = [
    ('images/phoneScreenshots', ERWARTET),
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

    # Welche Artefakt-Ordner gibt es ueberhaupt? Fehlt einer in ALLEN
    # Sprachen, ist das der normale CI-Zustand (nicht erzeugt).
    artefakt_vorhanden = {}
    for rel, _anzahl in ARTEFAKT:
        artefakt_vorhanden[rel] = [
            sprache for sprache in SPRACHEN
            if (FASTLANE / sprache / rel).is_dir()
        ]

    for sprache in SPRACHEN:
        basis = FASTLANE / sprache
        print('\n%s' % sprache)
        if not basis.is_dir():
            problems.append(f'{sprache}: der Ordner fehlt ganz')
            continue

        for rel, anzahl in VERSIONIERT:
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

        for rel, anzahl in ARTEFAKT:
            ordner = basis / rel
            if not ordner.is_dir():
                # Fehlt der Ordner in EINER Sprache, aber in der anderen
                # ist er da, ist das genau der zu korrigierende Fall.
                if len(artefakt_vorhanden.get(rel, [])) == 1:
                    problems.append(
                        f'{sprache}: {rel} fehlt, in '
                        f'{artefakt_vorhanden[rel][0]} ist es da - '
                        f'genau eine unvollstaendige Liste')
                    print('  X %-34s fehlt (in der anderen Sprache da)'
                          % rel)
                else:
                    print('  - %-34s nicht erzeugt (Artefakt, in der CI '
                          'nicht vorhanden)' % rel)
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
        for rel, _anzahl in VERSIONIERT + ARTEFAKT:
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
