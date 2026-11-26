"""Erzeugt das runde Thestia-Logo: das Artwork als Kreis.

WARUM ES DAS GIBT (09.11.2026, Betreiber): "Das Runde sollte dabei auch
die Farben von dem Abgerundeten haben (Hier muss das Bild Rund sein)."

DER BEFUND: Das runde Launcher-Icon war blass. Zwei Ursachen, beide
hier behoben:

1) DER VERLAUF WURDE BESCHNITTEN. Das Legacy-Icon legte den
   Hintergrund-Kreis (Radius = halbe Leinwand) in eine kleinere
   Maske (Radius = 72/108 der Leinwand). Sichtbar blieb damit nur die
   **Mitte** des Verlaufs - die satten Randbereiche (pink oben links,
   violett unten rechts) lagen außerhalb. Der Kreis sah dadurch
   deutlich blasser aus als das abgerundete Original.

2) DAS HERZ WAR HALBTRANSPARENT. Die Alpha des Vordergrunds wurde
   aus der Farbe berechnet (`min(r,g,b)` zwischen 88 und 168). Das
   betraf auch die magentafarbene Lippe des Herzens (min = 104-169):
   sie bekam nur 20-100 % Deckkraft und wurde über dem Verlauf zu
   rosa Milchglas. Die Schwelle ist in `generate_launcher_icon.py`
   jetzt enger (88-104), dort ist das Artwork voll deckend.

DAS MODUL: Der runde Schnitt - Verlauf am Rand zusammenführen, damit
keine transparenten Ecken bleiben, dann den Kreis draufsetzen - stand
bisher nur in Dart (`tool/images/generate_round_logo.dart`). Hier ist er in
Python, weil die Favicons und das Legacy-Launcher-Icon mit Pillow
erzeugt werden. Beide Wege liefern dasselbe Bild (dieselbe Quelle,
dieselbe Rechnung) - die beiden Werkzeuge sind unabhängig voneinander
prüfbar.

DIE QUELLE ist immer `assets/images/thestia_icon_base.png` - laut
Projekt-Konvention die EINZIGE Logo-Quelle. Der Weg zum Logo läuft
sonst auseinander (das war schon einmal der Grund für den Bug vom
09.11.2026).
"""
from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image, ImageDraw

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zählen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe ändert.
def _projektwurzel() -> pathlib.Path:
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / 'pubspec.yaml').exists():
            return kandidat
    # DER NOTFALL: Der Ordner mit den Migrationen - den hat auch das
    # kleine Test-Repo der Selbsttests (dort gibt es keine pubspec).
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / 'supabase' / 'migrations').is_dir():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent


WURZEL = _projektwurzel()

QUELLE = WURZEL / 'assets' / 'images' / 'thestia_icon_base.png'


