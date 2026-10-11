"""
tool/generate_launcher_icon.py
=============================
Erzeugt das Android-Launcher-Icon als echtes adaptives Icon aus dem
Thestia-Basis-Icon (`assets/images/thestia_icon_base.png`, EINZIGE Logo-Quelle).

Problem, das dieses Tool loest
------------------------------
Das Basis-Logo ist ein abgerundetes Quadrat, in dem der Schriftzug "Thestia"
ueber die volle Breite laeuft. Adaptive Icons werden vom Launcher auf eine
KREISFLAECHE maskiert (72 dp von 108 dp Leinwand). Ein Quadrat, das die
Safe-Zone (66 dp) ausfuellt, schiebt seine Ecken dabei weit ueber den
Sichtkreis hinaus - der Kreis schneidet die Enden des Schriftzugs ab
("Thestia" wurde zu "hestia").

Loesung
-------
Das Logo wird in seine Bestandteile zerlegt:

  * Hintergrund  = Markenverlauf, vollflaechig 108 dp
  * Vordergrund  = Herz + Schriftzug, transparent, so skaliert, dass die
                   Diagonale in einen Kreis mit 66 dp Durchmesser passt

Damit liegt das komplette Artwork garantiert in der Safe-Zone: Kreis-,
Squircle- oder Rounded-Square-Maske schneiden NICHTS ab, und der Name
bleibt immer lesbar. Zusaetzlich:

  * `monochrome`-Layer fuer Android 13+ (themed icons)
  * Legacy-`ic_launcher.png` als echtes RUNDES Icon fuer aeltere Launcher
    (vor Android 8 kennt das System keine adaptive Icons)

Aufruf:
    python tool/generate_launcher_icon.py
"""

from __future__ import annotations

import math
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / 'assets' / 'images' / 'thestia_icon_base.png'

# --- Adaptive-Icon-Geometrie (Android-Richtlinie) --------------------------
# 108 dp Leinwand, 72 dp Sichtkreis, 66 dp garantiert sichtbarer Bereich.
CANVAS_DP = 108.0
MASK_DP = 72.0
SAFE_DP = 66.0
CANVAS_PX = 1024

# Adaptive-Icons werden mit diesen Dpi-Werten ausgeliefert.
DENSITIES = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324,
             'xxxhdpi': 432}
# Legacy-Launcher (ohne adaptive Icons) erwarten die klassischen Icon-Groessen.
LEGACY_SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144,
                'xxxhdpi': 192}

RES = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'

# --- Trennung Artwork / Verlauf -------------------------------------------
# Das Artwork (Herz, Kopf-Silhouetten, Funken, Schriftzug) ist weiss bis
# hellrosa, der Verlauf ist satt (min(r,g,b) <= ~60). `min(r,g,b)` trennt
# die beiden sauber: HIGH = volle Deckkraft, LOW = kein Artwork.
ARTWORK_LO = 88.0
ARTWORK_HI = 168.0

GRID = 24  # Aufloesung der Hintergrund-Rekonstruktion


def split_logo(src: Image.Image) -> tuple[np.ndarray, np.ndarray]:
    """Trennt das Logo in (Artwork-RGB, Artwork-Alpha) mit Alpha in 0..255."""
    arr = np.asarray(src.convert('RGBA'), dtype=np.float64)
    rgb, alpha = arr[:, :, :3], arr[:, :, 3]
    lo, hi = ARTWORK_LO, ARTWORK_HI
    t = np.clip((rgb.min(axis=2) - lo) / (hi - lo), 0.0, 1.0)
    a = t * (alpha / 255.0) * 255.0
    a[alpha < 200] = 0.0
    return rgb, a


