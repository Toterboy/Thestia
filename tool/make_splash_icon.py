#!/usr/bin/env python3
"""Erzeugt die Splash-Grafiken: android12splash.png und splash.png.

ZWEI Splash-Varianten, weil Android zwei verschiedene Splash-Ablaeufe
kennt:

  * Android 12 und neuer (API 31+): `windowSplashScreenAnimatedIcon`.
    Das System legt das Drawable in ein 288-dp-Fenster und maskiert es
    mit einem Kreis. Der sichtbare Kreis ist 160 dp.
  * Android 11 und aelter: `launch_background.xml` - ein Layer-List aus
    Hintergrund und einem zentrierten Bild.

WAS FALSCH WAR (Befund vom 27.10.2026, Android 16 und Android 11):

  * Android 16: das Logo war "an den vier ecken abgeschnitten und zu
    gross". Grund: `android12splash.png` war 288 dp gross und enthielt
    einen Kreis von 192 dp. Das System zeichnet das Drawable 1:1 in
    sein 288-dp-Fenster und maskiert es mit dem 160-dp-Kreis - ein
    192-dp-Kreis ragt an vier Stellen (oben, unten, links, rechts, in
    den Diagonalen) ueber die Maske hinaus. Genau das war der Beschnitt.
  * Android 11: um das Logo lag ein SCHWARZER Kasten. Grund:
    `splash.png` hatte eine opake schwarze Flaeche als Hintergrund
    unter dem Logo.

DIE LOESUNG:

  * `android12splash.png`: 240-dp-Leinwand mit einem Kreis von 120 dp.
    Das System maskiert den Splash mit einem Kreis von 160 dp - ein
    Abzeichen, das kleiner ist, kann nicht beschnitten werden. 120 dp
    passen zur Legacy-Variante (110 dp), damit beide Splashs dasselbe
    Abzeichen in derselben Groesse zeigen.
  * `splash.png`: DASSELBE Abzeichen, aber auf TRANSPARENTEM Grund statt auf
    schwarzem. Der weisse Hintergrund (bzw. der dunkle in der
    Nachtvariante) kommt aus `background.png` und liegt dahinter.

DAS ABZEICHEN selbst ist jetzt ein echter KREIS: der runde Farbverlauf
(`thestia_icon_background.png`) plus das Motiv aus der Vordergrund-Ebene
(`thestia_icon_foreground.png`), mittig darueber. BISHER wurde das
Quadrat-Logo in den Kreis geschnitten - dabei schnitten die Ober- und
Unterkante des Quadrats mitten durch den Kreis und es blieb ein
dunkler Saum oben und unten stehen.

Die Groesse des Legacy-Logos bleibt unveraendert: der Kreis belegt
dieselben 43,75 % der Leinwand wie bisher. Das Logo selbst wird also
NICHT groesser oder kleiner - nur der schwarze Kasten verschwindet.

    python tool/make_splash_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
SRC = ROOT / 'assets' / 'images' / 'thestia_icon_base.png'
# Runder Farbverlauf und Motiv getrennt - so entsteht ein echter Kreis
# ohne beschnittene Kanten (siehe _rundes_artwork).
BG = ROOT / 'assets' / 'images' / 'thestia_icon_background.png'
FG = ROOT / 'assets' / 'images' / 'thestia_icon_foreground.png'

# Anteil des Motivs (Herz + Schriftzug) am Kreisdurchmesser.
#
# Das Motiv belegt in der Vordergrund-Ebene 462 von 1024 px = 45,1 % der
# Ebene. 62 % vom Kreis bedeuten fuer die Ebene also das 1,375-fache
# des Kreisdurchmessers. Der Wert ist so gewaehlt, dass der
# Schriftzug noch lesbar bleibt, aber nicht zu klein wirkt.
ART_ANTEIL = 0.62
ART_ANTEIL_EBENE = 0.451

# --------------------------------------------------------------------------
# Android 12+ (windowSplashScreenAnimatedIcon)
# --------------------------------------------------------------------------
# Leinwand = Icon-Bereich des Systems (240 dp), darin der sichtbare
# Kreis.
#
# WARUM 120 dp UND NICHT 160 dp (NUTZERWUNSCH 27.10.2026: "Es ist zudem
# zu gross. Das zweite passt aber."):
#
# Das System zeichnet das Drawable 1:1 in sein Fenster und maskiert es
# mit einem Kreis von 160 dp. Ein Kreis, der groesser als 160 dp ist,
# wird an vier Stellen beschnitten - das war der urspruengliche
# Fehler (192 dp Kreis in einer 288-dp-Leinwand). Die alte Fassung
# dieses Skripts hatte den Kreis auf exakt 160 dp gesetzt: damit ist
# zwar nichts beschnitten, das Abzeichen ist aber sichtbar groesser
# als das der Legacy-Variante (110 dp) - und genau das hat der Nutzer
# bemerkt.
#
# 120 dp liegen 20 dp innerhalb der Maske (kein Beschnitt unter jeder
# Auslegung des Systems) und sind mit den 110 dp der Legacy-Variante
# praktisch gleich gross. Beide Splashs zeigen damit dasselbe
# Abzeichen in derselben Groesse.
ICON_DP = 240
CIRCLE_DP = 120
PADDING_DP = (ICON_DP - CIRCLE_DP) // 2

# --------------------------------------------------------------------------
# Android 11 und aelter (launch_background.xml)
# --------------------------------------------------------------------------
# Das Bild wird mittig ueber den Hintergrund gelegt. Die bisherigen
# Groessen und der Anteil des Kreises bleiben erhalten - nur der
# schwarze Kasten um das Logo entfaellt.
LEGACY_SIZES = {
    'mdpi': 256,
    'hdpi': 384,
    'xhdpi': 512,
    'xxhdpi': 768,
    'xxxhdpi': 1024,
}
# Anteil des Kreises an der Leinwand (aus dem Altbestand gemessen:
# der Kreis belegte 168 von 384 px = 43,75 %).
LEGACY_CIRCLE_RATIO = 0.4375

DENSITIES = {
    'mdpi': 1,
    'hdpi': 1.5,
    'xhdpi': 2,
    'xxhdpi': 3,
    'xxxhdpi': 4,
}

# Kanten in dp breit ausgeblendet, damit das Downsample des Systems
# sauber bleibt. Ohne das zeigt der System-Scaler nach dem Downsample
# auf typischen Displays eine Treppe am Rand.
EDGE_DP = 1.5


def _circle_mask(size: int, diameter: int, edge: int) -> Image.Image:
    """Alpha-Maske: Kreis mit weichem Rand."""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse(
        [edge, edge, diameter - 1 - edge, diameter - 1 - edge],
        fill=255,
    )
    return mask.filter(ImageFilter.GaussianBlur(radius=edge / 2.0))


def _rundes_artwork(src: Image.Image, diameter: int) -> Image.Image:
    """Das Abzeichen als echter Kreis: Verlauf + Motiv, ohne Schnitte.

    BISHER (Befund 27.10.2026): das Logo wurde als Quadrat in den
    Kreis geschnitten. Weil die Logo-Grafik selbst ein abgerundetes
    Quadrat ist, schnitt der Kreis ihre Ober- und Unterkante an - im
    Splash blieb ein dunkler Saum oben und unten stehen.

    JETZT: der Kreis kommt aus dem RUNDEN Verlauf
    (`thestia_icon_background.png`), das Motiv (Herz + Schriftzug) aus
    der Vordergrund-Ebene wird mittig darueber gelegt. Damit ist die
    Form rund und sauber - ohne beschnittene Kanten.

    [src] wird nicht mehr benutzt - die Parameter bleiben aber, damit
    die Aufrufer unveraendert bleiben.
    """
    verlauf = Image.open(BG).convert('RGBA')
    verlauf = verlauf.resize((diameter, diameter), Image.LANCZOS)

    if FG.exists():
        vordergrund = Image.open(FG).convert('RGBA')
        # Ebene so gross, dass das Motiv ART_ANTEIL des Kreises einnimmt.
        ebene = int(round(diameter * ART_ANTEIL / ART_ANTEIL_EBENE))
        vordergrund = vordergrund.resize((ebene, ebene), Image.LANCZOS)
        versatz = (diameter - ebene) // 2
        verlauf.alpha_composite(vordergrund, (versatz, versatz))

    return verlauf


def build_icon_splash(src: Image.Image, size: int) -> Image.Image:
    """Android 12+: Leinwand mit Kreis in der Mitte, Rand transparent."""
    scale = size / float(ICON_DP)
    diameter = int(round(CIRCLE_DP * scale))
    padding = int(round(PADDING_DP * scale))
    edge = max(1, int(round(EDGE_DP * scale)))

    art = _rundes_artwork(src, diameter)

    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(art, (padding, padding))

    # Auf den Kreis zuschneiden. Der weiche Rand ist kein Dekor: er
    # verhindert die Treppe, die der System-Scaler sonst aus einem
    # harten Alphaschnitt macht.
    hole = Image.new('L', (size, size), 0)
    ImageDraw.Draw(hole).ellipse(
        [padding + edge, padding + edge,
         padding + diameter - 1 - edge, padding + diameter - 1 - edge],
        fill=255,
    )
    canvas.putalpha(hole.filter(ImageFilter.GaussianBlur(radius=edge / 2.0)))
    return canvas


def build_legacy_splash(src: Image.Image, size: int) -> Image.Image:
    """Android 11 und aelter: Logo als Kreis auf TRANSPARENTEM Grund.

    Vorher lag hier ein opakes schwarzes Quadrat - das war der
    "schwarze Kasten" um das Logo. Der Hintergrund kommt aus
    `background.png` und liegt hinter dem Bild.
    """
    scale = size / 256.0
    diameter = max(1, int(round(size * LEGACY_CIRCLE_RATIO)))
    edge = max(1, int(round(EDGE_DP * scale)))

    art = _rundes_artwork(src, diameter)

    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    offset = (size - diameter) // 2
    canvas.alpha_composite(art, (offset, offset))

    # Weicher Kreisrand, damit kein dunkler Saum auf dem transparenten
    # Grund entsteht.
    hole = Image.new('L', (size, size), 0)
    ImageDraw.Draw(hole).ellipse(
        [offset + edge, offset + edge,
         offset + diameter - 1 - edge, offset + diameter - 1 - edge],
        fill=255,
    )
    canvas.putalpha(hole.filter(ImageFilter.GaussianBlur(radius=edge / 2.0)))
    return canvas


def write_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, 'PNG', optimize=True)


def main() -> None:
    if not SRC.exists():
        sys.exit(f'Quelle fehlt: {SRC}')
    src = Image.open(SRC).convert('RGBA')

    for dpi, factor in DENSITIES.items():
        size = int(round(ICON_DP * factor))
        img = build_icon_splash(src, size)
        write_png(img, RES / f'drawable-{dpi}' / 'android12splash.png')
        # Die Nachtvariante ist identisch: das Logo ist ein Verlauf und
        # braucht keine Anpassung. Sie existiert nur, weil Android sie
        # dort erwartet, wo das normale 'drawable' nicht greift.
        write_png(img, RES / f'drawable-night-{dpi}' / 'android12splash.png')

    for dpi, size in LEGACY_SIZES.items():
        img = build_legacy_splash(src, size)
        write_png(img, RES / f'drawable-{dpi}' / 'splash.png')
        write_png(img, RES / f'drawable-night-{dpi}' / 'splash.png')

    print(f'Android 12+: {ICON_DP}dp Leinwand, {CIRCLE_DP}dp Kreis, '
          f'{PADDING_DP}dp Rand je Seite.')
    print(f'Android 11-: Logo als {LEGACY_CIRCLE_RATIO:.0%} der Leinwand, '
          f'Hintergrund transparent.')


if __name__ == '__main__':
    import sys
    main()
