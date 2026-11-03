#!/usr/bin/env python3
"""Erzeugt die Tablet-Screenshots fuer den Play Store - als KACHELN.

WARUM (03.11.2026): "Bei beiden Tablet Versionen soll es wieder in
Kacheln sein wie auch beim Smartphone. Ausserdem ist beim 10" alles zu
weit links im Bild."

ZWEI BEFUNDE:

1. Die Tablet-Saetze waren裁 cuts aus den Phone-Bildern. Ein Beschnitt
   ist keine Komposition: beim 10-Zoll-Bild (Querformat) liegt der
   Kachel-Block LINKS und der Text RECHTS - der Beschnitt auf 1920x1200
   hat genau den Text abgeschnitten. Deshalb stand "alles zu weit
   links".

2. Das Richtige ist, dieselbe Komposition in der Groesse zu erzeugen, in
   der sie gebraucht wird. Das Compositor-Skript kann das jetzt:
   compose_card_wqhd() hat die Groesse als Parameter bekommen.

DIE GROESSEN (Play-Vorgaben):

  7 Zoll:  1080x1920 Hochformat - das ist exakt die Kachel-Variante
           des Smartphones (9x16-kacheln). Sie wird 1:1 uebernommen.
  10 Zoll: 1920x1200 Querformat - neu komponiert, mit dem Kachel-Block
           links und dem Text rechts (wie das Smartphone im Querformat),
           aber in der richtigen Groesse und mittig.

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

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# Das Compositor-Skript bringt die Texte, die Schriften und die
# Kompositions-Helfer mit. Der Import laedt es nur - die main() laeuft
# nicht (sie ist ueber __name__ geschuetzt).
import make_store_screenshots as comp  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARKETING = ROOT / 'releases' / 'testapk' / 'screenshots' / 'marketing'
QUELLE_7 = MARKETING / '9x16-kacheln'
QUELLE_SHOT = ROOT / 'test' / 'screenshots' / 'store_v091' / 'phone'
OUT_7 = MARKETING / 'tablet7'
OUT_10 = MARKETING / 'tablet10'
FASTLANE = ROOT / 'fastlane' / 'metadata' / 'android'
SPRACHEN = ['de-DE', 'en-US']

GROSSE_7 = (1080, 1920)
GROSSE_10 = (1920, 1200)


def _zielordner(sprache: str, groesse: str) -> pathlib.Path:
    return (FASTLANE / sprache / 'images' / 'tabletScreenshots' / groesse)


def _speichere(bild: Image.Image, ziele: list) -> None:
    for ziel in ziele:
        ziel.parent.mkdir(parents=True, exist_ok=True)
        bild.save(ziel, format='PNG', optimize=True)


def main() -> int:
    if not QUELLE_7.exists():
        print('FEHLER: Die Kachel-Screenshots fehlen. Zuerst:\n'
              '  python tool/make_store_screenshots.py')
        return 1

    anzahl = 0

    # ------------------------------------------------------------------
    # 7 Zoll: die Kachel-Variante des Smartphones, 1:1 (1080x1920 ist
    # genau die Play-Vorgabe fuer das 7-Zoll-Tablet).
    # ------------------------------------------------------------------
    for quelle in sorted(QUELLE_7.glob('*.png')):
        with Image.open(quelle) as bild:
            if bild.size != GROSSE_7:
                bild = bild.resize(GROSSE_7, Image.LANCZOS)
            ziele = [OUT_7 / quelle.name]
            for sprache in SPRACHEN:
                ziele.append(_zielordner(sprache, '7in') / quelle.name)
            _speichere(bild, ziele)
        anzahl += 1
        print('  7 Zoll: %s' % quelle.name)

    # ------------------------------------------------------------------
    # 10 Zoll: neu komponiert in 1920x1200 (Kachel links, Text rechts).
    # ------------------------------------------------------------------
    for name, (headline, subline, badge) in comp.SHOTS.items():
        quelle = comp.SRC / ('%s.png' % name)
        if not quelle.exists():
            # Manche Kachel-Namen weichen vom Render-Namen ab.
            quelle = comp.SRC / ('%s.png' % comp.QUELLE.get(name, name))
        if not quelle.exists():
            print('  10 Zoll: %s - Quelle fehlt, uebersprungen' % name)
            continue

        shot = Image.open(quelle).convert('RGB')
        dunkel = _ist_dunkel(quelle)

        bild = comp.compose_card_wqhd(
            shot, headline, subline, badge, dark=dunkel,
            W=GROSSE_10[0], H=GROSSE_10[1],
        )
        ziele = [OUT_10 / ('%s.png' % name)]
        for sprache in SPRACHEN:
            ziele.append(_zielordner(sprache, '10in') / ('%s.png' % name))
        _speichere(bild, ziele)
        anzahl += 1
        print('  10 Zoll: %s (%s)' % (name, bild.size))

    print()
    print('%d Tablet-Screenshots geschrieben (7 Zoll: 1080x1920 Kacheln, '
          '10 Zoll: 1920x1200 neu komponiert).' % anzahl)
    return 0


def _ist_dunkel(quelle: pathlib.Path) -> bool:
    """Ist der Screen in der dunklen Variante gerendert?

    Der Export nennt die Variante im Dateinamen (z. B. '_dunkel').
    """
    return 'dunkel' in quelle.stem.lower()


if __name__ == '__main__':
    sys.exit(main())
