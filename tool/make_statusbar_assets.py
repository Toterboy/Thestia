"""
tool/make_statusbar_assets.py
=============================
Schneidet die echten Statusleisten-Symbole aus einem Referenz-Screenshot
des Geraets heraus und legt sie als Sprite ab.

WARUM ueberhaupt ein Sprite
---------------------------
Die Symbole wurden vorher mit Pillow nachgezeichnet - Linien, Boegen,
Polygone. Das Ergebnis war jedes Mal nur eine Annaeherung: die
Strichstaerke, die Bogenwinkel und die Proportionen stimmten nicht.
Die Statusleiste ist nicht 1:1 kopiert, sondern nachgeahmt.

Also: kein Nachbauen mehr. Das Original wird pixelgenau uebernommen.

Ablauf
------
1. Referenz-Screenshot als Datei bereitstellen, z. B.:

       python tool/make_statusbar_assets.py --ref "C:\\Users\\...\\image.png"

   Ist kein --ref angegeben, wird nach den Dateien gesucht, die das
   Skript selbst schon einmal gefunden hat (siehe REF_PRESETS).

2. Das Skript erkennt die Statusleiste am oberen Bildrand, schneidet
   die vier Symbolgruppen anhand ihrer Pixel-Spalten aus und schreibt

       assets/images/statusbar_icons.png   (Sprite, einzeilig)

   mit fester Reihenfolge: mute, wifi, signal, battery.

3. Zusaetzlich schreibt es tool/statusbar_geometry.json mit den
   gemessenen Werten (Positionen, Hoehen, Prozentzahl, Uhrzeit). Die
   Komposition liest diese Datei statt Values zu raten.

4. Ueberprueft wird das Ergebnis mit --check: das Skript meldet dann,
   ob die Icons im Sprite transparenten Hintergrund haben und ob die
   Reihenfolge stimmt.

Voraussetzung: Pillow (siehe tool/requirements.txt).
"""

import argparse
import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITE = ROOT / 'assets' / 'images' / 'statusbar_icons.png'
GEOMETRY = ROOT / 'tool' / 'statusbar_geometry.json'

# Reihenfolge im Sprite, fest. Die Reihenfolge im Cluster ist auf
# Android: Stumm, WLAN, Signal, Akku.
ORDER = ['mute', 'wifi', 'signal', 'battery']

# Frueher von hier aus bearbeitete Referenzen. Wenn eine davon passt,
# wird sie ohne --ref verwendet.
REF_PRESETS = [
    pathlib.Path(r'C:\Users\Thoralf\AppData\Local\Temp\opencode\statusbar_ref.png'),
    ROOT / 'docs' / 'statusbar_reference.png',
]


def find_reference(explicit: str | None) -> pathlib.Path:
    if explicit:
        p = pathlib.Path(explicit).expanduser()
        if not p.is_file():
            sys.exit(f'Referenz nicht gefunden: {p}')
        return p
    for p in REF_PRESETS:
        if p.is_file():
            print(f'Referenz (Vorgabe): {p}')
            return p
    sys.exit(
        'Keine Referenz gefunden.\n'
        'Bitte --ref mit dem Pfad zum Screenshot angeben:\n'
        '  python tool/make_statusbar_assets.py --ref "C:\\...\\image.png"\n'
        'Der Screenshot muss die Statusleiste am oberen Rand zeigen, '
        'die Symbole hell auf dunklem Grund.')


def detect_band(im, max_fraction=0.22):
    """Findet die Statusleiste als oberes Band mit hohem Kontrast.

    Die Symbole sind heller (und kraeftiger gesättigt) als der
    Hintergrund. Gesucht ist deshalb die Zeile, in der die Anzahl
    stark abweichender Pixel von oben nach unten am groessten ist -
    das ist die Icon-Zeile, nicht die Mitte einer Verlaufsflaeche.
    """
    rgb = im.convert('RGB')
    w, h = rgb.size
    px = rgb.load()

    best_row, best_score = 0, -1.0
    for y in range(0, int(h * max_fraction)):
        # Mittelwert als Hintergrund dieser Zeile annehmen und die
        # Ausreicher gegen ihn zaehlen.
        rs = gs = bs = n = 0
        for x in range(0, w, 4):
            r, g, b = px[x, y]
            rs += r
            gs += g
            bs += b
            n += 1
        if not n:
            continue
        mr, mg, mb = rs / n, gs / n, bs / n
        hits = 0
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if abs(r - mr) + abs(g - mg) + abs(b - mb) > 150:
                hits += 1
        score = hits / (w / 2)
        if score > best_score:
            best_score, best_row = score, y

    return best_row, best_score


