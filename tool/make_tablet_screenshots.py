#!/usr/bin/env python3
"""Erzeugt die Tablet-Screenshots fuer den Play Store - als KACHELN.

WARUM (03.11.2026): "Bei beiden Tablet Versionen soll es wieder in
Kacheln sein wie auch beim Smartphone. Ausserdem ist beim 10" alles zu
weit links im Bild."

ZWEI BEFUNDE:

1. Die Tablet-Saetze waren cuts aus den Phone-Bildern. Ein Beschnitt
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

SPRACHEN (03.11.2026): Bis hierher bekam die englische Liste die
DEUTSCHEN Tablet-Bilder - dieses Skript kopierte dieselben Dateien in
beide Sprachen. Jetzt laeuft es je Sprache ueber die eigene Quelle
(comp.PROFILE) und die eigenen Texte. Die englischen Bilder zeigen
englische Screens und englische Headlines.

Aufruf:
    python tool/make_tablet_screenshots.py

Ausgabe:
    releases/testapk/screenshots/marketing/tablet7/*.png   (1080x1920)
    releases/testapk/screenshots/marketing/tablet10/*.png  (1920x1200)
    releases/testapk/screenshots/marketing/en/tablet7/*.png
    releases/testapk/screenshots/marketing/en/tablet10/*.png
    fastlane/metadata/android/<sprache>/images/tabletScreenshots/{7in,10in}/*.png
"""
import pathlib
import sys

from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# Das Compositor-Skript bringt die Texte, die Schriften und die
# Kompositions-Helfer mit. Der Import laedt es nur - die main() laeuft
# nicht (sie ist ueber __name__ geschuetzt).
import make_store_screenshots as comp  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARKETING = ROOT / 'releases' / 'testapk' / 'screenshots' / 'marketing'
FASTLANE = ROOT / 'fastlane' / 'metadata' / 'android'

GROSSE_7 = (1080, 1920)
GROSSE_10 = (1920, 1200)

# Die Play-Sprache je Profil-Sprache. 'de' -> de-DE, 'en' -> en-US.
FASTLANE_SPRACHE = {'de': 'de-DE', 'en': 'en-US'}


def _zielordner(sprache: str, groesse: str) -> pathlib.Path:
    return FASTLANE / sprache / 'images' / 'tabletScreenshots' / groesse


def _speichere(bild: Image.Image, ziele: list) -> None:
    for ziel in ziele:
        ziel.parent.mkdir(parents=True, exist_ok=True)
        bild.save(ziel, format='PNG', optimize=True)


def _ist_dunkel(quelle: pathlib.Path) -> bool:
    """Ist der Screen in der dunklen Variante gerendert?

    Der Export nennt die Variante im Dateinamen (z. B. '_dunkel').
    """
    return 'dunkel' in quelle.stem.lower()


def _komponiere_10zoll(comp, profil, name, headline, subline, badge, dunkel):
    """Baut das 10-Zoll-Bild EINES Screens.

    Siehe den Kommentar im Aufrufer: je Screen die passende Komposition
    (Modus-Kacheln, App-Kacheln oder der geteilte Bildschirm).
    """
    if name == '04_entdecken':
        # Die fuenf echten Modus-Kacheln, nicht der Placeholder-Screen.
        tiles = sorted(profil['tiles'].glob('tile_*.png'),
                       key=lambda p: int(p.stem.split('_')[1]))
        if not tiles:
            return None
        crops = [comp._crop_tile(Image.open(t)) for t in tiles]
        return comp.compose_modes_wqhd(crops, headline, subline, badge,
                                        W=GROSSE_10[0], H=GROSSE_10[1])

    if name == '06_hell_dunkel':
        # HELL + DUNKEL als EINER Screen, schraeg geteilt. Ohne den
        # Split stand nur die helle Variante im Bild, obwohl die
        # Ueberschrift "Hell oder dunkel" versprach.
        hell = profil['src'] / '04_anpassen.png'
        dunkel_src = profil['src'] / '04_anpassen_dunkel.png'
        if not dunkel_src.exists():
            return None
        shot = comp.split_screen(Image.open(hell).convert('RGB'),
                                  Image.open(dunkel_src).convert('RGB'),
                                  winkel=-30.3, anker_x=0.5, anker_y=0.45)
        return comp.compose_card_wqhd(shot, headline, subline, badge,
                                       dark=False,
                                       W=GROSSE_10[0], H=GROSSE_10[1])

    # Kacheln aus dem Dart-Export, wenn es sie gibt.
    cards = comp.load_cards(comp.QUELLE.get(name, name),
                            default_src='%s.png' % comp.QUELLE.get(name, name),
                            margin=comp.CARD_MARGIN_LOGICAL
                            if name in ('01_willkommen', '02_aktuelles', '03_chat', '05_anpassen')
                            else 0.0,
                            cards_dir=profil['cards'])
    if cards:
        return comp.compose_cards_wqhd(
            cards, headline, subline, badge,
            heading=profil['heading_eisbrecher']
            if name == '07_eisbrecher' else None,
            cols=2 if name == '07_eisbrecher' else 1,
            dark=dunkel, W=GROSSE_10[0], H=GROSSE_10[1])

    # Sonst der ganze Bildschirm (Startseite).
    quelle = profil['src'] / ('%s.png' % comp.QUELLE.get(name, name))
    shot = Image.open(quelle).convert('RGB')
    return comp.compose_card_wqhd(shot, headline, subline, badge, dark=dunkel,
                                   W=GROSSE_10[0], H=GROSSE_10[1])