def build_background(src: Image.Image, rgb: np.ndarray,
                     art_a: np.ndarray, size: int) -> Image.Image:
    """Baut den Hintergrund des adaptiven Icons als smooth Gradient.

    Frueher wurde der Verlauf aus dem Quellbild rekonstruiert: die
    Nicht-Artwork-Pixel wurden auf ein 24x24-Gitter gemittelt und
    hochskaliert. Das hatte einen Fehler, der auf dem Geraet als
    SCHATTEN zu sehen war:

    Eine Gitterzelle, in der fast nur Artwork liegt (Herz, Koepfe,
    Schriftzug), hat nur wenige Nicht-Artwork-Pixel - und ihr Mittelwert
    ist dadurch deutlich dunkler als der Verlauf an der Stelle. Das
    Ergebnis war ein Hintergrund mit dunklen Stellen GENAU DA, WO DAS
    ARTWORK LIEGT. Da das Artwork halbtransparente Raender hat, schimmerte
    das durch - die "komischen Schatten".

    Gemessen: 7,8 % der Flaeche unter Luma 40, und der Bereich deckte
    sich mit dem Artwork.

    Jetzt wird der Verlauf nicht mehr gemittelt, sondern GEPASST: aus den
    Pixeln des Aussenrings (dort gibt es kein Artwork, nur Verlauf) wird
    je Farbkanal eine Ebene farbe = a*x + b*y + c per kleinster Quadrate
    bestimmt. Ein smooth Gradient in einer Richtung ist damit exakt
    beschrieben, und es gibt keine Zellen, die durch Artwork verfaelscht
    werden koennen.

    Voraussetzung ist, dass der Verlauf in der Tat smooth ist - das ist er
    (pink -> magenta -> violett, diagonal).
    """
    h, w = art_a.shape
    src_alpha = np.asarray(src.convert('RGBA'))[:, :, 3]

    ys, xs = np.mgrid[0:h, 0:w]
    mitte_y, mitte_x = (h - 1) / 2.0, (w - 1) / 2.0
    abstand = np.hypot(xs - mitte_x, ys - mitte_y) / (min(w, h) / 2.0)

    # Aussenring: 42 % bis 50 % vom Zentrum. Dort ist kein Artwork, nur
    # Verlauf - und der Ring deckt alle Richtungen ab, also auch die
    # komplette Bandbreite des Verlaufs.
    ring = (abstand > 0.42) & (abstand < 0.50) & (src_alpha >= 250)
    if ring.sum() < 100:
        raise SystemExit('Aussenring zu duenn - Schwellen pruefen.')

    # Kleinste Quadrate fuer farbe = a*x + b*y + c, je Kanal.
    x = xs[ring].astype(np.float64)
    y = ys[ring].astype(np.float64)
    ones = np.ones_like(x)
    design = np.stack([x, y, ones], axis=1)
    farben = rgb[ring]                      # (n, 3)

    # Normalgleichungen: (D^T D) p = D^T f. 3x3, numerisch stabil.
    ata = design.T @ design
    if abs(np.linalg.det(ata)) < 1e-6:
        raise SystemExit('Aussenring ist entartet - Verlauf nicht fassbar.')
    koeff = np.linalg.solve(ata, design.T @ farben)   # (3, 3)

    def ebene(groesse: int) -> np.ndarray:
        gy, gx = np.mgrid[0:groesse, 0:groesse]
        gx = gx.astype(np.float64) * (w - 1) / (groesse - 1)
        gy = gy.astype(np.float64) * (h - 1) / (groesse - 1)
        out = (koeff[0][None, None, :] * gx[:, :, None]
               + koeff[1][None, None, :] * gy[:, :, None]
               + koeff[2][None, None, :])
        return np.clip(out, 0, 255)

    bild = Image.fromarray(ebene(size).astype(np.uint8), 'RGB')
    return _rund(bild.convert('RGBA'), size)


def _rund(rgb: Image.Image, size: int, weich: float = 1.2) -> Image.Image:
    """Schneidet ein Quadrat zu einem Kreis mit weichem Rand.

    WARUM: `android:background` einer adaptiven Datei ist ein RECHTECK.
    Der Launcher legt seine eigene Form darueber - je nach Geraet ein
    Squircle, ein Kreis, ein abgerundetes Quadrat. Der Verlauf im
    Hintergrund fuellt aber die ganze Leinwand, also zeigt das Icon
    IMMER in der Form des Launchers. Wer ein rundes Icon will, kann das
    dem Launcher nicht vorschreiben: der legt die Form fest.

    Der Weg, der unabhaengig vom Launcher rund aussieht: der Hintergrund
    ist selbst schon ein Kreis und die Ecken sind transparent. Dann
    beschnitten die meisten Masken nichts Sichtbares - der sichtbare
    Teil ist der Kreis, gleichgueltig ob die Maske rund oder
    squirclig ist.

    Der Rand ist weich, weil der Launcher die Maske bei den meisten
    Geraeten noch zusaetzlich antialiaset. Ein harter Alphaschnitt
    zeigte sich sonst als helle oder dunkle Linie am Kreis.

    Der Kreis sitzt zentriert und fuellt die Leinwand zu 100 %. Das ist
    Absicht: kleiner ergaebe ringsum eine Luecke, in der die Form des
    Launchers wieder sichtbar wuerde - also genau das, was hier
    vermieden werden soll.
    """
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    if weich > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(radius=weich))

    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(rgb, (0, 0), mask)
    return out


