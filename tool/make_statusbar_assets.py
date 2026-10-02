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

from PIL import Image, ImageFilter

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


def _groups_at(px, w, py_h, y, tol, merge, half=6):
    """Roh erkannte Spaltengruppen bei bestimmten Parametern."""
    ink = []
    for x in range(w):
        s = [px[x, yy] for yy in range(y - half, y + half + 1)]
        n = len(s)
        mr = sum(c[0] for c in s) / n
        mg = sum(c[1] for c in s) / n
        mb = sum(c[2] for c in s) / n
        hits = sum(1 for c in s
                   if abs(c[0] - mr) + abs(c[1] - mg) + abs(c[2] - mb) > tol)
        ink.append(hits >= 2)

    raw, start = [], None
    for x, on in enumerate(ink):
        if on and start is None:
            start = x
        elif not on and start is not None:
            raw.append([start, x])
            start = None
    if start is not None:
        raw.append([start, len(ink)])

    merged = []
    for g in raw:
        if merged and g[0] - merged[-1][1] <= merge:
            merged[-1][1] = g[1]
        else:
            merged.append(g)

    return [(a, b) for a, b in merged if b - a >= max(3, int(round(w * 0.010)))]


def detect_icon_groups(px, w, py_h, y, expected=4):
    """Sucht die Parameter, die genau `expected` Symbole ergeben.

    Fest verdrahtete Schwellen sind hier falsch gewesen. Zwei Werte
    muessen gleichzeitig passen, und sie ziehen gegeneinander:

      * Die Toleranz bestimmt, wie schwach ein anti-aliasiertes
        Pixel zaehlt. Zu hoch fallen die ersten drei Signalbaenke weg
        (nur der letzte, 4 px breite, bleibt) - das Bild sieht dann aus
        wie es funktioniert, ist aber voellig falsch. Zu niedrig
        zaehlt Himmel-Rauschen mit.
      * Die Merge-Breite haelt die vier Signalbaenke zusammen, weil
        zwischen ihnen nur 2 px liegen, und muss trotzdem die Icons
        trennen, zwischen denen 6 bis 10 px liegen. Das Fenster ist
        eng: zu 7 px verschmilzt das Signal mit dem Akku.

    Deshalb wird das Paar gesucht statt geraten. Erwartet wird genau
    die Zahl der Symbole, die rechts in der Statusleiste stehen. Findet
    sich keine Kombination, bricht das Skript ab, statt vier falsche
    Schnipsel zu speichern.
    """
    trials = []
    for tol in (60, 70, 80, 90, 100, 120):
        for merge in (3, 4, 5, 6, 7):
            g = _groups_at(px, w, py_h, y, tol, merge)
            # Die Uhrzeit steht links, die Symbole rechts. Der
            # Referenzausschnitt ist ein Streifen des oberen Randes, die
            # Grenze liegt daher bei der Haelfte minus dem
            # Symbolbereich.
            right = [x for x in g if x[0] > w * 0.55]
            trials.append((len(right), abs(len(g) - (expected + 1)),
                           tol, merge, right, g))

    # Exakt vier Symbole rechts gewinnt; unter mehreren Treffern das
    # mit den insgesamt wenigsten Gruppen (weniger Rauschen).
    exact = [t for t in trials if t[0] == expected]
    if not exact:
        best = max(trials, key=lambda t: t[0])
        sys.exit(
            f'Symbolerkennung unzuverlaessig: beste Kombination fand '
            f'{best[0]} Symbole rechts (erwartet {expected}), '
            f'tol={best[2]} merge={best[3]}. '
            f'Gefunden: {best[4]}\n'
            f'Der Screenshot ist evtl. unschaerf, beschnitten oder zeigt '
            f'etwas anderes als die Statusleiste.')
    exact.sort(key=lambda t: t[1])
    _, _, tol, merge, right, all_groups = exact[0]
    print(f'Parameter selbst gesucht: toleranz={tol}  '
          f'merge={merge}  -> {len(right)} Symbole')
    return all_groups, right, tol, merge


def crop_cluster(im, x0, x1, y, pad):
    left = max(0, x0 - pad)
    right = min(im.width, x1 + pad + 1)
    top = max(0, y - pad)
    bottom = min(im.height, y + pad + 1)
    return im.crop((left, top, right, bottom))