def find_clusters(px, w, y, tolerance=150):
    """Spalten mit Symbolpixeln zu zusammenhaengenden Gruppen verbinden.

    Zwischen den Symbolen sind Luecken. Eine Luecke zaehlt nur als
    Trenner, wenn sie breiter ist als die halbe Symbolbreite -
    sonst wuerde ein Icon mit einem Strich darin zerrissen.
    """
    cols = []
    for x in range(w):
        hits = 0
        for yy in range(max(0, y - 12), y + 13):
            r, g, b = px[x, yy]
            # Weiss-Nahe: die Referenzsymbole sind hell. Ueber die
            # Sättigung erkennbar, damit ein heller Hintergrund
            # (Wolke) nicht mitgezaehlt wird.
            if r > 200 and g > 200 and b > 200:
                hits += 1
        cols.append(hits > 0)

    groups, start = [], None
    for x, on in enumerate(cols):
        if on and start is None:
            start = x
        elif not on and start is not None:
            groups.append((start, x))
            start = None
    if start is not None:
        groups.append((start, len(cols)))

    # Zu enge Gruppen (schmale Kratzer) verwerfen.
    min_w = max(4, w // 120)
    return [g for g in groups if g[1] - g[0] >= min_w]


def crop_cluster(im, x0, x1, y, pad):
    left = max(0, x0 - pad)
    right = min(im.width, x1 + pad + 1)
    top = max(0, y - pad)
    bottom = min(im.height, y + pad + 1)
    return im.crop((left, top, right, bottom))


def main():
    ap = argparse.ArgumentParser(
        description='Statusleisten-Symbole aus einer Referenz schneiden')
    ap.add_argument('--ref', help='Pfad zum Referenz-Screenshot')
    ap.add_argument('--check', action='store_true',
                    help='Sprite und Geometrie nur pruefen, nicht schreiben')
    args = ap.parse_args()

    if args.check:
        return check()

    ref = find_reference(args.ref)
    im = Image.open(ref)
    print(f'Referenz: {ref}  {im.size}')

    y, score = detect_band(im)
    print(f'Icon-Zeile: y={y}  Kontrast-Score={score:.3f}')
    if score < 0.01:
        sys.exit('Keine Symbolzeile erkannt. Ist das die Statusleiste?')

    rgb = im.convert('RGB')
    groups = find_clusters(rgb.load(), rgb.width, y)
    print(f'Gefundene Spaltengruppen: {len(groups)}')
    for i, (a, b) in enumerate(groups):
        print(f'  {i}: x={a}..{b}  breite={b - a}')

    if len(groups) < 4:
        sys.exit(
            f'Nur {len(groups)} Gruppen gefunden, erwartet werden 4 '
            f'(Stumm, WLAN, Signal, Akku) - plus moeglicherweise die '
            f'Uhrzeit links. Bitte den Screenshot ohne Taskleiste und '
            f'ohne weitere Symbole im Band schneiden.')

    # Die rechten vier Gruppen sind die Symbole. Eine fuenfte ganz
    # links ist in der Regel die Uhrzeit und wird uebersprungen.
    chosen = groups[-4:]

    pad = max(4, rgb.width // 90)
    tiles = []
    for name, (a, b) in zip(ORDER, chosen):
        tile = crop_cluster(rgb, a, b, y, pad)
        tiles.append((name, tile))
        print(f'  {name:<8} {tile.size}')

    # --- Sprite: gleich hoch machen, damit der Composer sie ohne
    # Nachrechnen platzieren kann. ----------------------------------
    height = max(t.size[1] for _, t in tiles)
    gap = 4
    widths = [t.size[0] for _, t in tiles]
    total_w = sum(widths) + gap * (len(tiles) - 1)

    sprite = Image.new('RGBA', (total_w, height), (0, 0, 0, 0))
    cursor = 0
    boxes = {}
    for (name, tile), w in zip(tiles, widths):
        # Symbole unten buendig: die Statusleisten-Glyphen sitzen auf
        # einer gemeinsamen Grundlinie.
        sprite.paste(tile, (cursor, height - tile.size[1]))
        boxes[name] = {'x': cursor, 'y': height - tile.size[1],
                       'w': w, 'h': tile.size[1]}
        cursor += w + gap

    SPRITE.parent.mkdir(parents=True, exist_ok=True)
    sprite.save(SPRITE)
    print(f'\nSprite geschrieben: {SPRITE.relative_to(ROOT)}  {sprite.size}')

    geom = {
        'source': str(ref),
        'sourceSize': list(im.size),
        'iconRowY': y,
        'padding': pad,
        'sprite': boxes,
        'spriteSize': [sprite.size[0], sprite.size[1]],
    }
    GEOMETRY.write_text(json.dumps(geom, indent=2), encoding='utf-8')
    print(f'Geometrie geschrieben: {GEOMETRY.relative_to(ROOT)}')
    print('\nNaechster Schritt: in tool/make_store_screenshots.py die '
          'gezeichneten Symbole durch das Sprite ersetzen.')


def check():
    if not SPRITE.is_file():
        sys.exit(f'Sprite fehlt: {SPRITE}')
    im = Image.open(SPRITE).convert('RGBA')
    alpha = im.getchannel('A')
    box = alpha.getbbox()
    print(f'Sprite {im.size}, sichtbarer Bereich: {box}')
    if box is None:
        sys.exit('Sprite ist vollstaendig transparent - nichts uebernommen.')
    if not GEOMETRY.is_file():
        sys.exit('Geometrie-Datei fehlt.')
    geom = json.loads(GEOMETRY.read_text(encoding='utf-8'))
    missing = [n for n in ORDER if n not in geom['sprite']]
    if missing:
        sys.exit(f'Fehlt im Sprite: {missing}')
    for name, b in geom['sprite'].items():
        if b['x'] + b['w'] > im.size[0]:
            sys.exit(f'{name} ragt aus dem Sprite heraus: {b}')
    print(f'OK  {len(ORDER)} Symbole, Reihenfolge {ORDER}')
    return 0


if __name__ == '__main__':
    sys.exit(main() or 0)