def build_foreground(src: Image.Image, rgb: np.ndarray, art_a: np.ndarray,
                     bg: Image.Image, size: int) -> tuple[Image.Image, tuple]:
    """Artwork transparent, in den Safe-Zone-Kreis skaliert und zentriert."""
    h, w = art_a.shape
    ys, xs = np.mgrid[0:h, 0:w]
    ys, xs = np.nonzero(art_a > 2.0)
    if not len(ys):
        raise SystemExit('Kein Artwork erkannt - Schwellen pruefen.')
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    bw, bh = x1 - x0, y1 - y0

    # Un-Mix: die halbtransparenten Randpixel des Originals enthalten noch
    # den dunklen Verlauf. Ohne Korrektur entsteht ein dunkler Halo um Herz
    # und Schrift. Aus "beobachtet = a*Artwork + (1-a)*Hintergrund" loesen
    # wir die echte Artwork-Farbe.
    alpha = np.clip(art_a[y0:y1, x0:x1] / 255.0, 0.0, 1.0)[..., None]
    bg_crop = np.asarray(
        bg.resize((w, h), Image.BICUBIC).convert('RGB'),
        dtype=np.float64)[y0:y1, x0:x1]
    obs = rgb[y0:y1, x0:x1]
    safe = np.maximum(alpha, 0.06)
    unmixed = np.where(alpha > 0.02, (obs - (1.0 - safe) * bg_crop) / safe, obs)
    art = Image.fromarray(
        np.clip(np.dstack([unmixed, art_a[y0:y1, x0:x1]]), 0, 255)
        .astype(np.uint8), 'RGBA')

    # Skalierung so, dass die Diagonale in den Safe-Zone-Kreis passt -
    # nur so bleibt der breite Schriftzug bei Kreis-Maske vollstaendig.
    safe_px = SAFE_DP / CANVAS_DP * size
    s = safe_px / math.hypot(bw, bh)
    nw, nh = max(1, round(bw * s)), max(1, round(bh * s))
    art = art.resize((nw, nh), Image.LANCZOS)

    fg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    fg.alpha_composite(art, ((size - nw) // 2, (size - nh) // 2))
    info = (bw, bh, nw, nh)
    return fg, info


def build_monochrome(fg: Image.Image, size: int) -> Image.Image:
    """Weisse Silhouette fuer Android 13+ (themed icons)."""
    arr = np.asarray(fg, dtype=np.float64)
    a = arr[:, :, 3]
    # Alpha leicht betonen, damit auch die duennen Striche der Schrift
    # in der monochrome-Darstellung nicht verschwinden.
    a = np.clip(a * 1.15, 0, 255)
    return Image.fromarray(
        np.dstack([np.full_like(a, 255.0), np.full_like(a, 255.0),
                   np.full_like(a, 255.0), a]).astype(np.uint8), 'RGBA')


def build_legacy(fg: Image.Image, bg: Image.Image, size: int) -> Image.Image:
    """Rundes Icon fuer Launcher ohne Adaptive-Icon-Support."""
    out = bg.resize((size, size), Image.LANCZOS)
    r = 0.5 * MASK_DP / CANVAS_DP * size
    ss = 4
    mask = Image.new('L', (size * ss, size * ss), 0)
    ImageDraw.Draw(mask).ellipse(
        [size * ss / 2 - r * ss, size * ss / 2 - r * ss,
         size * ss / 2 + r * ss, size * ss / 2 + r * ss], fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)

    art = fg.resize((size, size), Image.LANCZOS)
    composed = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    composed.paste(out, (0, 0), mask)
    composed.alpha_composite(art)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    canvas.paste(composed, (0, 0), mask)
    return canvas


def write_png(img: Image.Image, path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f'  {path.relative_to(ROOT)}  {img.size[0]}x{img.size[1]}')


ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generiert von tool/generate_launcher_icon.py - nicht handaendig aendern.
     Hintergrund = Markenverlauf (volflaechig), Vordergrund = Herz +
     Schriftzug in der Safe-Zone, damit eine KREIS-Maske des Launchers
     nichts abschneidet. monochrome = Android 13+ Themed Icons. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@drawable/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
'''


def main() -> None:
    if not SRC.exists():
        sys.exit(f'Quelle fehlt: {SRC}')
    src = Image.open(SRC)

    rgb, art_a = split_logo(src)
    bg = build_background(src, rgb, art_a, CANVAS_PX)
    fg, (bw, bh, nw, nh) = build_foreground(src, rgb, art_a, bg, CANVAS_PX)
    mono = build_monochrome(fg, CANVAS_PX)

    dp_w = nw / CANVAS_PX * CANVAS_DP
    print(f'Artwork {bw}x{bh}px -> {nw}x{nh}px = {dp_w:.1f}dp breit '
          f'(Sichtkreis {MASK_DP:.0f}dp, Safe-Zone {SAFE_DP:.0f}dp)')

    # Flutter-Assets (auch fuer Splash/Notifications verwendbar)
    write_png(fg, ROOT / 'assets' / 'images' / 'thestia_icon_foreground.png')
    write_png(bg, ROOT / 'assets' / 'images' / 'thestia_icon_background.png')

    for dpi, px in DENSITIES.items():
        write_png(fg.resize((px, px), Image.LANCZOS),
                  RES / f'drawable-{dpi}' / 'ic_launcher_foreground.png')
        write_png(bg.resize((px, px), Image.LANCZOS),
                  RES / f'drawable-{dpi}' / 'ic_launcher_background.png')
        write_png(mono.resize((px, px), Image.LANCZOS),
                  RES / f'drawable-{dpi}' / 'ic_launcher_monochrome.png')

    for dpi, px in LEGACY_SIZES.items():
        write_png(build_legacy(fg, bg, px),
                  RES / f'mipmap-{dpi}' / 'ic_launcher.png')

    xml = RES / 'mipmap-anydpi-v26' / 'ic_launcher.xml'
    xml.parent.mkdir(parents=True, exist_ok=True)
    xml.write_text(ADAPTIVE_XML, encoding='utf-8')
    print(f'  {xml.relative_to(ROOT)}')

    print('Launcher-Icon erzeugt (round, Safe-Zone, monochrome).')


if __name__ == '__main__':
    main()
