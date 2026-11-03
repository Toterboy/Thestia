#!/usr/bin/env python3
"""Erzeugt die Tablet-Screenshots fuer den Play Store.

WARUM (03.11.2026): "Mache zusaetzlich aus den Smartphone Screenshots in
einem extra Ordner fuer ein 7" Tablet und fuer ein 10" Tablet noch genau
die selben Screenshots."

Google Play verlangt fuer einen Store-Eintrag mit Tablet-Screenshots zwei
zusaetzliche Satz-Ordner:

  images/tabletScreenshots/7in/    7-Zoll-Tablet
  images/tabletScreenshots/10in/   10-Zoll-Tablet

Die Vorgaben des Play Console:

  7 Zoll:  1080x1920 (Hochformat) - auch 1200x1920 akzeptiert
  10 Zoll: 1920x1200 (Querformat) - auch 1200x1920 akzeptiert

DIE QUELLE: die bereits erzeugten Marketing-Screenshots. Der 7-Zoll-Satz
ist exakt die 9:16-Serie (1080x1920) - das ist dieselbe Aufloesung, die
Play fuer das 7-Zoll-Tablet verlangt, also ein 1:1-Kopieren ohne
Qualitaetsverlust. Der 10-Zoll-Satz entsteht aus der WQHD-Serie
(2560x1440) durch Beschnitt auf 1920x1200 (Querformat, wie gefordert).

Es werden KEINE neuen App-Screens gerendert: der Auftrag lautet
"genau die selben Screenshots". Das spart den kompletten Golden-Render-
Durchlauf und liefert genau das, was im Store landen soll.

Aufruf:
    python tool/make_tablet_screenshots.py

Ausgabe:
    releases/testapk/screenshots/marketing/tablet7/*.png   (1080x1920)
    releases/testapk/screenshots/marketing/tablet10/*.png  (1920x1200)
    fastlane/metadata/android/<sprache>/images/tabletScreenshots/{7in,10in}/*.png
"""
import pathlib
import shutil
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARKETING = ROOT / 'releases' / 'testapk' / 'screenshots' / 'marketing'
QUELLE_7 = MARKETING / '9x16'
QUELLE_10 = MARKETING / 'wqhd'
OUT_7 = MARKETING / 'tablet7'
OUT_10 = MARKETING / 'tablet10'

SPRACHEN = ['de-DE', 'en-US']
FASTLANE = ROOT / 'fastlane' / 'metadata' / 'android'

# Play: 7 Zoll Hochformat 1080x1920, 10 Zoll Querformat 1920x1200.
GROSSE_7 = (1080, 1920)
GROSSE_10 = (1920, 1200)


def _schreibe(bild: Image.Image, ziele: list[pathlib.Path]) -> int:
    anzahl = 0
    for ziel in ziele:
        ziel.parent.mkdir(parents=True, exist_ok=True)
        bild.save(ziel, format='PNG', optimize=True)
        anzahl += 1
    return anzahl


def main() -> int:
    if not QUELLE_7.exists() or not QUELLE_10.exists():
        print('FEHLER: Die Marketing-Screenshots fehlen. Zuerst:\n'
              '  python tool/make_store_screenshots.py')
        return 1

    anzahl = 0

    # 7 Zoll: die 9:16-Serie unveraendert (1080x1920 ist genau die
    # Vorgabe des Play Console fuer das 7-Zoll-Tablet).
    for quelle in sorted(QUELLE_7.glob('*.png')):
        with Image.open(quelle) as bild:
            if bild.size != GROSSE_7:
                # Sollte nicht vorkommen - die 9:16-Serie ist 1080x1920.
                bild = bild.resize(GROSSE_7, Image.LANCZOS)
            ziele = [OUT_7 / quelle.name]
            for sprache in SPRACHEN:
                ziele.append(
                    FASTLANE / sprache / 'images' / 'tabletScreenshots' /
                    '7in' / quelle.name)
            anzahl += _schreibe(bild, ziele)
            print('  7 Zoll: %s' % quelle.name)

    # 10 Zoll: die WQHD-Serie auf 1920x1200 beschneiden. Der Beschnitt
    # nimmt die Seiten weg (2560 -> 1920), nicht die Hoehe - das Bild
    # bleibt scharf.
    for quelle in sorted(QUELLE_10.glob('*.png')):
        with Image.open(quelle) as bild:
            ziel_breite, ziel_hoehe = GROSSE_10
            if bild.width / bild.height > ziel_breite / ziel_hoehe:
                # Zu breit: die Seiten beschneiden.
                neue_breite = int(bild.height * ziel_breite / ziel_hoehe)
                links = (bild.width - neue_breite) // 2
                bild = bild.crop((links, 0, links + neue_breite, bild.height))
            bild = bild.resize(GROSSE_10, Image.LANCZOS)
            ziele = [OUT_10 / quelle.name]
            for sprache in SPRACHEN:
                ziele.append(
                    FASTLANE / sprache / 'images' / 'tabletScreenshots' /
                    '10in' / quelle.name)
            anzahl += _schreibe(bild, ziele)
            print('  10 Zoll: %s' % quelle.name)

    print()
    print('%d Tablet-Screenshots geschrieben (7 Zoll: 1080x1920, '
          '10 Zoll: 1920x1200).' % anzahl)
    return 0


if __name__ == '__main__':
    sys.exit(main())