def _quadrat_mit_verlauf(src: Image.Image) -> np.ndarray:
    """Das Artwork auf ein Quadrat bringen, ohne transparente Ecken.

    1) Die opaken Pixel werden zu einem Quadrat beschnitten.
    2) Jedes Pixel außerhalb nimmt den Quellpixel an der GEKLEMMTEN
       Position - der Verlauf läuft damit nahtlos in die Ecken
       weiter, statt transparent zu bleiben.
    3) Was danach noch transparent ist (die abgerundeten Ecken des
       Originals), wird aus dem nächsten opaken Pixel derselben
       Zeile gefüllt.
    """
    arr = np.asarray(src.convert('RGBA'), dtype=np.uint8)
    alpha = arr[:, :, 3]
    opak = alpha > 20
    ys, xs = np.nonzero(opak)
    if len(xs) == 0:
        raise ValueError('Die Quelle hat keine opaken Pixel.')
    min_x, max_x = int(xs.min()), int(xs.max())
    min_y, max_y = int(ys.min()), int(ys.max())
    bw, bh = max_x - min_x + 1, max_y - min_y + 1
    side = max(bw, bh)

    yy, xx = np.mgrid[0:side, 0:side]
    pad_x = (side - bw) // 2
    pad_y = (side - bh) // 2
    sx = np.clip(min_x + (xx - pad_x), 0, arr.shape[1] - 1)
    sy = np.clip(min_y + (yy - pad_y), 0, arr.shape[0] - 1)
    quadrat = arr[sy, sx].copy()

    # Restliche transparente Pixel: aus dem nächsten opaken Pixel
    # derselben Zeile füllen (vorwärts oder rückwärts - was
    # näher liegt).
    a = quadrat[:, :, 3]
    deckend = a >= 200
    spalten = np.arange(side)[None, :]
    vor = np.maximum.accumulate(np.where(deckend, spalten, -1), axis=1)
    rueck = np.minimum.accumulate(
        np.where(deckend[:, ::-1], spalten, side)[:, ::-1], axis=1)
    vor = np.clip(vor, 0, side - 1)
    rueck = np.clip(rueck, 0, side - 1)
    dist_vor = np.abs(spalten - vor)
    dist_rueck = np.abs(rueck - spalten)
    nimm_rueck = (dist_rueck < dist_vor) & (rueck < side)
    quelle_idx = np.where(nimm_rueck, rueck, vor)
    fehlend = ~deckend
    if fehlend.any():
        zeilen = np.arange(side)[:, None]
        fuellung = quadrat[zeilen, quelle_idx]
        quadrat[fehlend] = fuellung[fehlend]
    return quadrat


def rundes_logo(size: int, quelle: pathlib.Path | None = None) -> Image.Image:
    """Das Thestia-Artwork als runder Kreis in [size] x [size].

    Der Kreis sitzt mittig und füllt die Fläche zu 100 % - sonst
    würde ringsum eine Lücke bleiben, in der die Form des
    Launchers wieder sichtbar würde.
    """
    pfad = quelle or QUELLE
    src = Image.open(pfad)
    quadrat = _quadrat_mit_verlauf(src)

    # Auf die Zielgrösse bringen (LANCZOS) und dann den Kreis setzen.
    bild = Image.fromarray(quadrat, 'RGBA').resize((size, size), Image.LANCZOS)

    radius = size / 2.0 - 0.5
    ss = 4  # Ueberabtastung fuer die weiche Kante
    mask = Image.new('L', (size * ss, size * ss), 0)
    ImageDraw.Draw(mask).ellipse(
        [size * ss / 2 - radius * ss, size * ss / 2 - radius * ss,
         size * ss / 2 + radius * ss, size * ss / 2 + radius * ss],
        fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)

    # Weiche Kante (1,5 px): ein harter Alphaschnitt zeigte sich als
    # helle Linie am Kreis.
    weich = 1.5
    if weich > 0:
        px = mask.load()
        for y in range(size):
            for x in range(size):
                dx = x + 0.5 - size / 2
                dy = y + 0.5 - size / 2
                kante = radius - (dx * dx + dy * dy) ** 0.5
                if kante < weich:
                    px[x, y] = int(px[x, y] * max(0.0, min(1.0, kante / weich)))

    # Das Artwork ist innerhalb des Kreises deckend; die Maske ersetzt
    # den Alpha außerhalb.
    ergebnis = bild.copy()
    ergebnis.putalpha(mask)
    return ergebnis


def main() -> int:
    """Schreibt das runde Logo (hell und dunkel) nach assets/images/."""
    ziel_dir = WURZEL / 'assets' / 'images'
    rund = rundes_logo(1024)
    rund.save(ziel_dir / 'thestia_logo_round.png', optimize=True)
    print('  assets/images/thestia_logo_round.png  1024x1024')

    dunkel = rund.copy()
    px = dunkel.load()
    for y in range(dunkel.height):
        for x in range(dunkel.width):
            r, g, b, a = px[x, y]
            if a and not (r > 235 and g > 235 and b > 235):
                px[x, y] = (int(r * 0.88), int(g * 0.88), int(b * 0.88), a)
    dunkel.save(ziel_dir / 'thestia_logo_round_dark.png', optimize=True)
    print('  assets/images/thestia_logo_round_dark.png  1024x1024')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
