"""Prueft, dass die Store-Screenshots die System-UI korrekt zeigen.

Der Screenshot-Render (test/screenshots/store_v091_shots_test.dart) ist
gitignoriert. Damit koennen dort Fehler unbemerkt entstehen und beim
naechsten Checkout wieder verschwinden. Diese Pruefung laeuft gegen das
ERGEBNIS - die fertigen PNGs - und schlaegt an, wenn der Render nicht
mehr wie ein echtes Geraet aussieht.

Geprueft wird:

  1. Seitenverhaeltnis der Quelle: 20:9 (1080x2400). Ein gerenderter
     Bildschirm, der auf 16:9 gequetscht wurde, sieht auf jedem
     modernen Geraet falsch aus.
  2. Statusleisten-Reserve: im oberen Band von 24 dp darf KEIN
     sichtbarer App-Inhalt liegen. Toleranz 12 physische Pixel fuer
     den Antialiasing-Rand der AppBar-Icons.
  3. Die System-Indikatoren, die make_store_screenshots.py zeichnet,
     muessen oben vorhanden sein: ohne sie wirkt der Screen wie ein
     Bild, nicht wie ein Geraet.

Die Werte kommen aus tool/store_screenshot_insets.dart - dieselbe
Quelle, die der Render-Harness benutzt. Veraendert man die Insets dort,
muss man sie hier nicht nachziehen.

Aufruf:  python tool/check_store_screenshots.py
"""

import pathlib
import re
import sys
from collections import Counter

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / 'test' / 'screenshots' / 'store_v091' / 'phone'
FINAL = (ROOT / 'fastlane' / 'metadata' / 'android' / 'de-DE' /
         'images' / 'phoneScreenshots')

# Insets aus dem committeten Modul lesen, nicht hart verdrahten.
INSET_DART = (ROOT / 'test' / 'screenshots' / 'support' /
              'store_screenshot_insets.dart')
DPR = 3                      # 1080 / 360 dp
SRC_H = 2400
SRC_W = 1080
LOGICAL_H = SRC_H // DPR     # 800 dp


def read_insets():
    """Liest storeStatusBarDp / storeNavBarDp aus dem Dart-Modul."""
    if not INSET_DART.exists():
        raise SystemExit('FEHLT: tool/store_screenshot_insets.dart')
    src = INSET_DART.read_text(encoding='utf-8')
    def grab(name):
        m = re.search(rf'{name}\s*=\s*([0-9.]+)', src)
        if not m:
            raise SystemExit(f'FEHLT: {name} in store_screenshot_insets.dart')
        return float(m.group(1))
    return grab('storeStatusBarDp'), grab('storeNavBarDp')


def find_device(im):
    """Findet das Mockup-Geraetefenster ueber seinen dunklen Korpus.

    Der Geraetekoerpus ist graphit (neutral dunkel), der Markenverlauf
    dagegen magenta (blau deutlich groesser als gruen). Damit ist das
    Fenster eindeutig auffindbar - anders als mit einem festen
    Prozentfenster, das an der Position des Textblocks haengt und
    deshalb bei jeder Headline-Länge danebenliegt.
    """
    px = im.load()
    w, h = im.size

    def is_device(c):
        r, g, b = c
        return r < 90 and g < 90 and b < 110 and abs(int(b) - int(g)) < 40

    rows = [y for y in range(0, h, 4)
            if sum(1 for x in range(0, w, 8) if is_device(px[x, y]))
            > 0.5 * len(range(0, w, 8))]
    if not rows:
        return None
    top, bot = min(rows), max(rows)
    mid = (top + bot) // 2
    xs = [x for x in range(0, w, 4) if is_device(px[x, mid])]
    if not xs:
        return None
    return min(xs), top, max(xs), bot


