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
from PIL import Image, ImageDraw

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
    """Rekonstruiert den Markenverlauf des Logos.

    Nur die Nicht-Artwork-Pixel gehen ein. Sie werden auf ein Gitter
    gemittelt und bicubics hochskaliert - dadurch entsteht ein glatter
    Verlauf, der stufenlos an das Artwork angrenzt (der urspruengliche
    Verlauf ist mehrstufig: pink -> magenta -> violett).
    """
    h, w = art_a.shape
    sel = (np.asarray(src.convert('RGBA'))[:, :, 3] >= 200) & (art_a <= 0.02)
    if not sel.any():
        raise SystemExit('Kein Hintergrund erkannt - Schwellen pruefen.')

    ys, xs = np.mgrid[0:h, 0:w]
    cell = (np.clip(ys / h * GRID, 0, GRID - 1).astype(int) * GRID
            + np.clip(xs / w * GRID, 0, GRID - 1).astype(int))
    acc = np.zeros((GRID * GRID, 3))
    cnt = np.zeros(GRID * GRID)
    np.add.at(acc, cell[sel], rgb[sel])
    np.add.at(cnt, cell[sel], 1.0)

    grid = np.zeros((GRID, GRID, 3))
    filled = cnt > 0
    for gy in range(GRID):
        for gx in range(GRID):
            if filled[gy * GRID + gx]:
                grid[gy, gx] = acc[gy * GRID + gx] / cnt[gy * GRID + gx]

    # Leere Zellen (z. B. von der runden Form weggeschnitten) aus den
    # Nachbarzellen fuellen, sonst entstehen Löcher im Verlauf.
    filled = (cnt > 0).reshape(GRID, GRID)
    filled_grid = grid
    for _ in range(GRID):
        if filled.all():
            break
        holes = np.argwhere(~filled)
        for gy, gx in holes:
            n, total = 0, np.zeros(3)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = gy + dy, gx + dx
                    if 0 <= ny < GRID and 0 <= nx < GRID and filled[ny, nx]:
                        total += filled_grid[ny, nx]
                        n += 1
            if n:
                filled_grid[gy, gx] = total / n
                filled[gy, gx] = True

    small = Image.fromarray(np.clip(filled_grid, 0, 255).astype(np.uint8),
                            'RGB')
    return small.resize((size, size), Image.BICUBIC).convert('RGBA')


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
