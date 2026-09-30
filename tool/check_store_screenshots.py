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


def find_screen(im):
    """Findet die abgerundete App-Kachel im fertigen Bild.

    v0.9.2: Es gibt kein Geraet-Mockup mehr, sondern nur noch die
    abgerundete App-Kachel auf dem Markenverlauf.

    Die Kachel ist NEUTRAL hell (Summe > 560), der Verlauf gesaettigt
    (Summe deutlich niedriger) und der Text weiss (Summe sehr hoch,
    aber nur in schmalen Zeilen).

    Ein reiner Schwellwert auf "helle Zeile" reicht nicht: bei
    04_anpassen ist die Subline zweizeilig, und die weisse Schrift
    ueberschreitet die Schwelle, sobald genug Buchstaben in einer Zeile
    stehen. Deshalb wird nach der ERSTEN Zeile gesucht, auf der ein
    heller Lauf ueber mehr als 45% der Breite laeuft - Text erfasst
    keine 45% contigu, die Kachel sehr wohl.
    """
    px = im.load()
    w, h = im.size
    cols = list(range(0, w, 6))
    best = None
    for y in range(int(h * 0.15), int(h * 0.80)):
        light = sum(1 for x in cols if sum(px[x, y]) > 560)
        frac = light / len(cols)
        # Erste breite helle Zeile, danach noch zwei bestaetigen: die
        # Kachel ist ein Block, Text ist es nicht.
        if frac > 0.45:
            if best is None:
                best = y
        elif best is not None:
            if y - best >= 2:
                return best
            best = None
    return best


def find_screen_x(im, top):
    """Horizontale Ausdehnung der Kachel, gemessen auf einer Zeile drin."""
    px = im.load()
    w, h = im.size
    y = top + int((h - top) * 0.25)
    xs = [x for x in range(0, w, 2) if sum(px[x, y]) > 560]
    return (min(xs), max(xs)) if xs else None


def count_indicators(im, top, left, right):
    """Prueft, ob die System-Symbole im Statusleisten-Band sichtbar sind.

    Bewusst KEIN Zaehlen nach Seiten und KEINE Modalsuche. Die erste
    Fassung versuchte, Uhr und Akku getrennt zu zaehlen und produzierte
    damit drei Wertegleichungen ohne Aussagekraft: die genaue Position
    haengt an Kachelbreite, Radius und Bildhoehe, und jede Tabelle
    darin war geraten statt gemessen - sieflagte korrekt gezeichnete
    Symbole als fehlend.

    Stattdessen ein Nachweis, der wirklich etwas prueft: im Band muss
    es DUNKLE Pixel geben. Die App-Oberflaeche ist hell (247,247,251),
    die System-Symbole sind deckend dunkel (60,52,66). Zaehlt werden
    nur Pixel deutlich unterhalb der App-Helligkeit, in beiden
    Randbereichen zusammen. Das ist unabhaengig davon, ob gerade die
    Uhr oder der Akku links steht.
    """
    px = im.load()
    tile_h = (right - left) * 2400 / 1080
    band_top = top + int(tile_h * 0.020)
    band_bot = top + int(tile_h * 0.036)

    dark = 0
    for y in range(band_top, band_bot):
        for x in range(left + 20, right - 20):
            r, g, b = px[x, y][:3]
            if r < 180 and g < 180 and b < 180:
                dark += 1
    return dark


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
            top = find_screen(fim)
            if top is None:
                problems.append(
                    f'{f.name}: abgerundete App-Kachel nicht gefunden - '
                    f'das fertige Bild scheint kein Verlauf plus '
                    f'App-Screen zu sein')
            else:
                xs = find_screen_x(fim, top)
                if xs is None:
                    problems.append(
                        f'{f.name}: Kacheloberkante bei y={top} gefunden, '
                        f'Ausdehnung aber nicht messbar')
                else:
                    left, right = xs
                    dark = count_indicators(fim, top, left, right)
                    if dark < 60:
                        problems.append(
                            f'{f.name}: keine System-Symbole in der '
                            f'Statusleiste ({dark} dunkle Pixel, >= 60 '
                            f' erwartet) - der Screen wirkt wie ein Bild '
                            f'statt wie ein Geraet')
                    notes.append(f'Symbole {dark}')

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