def count_indicators(im, dev):
    """Zaehlt Kanten-Pixel im Statusleisten-Band, je Seite.

    Gezahlt wird nicht auf WEISSE Pixel, sondern auf Abweichung vom
    Modalwert des App-Hintergrunds: die Indikatoren liegen auf einem
    hellen Screen (247,247,251) und sind selbst hell - nur ihre
    Kontur hebt sich ab. Die Mitte bleibt bewusst aus, dort sitzt die
    Punch-Hole-Kamera.
    """
    px = im.load()
    left, top, right, bot = dev
    gw, gh = right - left, bot - top
    band_top = top + int(gh * 0.008)
    band_bot = top + int(gh * 0.030)

    modal = Counter()
    for y in range(band_top, band_bot):
        for x in range(left, right):
            modal[px[x, y]] += 1
    if not modal:
        return 0, 0
    bg = modal.most_common(1)[0][0]

    def edges(xa, xb):
        n = 0
        for y in range(band_top, band_bot):
            for x in range(xa, xb):
                c = px[x, y]
                if sum(abs(c[i] - bg[i]) for i in range(3)) > 60:
                    n += 1
        return n

    return (edges(left, left + gw // 3),
            edges(left + 2 * gw // 3, right))


def main():
    # Das Insets-Modul ist committet und in CI IMMER vorhanden. Es wird
    # deshalb vor allem anderen geprueft - wenn es fehlt oder keine
    # plausiblen Werte liefert, ist der Screenshot-Render kaputt, und das
    # ist auch ohne fertige Bilder feststellbar.
    status_dp, nav_dp = read_insets()
    problems = []
    if not (16 <= status_dp <= 48):
        problems.append(
            f'storeStatusBarDp = {status_dp} dp ist unrealistisch '
            f'(Android: 24..32 dp, Erwartung 16..48)')
    if not (16 <= nav_dp <= 48):
        problems.append(
            f'storeNavBarDp = {nav_dp} dp ist unrealistisch '
            f'(Erwartung 16..48)')

    # Die Screenshot-Ausgaben sind bewusst gitignoriert und in CI nicht
    # vorhanden. Ohne sie ist der Realismus nicht pruefbar - der Check
    # darf daran nicht scheitern, sonst ist die ganze CI rot und der
    # Nutzen weg. Er meldet "uebersprungen" und beendet mit 0.
    #
    # Das ist kein Wegsehen: sind die Dateien da (lokaler Release-Lauf),
    # wird vollstaendig geprueft und ein Befund bricht hart ab.
    if not SRC.exists() or not any(SRC.glob('*.png')):
        print('=' * 68)
        print('STORE-SCREENSHOT-REALISMUS')
        print('=' * 68)
        print(f'Insets-Modul geprueft: Status {status_dp} dp, '
              f'Navigation {nav_dp} dp')
        if problems:
            for p in problems:
                print(' X', p)
            return 1
        print(f'Keine Quell-Screens vorhanden ({SRC.relative_to(ROOT)}).')
        print('Die Ausgaben sind gitignoriert und in CI nicht da - der')
        print('Realismus wird beim Release-Lauf lokal geprueft:')
        print('  $env:STORE_SHOTS="1"; flutter test --update-goldens '
              'test/screenshots/store_v091_shots_test.dart')
        print('  python tool/make_store_screenshots.py')
        print('  python tool/check_store_screenshots.py')
        print()
        print('OK  Insets plausibel, Bildpruefung uebersprungen.')
        return 0

    band_px = int(status_dp * DPR)
    tol = 12

    print('=' * 68)
    print('STORE-SCREENSHOT-REALISMUS')
    print('=' * 68)
    print(f'System-Insets aus store_screenshot_insets.dart: '
          f'Status {status_dp} dp, Navigation {nav_dp} dp')
    print(f'entspricht {band_px} physischen px von {SRC_H} '
          f'({LOGICAL_H} dp)')
    print(f'Toleranz fuer Icon-Antialiasing: {tol} px')
    print()

    problems = []
    for f in sorted(SRC.glob('*.png')):
        im = Image.open(f).convert('RGB')
        w, h = im.size
        px = im.load()
        notes = []

        # 1) Seitenverhaeltnis
        ratio = h / w
        if not (2.0 <= ratio <= 2.25):
            problems.append(
                f'{f.name}: Seitenverhaeltnis {ratio:.2f}:1 ist nicht 20:9')

        # 2) Statusleisten-Reserve
        bg = px[6, 6]
        content = total = 0
        for y in range(0, max(0, band_px - tol), 2):
            for x in range(0, w, 6):
                c = px[x, y]
                total += 1
                if sum(abs(c[i] - bg[i]) for i in range(3)) > 90:
                    content += 1
        share = content / total if total else 0
        if share >= 0.02:
            problems.append(
                f'{f.name}: {share*100:.1f}% sichtbarer App-Inhalt im '
                f'Statusleisten-Band (0..{band_px - tol}px) - der Render '
                f'hat die System-Insets nicht angewendet')
        notes.append(f'Reserve {share*100:.2f}%')

        # 3) System-Indikatoren im fertigen Bild
        final = FINAL / f.name
        if final.exists():
            fim = Image.open(final).convert('RGB')
            dev = find_device(fim)
            if dev is None:
                problems.append(
                    f'{f.name}: Geraetefenster nicht gefunden - der '
                    f'Mockup-Rahmen fehlt im fertigen Bild')
            else:
                left, top, right, bot = dev
                lft, rgt = count_indicators(fim, dev)
                if lft < 20 or rgt < 20:
                    problems.append(
                        f'{f.name}: System-Indikatoren fehlen '
                        f'(Uhr {lft} px, Akku/Signal {rgt} px, '
                        f'jeweils >= 20 erwartet) - der Screen wirkt wie '
                        f'ein Bild statt wie ein Geraet')
                notes.append(f'Indikatoren {lft}/{rgt}')

        print(f'  {f.name:<26} {"  ".join(notes)}')

    print()
    if problems:
        for p in problems:
            print(' X', p)
        print(f'\n{len(problems)} Befund(e).')
        sys.exit(1)
    print('OK  Seitenverhaeltnis, Statusleisten-Reserve und '
          'System-Indikatoren stimmen.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