def _row_background(rgb, ref_w, y):
    """Mittlere Hintergrundfarbe einer Zeile des Referenzfotos."""
    samples = range(0, ref_w, 7)
    n = len(samples)
    out = []
    for i in range(3):
        out.append(sum(rgb.getpixel((x, y))[i] for x in samples) / n)
    return out


def _deviation(rgb, ref_w, x, y, rows_bg):
    bg_row = rows_bg.get(y)
    if bg_row is None:
        bg_row = _row_background(rgb, ref_w, y)
        rows_bg[y] = bg_row
    p = rgb.getpixel((x, y))
    return sum(abs(p[i] - bg_row[i]) for i in range(3))


def _alpha_for_tile(rgb, ref_w, box, tol):
    """Deckkraft eines Symbols, gemessen gegen den Zeilenhintergrund.

    Weich, nicht binarisiert. Zwei Fehler, beide an derselben Stelle:

      * Feste Schwelle: die Symbole wurden zu dick. An den Raendern
        eines 13-px-Symbols liegen viele Anti-Aliasing-Pixel knapp
        ueber der Schwelle und verbreitern den Strich beim
        Binarisieren um ein Pixel je Seite.
      * Relative Schwelle (62 % vom Maximum): zu duenn. Das Maximum
        stammt aus Ausreissern, der echte Strich liegt weit darunter.

    Die Weichheit ist die ehrliche Uebernahme: die Deckkraft ist die
    Abweichung vom Hintergrund, normalisiert auf das kraeftigste Pixel.
    Die Strichstaerke ist damit die des Originals, unabhaengig davon,
    wie stark die Vorlage verkleinert wurde.

    `tol` ist der Abstand, unterhalb dessen nichts gezaehlt wird. Er
    kommt aus derselben Suche wie die Icon-Erkennung - mit eigenen
    Werten frisst die Messung den Himmelverlauf des Fotos mit.
    """
    x0 = max(0, box[0])
    y0 = max(0, box[1])
    x1 = min(ref_w, box[2])
    y1 = min(rgb.size[1], box[3])
    w = max(1, x1 - x0)
    h = max(1, y1 - y0)

    rows_bg = {}
    devs = []
    for yy in range(y0, y1):
        for xx in range(x0, x1):
            d = _deviation(rgb, ref_w, xx, yy, rows_bg)
            devs.append(d if d > tol else 0.0)
    if not devs:
        return Image.new('L', (w, h), 0)

    # Normierung: ein Pixel bei 32 % des Maximums bekommt volle
    # Deckkraft. Bei 75 % (zuerst versucht) war nur der allerstaerkste
    # Kern undurchsichtig, der Rest blieb blass - die Icons wirkten
    # ausgewaschen statt gezeichnet. Die 32 % erhalten die Anti-
    # Aliasing-Raender als weiche Kante, ohne die Flaeche zu
    # ausdunnen.
    span = max(1.0, max(devs) * 0.32)
    hard = Image.new('L', (w, h), 0)
    data = hard.load()
    i = 0
    for yy in range(y0, y1):
        for xx in range(x0, x1):
            data[xx - x0, yy - y0] = 255 if devs[i] >= span else 0
            i += 1

    # Schliessen (MinFilter = verdunkeln, danach MaxFilter = aufhellen):
    # schliesst die LOECHTEN INNEN in den duennen Strichen. Ohne das
    # waren Stumm und WLAN zerrissen - die Symbole sind im Referenzfoto
    # nur 11 bis 14 px hoch, ihre Striche ein bis zwei Pixel, und ein
    # Pixel ohne Messpunkt darin ist ein Loch. Anschliessend leicht
    # weichzeichnen, damit die Kanten wieder Anti-Aliasing bekommen
    # statt zu bleiben wie ein Schwellwertbild.
    closed = hard.filter(ImageFilter.MinFilter(3)).filter(
        ImageFilter.MaxFilter(3))
    return closed.filter(ImageFilter.GaussianBlur(0.6))