def main() -> int:
    anzahl = 0

    for profil in comp.PROFILE:
        lang = profil['lang']
        sprache = FASTLANE_SPRACHE.get(lang, lang)
        basis = MARKETING if lang == 'de' else MARKETING / 'en'
        out_7 = basis / 'tablet7'
        out_10 = basis / 'tablet10'

        # ------------------------------------------------------------------
        # 7 Zoll: die Kachel-Variante des Smartphones, 1:1 (1080x1920 ist
        # genau die Play-Vorgabe fuer das 7-Zoll-Tablet).
        # ------------------------------------------------------------------
        kacheln = profil['out_9x16_kacheln']
        if not kacheln.exists():
            print('  %s: Kacheln fehlen (%s) - zuerst '
                  'python tool/make_store_screenshots.py'
                  % (lang, kacheln.relative_to(ROOT)))
            return 1

        for quelle in sorted(kacheln.glob('*.png')):
            with Image.open(quelle) as bild:
                if bild.size != GROSSE_7:
                    bild = bild.resize(GROSSE_7, Image.LANCZOS)
                ziele = [out_7 / quelle.name]
                ziele.append(_zielordner(sprache, '7in') / quelle.name)
                _speichere(bild, ziele)
            anzahl += 1
            print('  %s 7 Zoll: %s' % (lang, quelle.name))

        # ------------------------------------------------------------------
        # 10 Zoll: neu komponiert in 1920x1200.
        #
        # JE SCREEN EIGENE KOMPOSITION (04.11.2026). Vorher stand in ALLEN
        # Bildern der ganze Telefon-Screen links - das brachte drei
        # Fehler:
        #
        #   * Der Screen fuellte die volle Bildhoehe; oben schnitt die
        #     Kante mitten durch den "Ueberspringen"-Knopf.
        #   * Alles wurde kleiner - das App-Logo schrumpfte auf 150 px
        #     und wirkte unscharf.
        #   * Fuer 04 (Entdecken) gibt es keinen Screen, sondern fuenf
        #     Modus-Kacheln: der Dart-Placeholder (eine schwarze Box mit
        #     X) stand im Bild. Fuer 06 (Hell/Dunkel) fehlte die
        #     Schraegteilung - es stand nur die helle Variante.
        #
        # Die Reihenfolge:
        #   1) Modus-Kacheln (04)      -> compose_modes_wqhd
        #   2) Kacheln aus dem Export  -> compose_cards_wqhd (1:1, scharf)
        #   3) Bildschirm (06)         -> compose_card_wqhd mit Split
        # ------------------------------------------------------------------
        for name, (headline, subline, badge) in profil['shots'].items():
            quelle = profil['src'] / ('%s.png' % comp.QUELLE.get(name, name))
            if not quelle.exists():
                print('  %s 10 Zoll: %s - Quelle fehlt, uebersprungen'
                      % (lang, name))
                continue

            dunkel = name == '08_datenschutz'
            bild = _komponiere_10zoll(
                comp, profil, name, headline, subline, badge, dunkel)

            if bild is None:
                print('  %s 10 Zoll: %s - nichts zu zeigen, uebersprungen'
                      % (lang, name))
                continue

            ziele = [out_10 / ('%s.png' % name)]
            ziele.append(_zielordner(sprache, '10in') / ('%s.png' % name))
            _speichere(bild, ziele)
            anzahl += 1
            print('  %s 10 Zoll: %s (%s)' % (lang, name, bild.size))

    print()
    print('%d Tablet-Screenshots geschrieben (7 Zoll: 1080x1920 Kacheln, '
          '10 Zoll: 1920x1200 neu komponiert, je Sprache eigene Quellen).'
          % anzahl)
    return 0


if __name__ == '__main__':
    sys.exit(main())
