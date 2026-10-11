# tool/make_splash_icon.py
#
# Erzeugt android12splash.png fuer den Android-12+-Splash.
#
# WARUM ES DAS GIBT (das Bild war bisher handgepflegt):
# `android:windowSplashScreenAnimatedIcon` hat eine feste Geometrie:
# der Splash zeichnet in ein Fenster von 288dp x 288dp und die sichtbare
# Maske ist ein Kreis von 240dp. Ist das Drawable <= 288dp, wird es 1:1
# in dieses Fenster gelegt - die sichtbare Flaeche ist dann exakt das
# Drawable, nicht der 240dp-Kreis.
#
# Der bisherige android12splash.png fegte die 288dp-Leinwand mit einem
# randlosen Kreis voll. Ergebnis auf dem Geraet: der Kreis kam mit 288dp
# statt 240dp, also sichtbar zu gross aufgezoomt.
#
# Die Loesung ist deshalb nicht "Logo verkleinern", sondern der
# Systemgeometrie folgen: 288dp-Leinwand, darin ein Kreis von exakt
# 240dp, der Rand transparent. Damit greift die Systemmaske ohne
# Beschnitt und der Kreis erscheint in der vorgesehenen Groesse.
#
# Kanten-Anti Aliasing: Der Kreisrand wird mit einem weichen Alpha-
# Verlauf gezeichnet (1.5px Breite). Ohne das zeigt der System-Scaler
# nach dem Downsample auf typischen Displays eine Treppe am Rand.

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
SRC = ROOT / 'assets' / 'images' / 'thestia_icon_base.png'

# Splash-Fenster in dp (Android-12-Splash-Spezifikation).
SPLASH_DP = 288

# Sichtkreis des Splash.
#
# Die Android-Spezifikation nennt 240dp als Sichtkreis bei 288dp Fenster.
# Das ist die Geometrie, nach der das SYSTEM skaliert - sie sagt aber
# nichts darueber, wie gross das Logo im Kreis wirken soll.
#
# Der Splash sah trotz 240dp-Kreis "gezoomt" aus. Grund: das Logo fuellt
# seinen Kreis zu 100 %. Das adaptive Icon in der App-Liste dagegen
# legt seinen Inhalt in die 72-dp-Safe-Zone einer 108-dp-Leinwand, also
# auf zwei Drittel. Beide Seite an Seite wirkt der Splash deshalb
# ausgezoomt, obwohl die technische Kreisgroesse stimmte.
#
# Deshalb folgt der Kreis demselben Verhaeltnis wie die Safe-Zone:
# 288 * 2/3 = 192dp.
CIRCLE_DP = 192

# Der Kreis sitzt mittig. 288 - 240 = 48dp Rand, also 24dp je Seite.
PADDING_DP = (SPLASH_DP - CIRCLE_DP) // 2

DENSITIES = {
    'mdpi': 1,
    'hdpi': 1.5,
    'xhdpi': 2,
    'xxhdpi': 3,
    'xxxhdpi': 4,
}

# Kanten in dp breit ausgeblendet, damit das Downsample sauber bleibt.
EDGE_DP = 1.5


def circle_mask(size: int, diameter: int, edge: int) -> Image.Image:
    """Alpha-Maske: Kreis mit weichem Rand, sonst quadratisch."""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)

    # Kernbereich deckend, danach mit kleinem Radius weichzeichnen.
    inset = edge
    draw.ellipse(
        [inset, inset, diameter - 1 - inset, diameter - 1 - inset],
        fill=255,
    )
    return mask.filter(ImageFilter.GaussianBlur(radius=edge / 2.0))


def build_splash(src: Image.Image, size: int) -> Image.Image:
    scale = size / float(SPLASH_DP)
    diameter = int(round(CIRCLE_DP * scale))
    padding = int(round(PADDING_DP * scale))
    edge = max(1, int(round(EDGE_DP * scale)))

    # Das Basisbild quadratisch beschneiden und auf den Sichtkreis
    # einpassen. Ohne das Beschneiden wuerde ein nicht quadratisches
    # Quellbild den Kreis verlassen.
    box = min(src.width, src.height)
    cropped = src.crop((0, 0, box, box)).convert('RGBA')
    art = cropped.resize((diameter, diameter), Image.LANCZOS)

    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(art, (padding, padding))

    # Rundes Alpha auf den Kreis zuschneiden. Der weiche Rand ist kein
    # Dekor: er verhindert die Treppe, die der System-Scaler sonst
    # aus einem harten Alphaschnitt macht.
    mask = Image.new('L', (size, size), 0)
    hole = Image.new('L', (size, size), 0)
    ImageDraw.Draw(hole).ellipse(
        [padding + edge, padding + edge,
         padding + diameter - 1 - edge, padding + diameter - 1 - edge],
        fill=255,
    )
    mask = hole.filter(ImageFilter.GaussianBlur(radius=edge / 2.0))

    out = canvas.copy()
    out.putalpha(mask)
    return out


def write_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, 'PNG', optimize=True)


def main() -> None:
    if not SRC.exists():
        sys.exit(f'Quelle fehlt: {SRC}')
    src = Image.open(SRC).convert('RGBA')

    for dpi, factor in DENSITIES.items():
        size = int(round(SPLASH_DP * factor))
        img = build_splash(src, size)
        write_png(img, RES / f'drawable-{dpi}' / 'android12splash.png')
        # Die Nachtvariante ist identisch: das Logo ist ein Verlauf und
        # braucht keine Anpassung. Sie existiert nur, weil Android sie
        # dort erwartet, wo das normale 'drawable' nicht greift.
        write_png(img, RES / f'drawable-night-{dpi}' / 'android12splash.png')

    print(f'Splash erzeugt: {SPLASH_DP}dp Leinwand, {CIRCLE_DP}dp Kreis, '
          f'{PADDING_DP}dp Rand je Seite.')


if __name__ == '__main__':
    import sys
    main()