def _ink_box(rgb, ref_w, y, tol, x0, x1, half=12):
    """Engster Kasten um die Tintenpixel einer Spaltengruppe.

    Zwei Fehler waren hier drin:

    * `min_hits=1` genuegt ein einziges verrauschtes Pixel pro Spalte,
      dann umfasst der Kasten den ganzen Ausschnitt (gemessene
      Iconfeld-Hoehe: 25 px, das ist genau das Fenster).
    * Es wurden nicht die tatsaechlich getroffenen Zeilen gesammelt,
      sondern das ganze Fenster, sobald eine Spalte ueberhaupt Tinte
      hatte. Damit war die Hoehe immer 2*half+1, unabhaengig vom
      Symbol.
    """
    rows_bg = {}
    hits_x, hits_y = [], []
    for x in range(max(0, x0), min(ref_w, x1)):
        ink_rows = []
        for yy in range(max(0, y - half), min(rgb.size[1], y + half + 1)):
            if _deviation(rgb, ref_w, x, yy, rows_bg) > tol:
                ink_rows.append(yy)
        if len(ink_rows) >= 2:
            hits_x.append(x)
            hits_y.extend(ink_rows)
    if not hits_x:
        return None, None, None, None
    return min(hits_x), min(hits_y), max(hits_x), max(hits_y)


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
    clock_text = '3:41'   # Uhrzeit, wie sie in der Referenz steht
    print(f'Referenz: {ref}  {im.size}')

    y, score = detect_band(im)
    print(f'Icon-Zeile: y={y}  Kontrast-Score={score:.3f}')
    if score < 0.01:
        sys.exit('Keine Symbolzeile erkannt. Ist das die Statusleiste?')

    rgb = im.convert('RGB')
    all_groups, right, tol, merge = detect_icon_groups(
        rgb.load(), rgb.width, rgb.height, y)
    print(f'Gefundene Spaltengruppen: {len(all_groups)}')
    for i, (a, b) in enumerate(all_groups):
        print(f'  {i}: x={a}..{b}  breite={b - a}')

    if len(right) < 4:
        sys.exit(f'Nur {len(right)} Symbole rechts erkannt, erwartet 4.')
    chosen = right[-4:]

    # Ausschnitt grosszuegig: +/- 12 Zeilen um die erkannte Zeile.
    #
    # Erster Versuch war +/- 5 (rgb.width // 90). Das hat Symbole
    # beschnitten, und zwar still: das WLAN reicht in der Referenz von
    # y=29 bis y=41, der Ausschnitt endete bei y=37. Es fehlten vier
    # Zeilen am unteren Rand des Fan-Symbols. In der fertigen
    # Komposition sah das nicht wie ein Abschneidefehler aus, sondern
    # wie ein falsches Symbol.
    #
    # Der Comment-Bereich wird spaeter ueber die Alphabox wieder
    # weggeschnitten, mehr Ausschnitt schadet also nicht.
    pad = 12

    # Die Deckkraft wird HIER berechnet, nicht erst beim Einfuegen in
    # den Store-Screenshot. Sie braucht den Hintergrund der ganzen
    # Referenzzeile; beim Einfuegen liegt nur die Kachel vor, und der
    # Himmel verlaufet innerhalb einer Kachel - eine mittlere Randfarbe
    # trifft daneben und die Kachel bleibt als grauer Kasten stehen.
    tiles = []
    for name, (a, b) in zip(ORDER, chosen):
        # Die Box muss EXAKT dem Ausschnitt entsprechen (rechts +1, weil
        # crop_cluster exklusiv schneidet) - sonst passt die Deckkraft
        # nicht auf die Kachel und putalpha wirft.
        box = (a - pad, y - pad, b + pad + 1, y + pad + 1)
        alpha = _alpha_for_tile(rgb, rgb.width, box, tol)
        tile = Image.new('RGBA', crop_cluster(rgb, a, b, y, pad).size,
                         (255, 255, 255, 0))
        tile.putalpha(alpha)
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
        # NUR der Dateiname, nie der volle Pfad: die Referenz ist ein
        # Foto vom Bildschirm des Nutzers und der Pfad enthaelt den
        # Benutzernamen. Das Repository ist oeffentlich.
        'source': ref.name,
        'sourceSize': list(im.size),
        'iconRowY': y,
        'padding': pad,
        'sprite': boxes,
        'spriteSize': [sprite.size[0], sprite.size[1]],
    }

    # Gemessene Proportionen, auf die die Bildbreite bezogen.
    #
    # Diese Zahlen sind das eigentliche Ergebnis der Analyse. Die
    # gezeichnete Fassung hatte den Cluster auf geratene "30 % der
    # Bildbreite" gesetzt und die Symbole auf 3,5 % Hoehe - beides zu
    # gross. Aus der Referenz kommen rund 2,3 % Hoehe und ein Cluster
    # von knapp 20 % Breite. Nachgebaut ist das nie 1:1, skaliert ist es
    # dagegen exakt: der Composer teilt die Bildbreite des Zielbildes
    # durch die Bildbreite der Referenz.
    #
    # Gemessen wird an den ERKANNTEN Gruppen, nicht an den
    # Sprite-Kacheln: deren Positionen enthalten das zusaetzliche
    # Padding und wuerden die Abstaende um genau diesen Betrag
    # verfaelschen (7,6 % statt 1,5 %).
    ref_w = im.size[0]

    # ECHTE Tintenkaesten messen, nicht die erkannten Spaltengruppen.
    #
    # Die Gruppen liefern nur x-Bereiche und eine Fensterhoehe von
    # 2*pad+1. Beides geht nicht in die Skalierung ein: der Ausschnitt
    # ist absichtlich gross, ein zu hohes Fenster macht die Symbole zu
    # klein. Gemessen wird nur ueber die eigene Spaltengruppe - mit
    # Nachbarspalten laufen die Kaesten ineinander (mute 343..365
    # statt 343..353).
    ink_boxes = {}
    for name, (a, b) in zip(ORDER, right):
        bx0, by0, bx1, by1 = _ink_box(rgb, ref_w, y, tol, a, b)
        ink_boxes[name] = ({} if bx0 is None else
                           {'w': bx1 - bx0 + 1, 'h': by1 - by0 + 1})
    heights = [v['h'] for v in ink_boxes.values() if v.get('h')]
    geom['iconBox'] = ink_boxes
    geom['iconHeightFraction'] = round(
        (max(heights) if heights else 2 * pad + 1) / ref_w, 5)
    geom['iconWidthFraction'] = {
        n: round(v['w'] / ref_w, 5) for n, v in ink_boxes.items() if v.get('w')}
    geom['padding'] = pad

    # Akku: Koerper und Kontaktstift getrennt messen. Der Stift war
    # "komisch lang" - er war mit dem Icon-Abstand gezeichnet, also
    # rund ein Drittel so breit wie der Koerper statt wie im Original
    # rund ein Elftel.
    #
    # Er hat keine eigene Spaltenluecke (x=431 Koerper, x=432 Stift),
    # gesucht wird deshalb nach Spalten mit kleinerer Tintenhoehe: der
    # Stift ist die schmale, flache Fortsetzung am rechten Rand.
    bat_a, bat_b = right[-1]
    bat_box = _ink_box(rgb, ref_w, y, tol, bat_a, bat_b)
    bat_h = (bat_box[3] - bat_box[1] + 1) if bat_box[0] is not None else 14
    rows_bg = {}
    col_h = []
    for xx in range(bat_a, bat_b + 1):
        ys = [yy for yy in range(max(0, y - 12), min(rgb.size[1], y + 13))
              if _deviation(rgb, ref_w, xx, yy, rows_bg) > tol]
        col_h.append((xx, (max(ys) - min(ys) + 1) if ys else 0))
    max_h = max((h for _x, h in col_h), default=bat_h)
    nub_cols = [x for x, h in col_h
                if 0 < h <= max_h * 0.75 and x > bat_a + bat_h]
    body_x1 = (min(nub_cols) - 1) if nub_cols else bat_b
    geom['battery'] = {
        'bodyWidthFraction': round((body_x1 - bat_a + 1) / ref_w, 5),
        'nubWidthFraction': round(max(0, bat_b - body_x1) / ref_w, 5),
        'nubHeightFraction': round(
            max((h for x, h in col_h if x in nub_cols), default=0) / ref_w, 5),
        'bodyHeightFraction': round(bat_h / ref_w, 5),
    }
    print(f'  Akku          Koerper {geom["battery"]["bodyWidthFraction"]*100:.2f} %'
          f' breit, Stift {geom["battery"]["nubWidthFraction"]*100:.2f} % breit')
    icon_w = {n: (b - a) for n, (a, b) in zip(ORDER, right)}
    gaps = [right[i + 1][0] - right[i][1] for i in range(len(right) - 1)]
    gap_px = sum(gaps) / max(1, len(gaps))

    # iconWidthFraction, iconHeightFraction, iconBox und battery stehen
    # bereits weiter oben - sie stammen aus den TINTENKAESTEN, nicht aus
    # den Spaltengruppen. Ein spaeteres Ueberschreiben mit der
    # Fensterhoehe (2*pad+1 = 25 px statt der echten 14) hat die Icons
    # auf 80 % ihrer gedachten Groesse geschrumpft.
    geom['gapFraction'] = round(gap_px / ref_w, 5)
    geom['clusterFraction'] = round(
        (sum(ink_boxes[n]['w'] for n in ORDER if ink_boxes[n].get('w'))
         + gap_px * (len(ORDER) - 1)) / ref_w, 5)
    geom['rightMarginFraction'] = round(
        (ref_w - right[-1][1]) / ref_w, 5)

    # Die Uhr mitmessen. Sie war der Grund, warum die Leiste auch nach
    # korrekten Icons nicht stimmte: ihre Groesse war geraten
    # (Schriftgroesse 3 % der Bildbreite), dabei sind es 5,49 % BREITE
    # und 2,53 % Hoehe - und die Referenzschrift ist sichtbar leichter
    # als eine fette Sans. Beides wird jetzt gemessen.
    clock = {}
    left_groups = [g for g in all_groups if g[0] < ref_w * 0.55]
    if left_groups:
        a, b = left_groups[0]

        def row_background(yy):
            """Mittlere Hintergrundfarbe der Zeile - dieselbe Mass, mit
            der auch die Icons erkannt werden. Ein einzelnes
            Hintergrundpixel taugt nicht: die Referenz ist ein Foto."""
            samples = range(0, ref_w, 7)
            n = len(samples)
            out = []
            for i in range(3):
                total = 0
                for xx2 in samples:
                    total += rgb.getpixel((xx2, yy))[i]
                out.append(total / n)
            return out

        hits_x, hits_y = [], []
        half = 8
        for yy in range(y - half, y + half + 1):
            bg_row = row_background(yy)
            for xx in range(a, b):
                p = rgb.getpixel((xx, yy))
                if sum(abs(p[i] - bg_row[i]) for i in range(3)) > 60:
                    hits_x.append(xx)
                    hits_y.append(yy)
        if hits_x:
            cw = max(hits_x) - min(hits_x) + 1
            ch = max(hits_y) - min(hits_y) + 1
            clock = {
                'widthFraction': round(cw / ref_w, 5),
                'heightFraction': round(ch / ref_w, 5),
                'leftFraction': round(min(hits_x) / ref_w, 5),
                'text': clock_text,
            }
    geom['clock'] = clock

    GEOMETRY.write_text(json.dumps(geom, indent=2), encoding='utf-8')
    print(f'Geometrie geschrieben: {GEOMETRY.relative_to(ROOT)}')
    if clock:
        print(f'  Uhr          {clock["widthFraction"]*100:.2f} % breit, '
              f'{clock["heightFraction"]*100:.2f} % hoch, '
              f'linker Rand {clock["leftFraction"]*100:.2f} %')
    print(f'  Icon-Hoehe      {geom["iconHeightFraction"]*100:.2f} % der Breite')
    for n in ORDER:
        print(f'  {n:<8} Breite   '
              f'{geom["iconWidthFraction"][n]*100:.2f} %')
    print(f'  Abstand         {geom["gapFraction"]*100:.2f} %')
    print(f'  Cluster gesamt  {geom["clusterFraction"]*100:.2f} %')
    print(f'  rechter Rand    {geom["rightMarginFraction"]*100:.2f} %')
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
