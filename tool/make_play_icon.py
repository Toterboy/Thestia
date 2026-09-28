"""Erzeugt die Play-konformen Icon-Dateien aus dem vorhandenen Master-Icon.

Play verlangt fuer das Store-Icon:
  - exakt 512 x 512 px
  - 32-Bit-PNG (RGBA)
  - maximal 1024 KB
  - sRGB, keine abgerundeten Ecken (Play maskiert selbst), kein Schatten

Im Repo lag ein 1254x1254-Icon mit 1.535.910 Byte - groesser in beiden
Punkten. Play lehnt das beim Upload ab, es ist also ein echter Blocker
und keine Formalie.

Qualitaet: herunterskalieren statt zuschneiden, damit das Motiv nicht
verzerrt. Quelle ist quadratisch, deshalb passt 512x512 ohne Beschnitt.
Wenn das Ergebnis trotzdem ueber 1024 KB liegt, wird in Schritten
quantisiert - das Icon ist ein flaches Vektor-Motiv, die Quantisierung
faellt nicht auf.
"""
from __future__ import annotations

import io
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = 512
MAX_BYTES = 1024 * 1024  # 1024 KB
# Quelle und Ziel duerfen NICHT dieselbe Datei sein. Im ersten Entwurf
# stand beides auf fastlane/.../icon.png - beim zweiten Lauf las das
# Skript dann sein eigenes 512er-Ergebnis ein und verarbeitete das
# weiter, statt es zu erkennen. Die Master-Datei liegt deshalb
# unberuehrt unter assets/images/ und wird nie geschrieben.
MASTER = pathlib.Path('assets/images/thestia_icon_base.png')
TARGETS = [
    'fastlane/metadata/android/de-DE/images/icon.png',
    'fastlane/metadata/android/en-US/images/icon.png',
]
# Das Store-Icon im Repo war 1254x1254 - ein groesserer, eigens fuer den
# Store geschnittener Satz. Er liegt in der Git-Historie, ist aber kein
# separates Arbeitsmaster. Deshalb wird die Quelle bevorzugt aus dem
# Repo-Stand des Ziels gelesen, solange sie noch zu gross ist.
STORE_SOURCE = TARGETS[0]


def quantize_until_fits(img: Image.Image, budget: int) -> tuple[bytes, str]:
    """PNG unterhalb des Budgets, bevorzugt echtes RGBA.

    Reihenfolge bewusst so: zuerst unquantisiertes RGBA, weil Play
    ausdruecklich ein "32-bit PNG (with alpha)" verlangt. Ein
    Paletten-PNG (Modus P) ist zwar kleiner, aber die Farbtabelle ist
    keine 32-Bit-RGBA-Bittebene - das ist eine Auslegung, die man beim
    Upload nicht braucht, wenn das Budget ohnehin reicht. Das flache
    Vektor-Motiv braucht 512x512 RGBA nur ~100 KB.

    Erst wenn das Budget gerissen wird, wird quantisiert. Fuer RGBA
    verlangt Pillow FASTOCTREE; MEDIANCUT ist nur fuer Bilder ohne
    Alphakanal zulaessig und bricht mit ValueError ab.
    """
    buf = io.BytesIO()
    img.save(buf, format='PNG', optimize=True)
    if buf.tell() <= budget:
        return buf.getvalue(), 'RGBA, unquantisiert'

    for colors in (256, 128, 64, 32):
        buf = io.BytesIO()
        img.quantize(colors=colors, method=Image.FASTOCTREE).save(
            buf, format='PNG', optimize=True)
        if buf.tell() <= budget:
            return buf.getvalue(), f'Palette, {colors} Farben, FASTOCTREE'

    buf = io.BytesIO()
    img.convert('P', palette=Image.ADAPTIVE, colors=64).save(
        buf, format='PNG', optimize=True, bits=4)
    if buf.tell() <= budget:
        return buf.getvalue(), '4-Bit-Palette (Notfall)'
    return buf.getvalue(), 'NICHT EINHALTBAR'


def pick_source() -> tuple[pathlib.Path, str]:
    """Quelle waehlen und begruenden.

    Bevorzugt wird das Store-Icon, solange es noch groesser als das Ziel
    ist - das ist der eigenstaendig geschnittene Store-Satz, den man
    nicht durch das In-App-Motiv ersetzen sollte. Ist es bereits 512 oder
    kleiner, wurde es vermutlich schon hierher erzeugt; dann greift das
    unbearbeitete In-App-Master, und der Aufruf ist gekennzeichnet.
    """
    store = ROOT / STORE_SOURCE
    master = ROOT / MASTER
    if store.exists():
        with Image.open(store) as im:
            if im.width > TARGET or im.height > TARGET:
                return store, f'Store-Icon ({im.width}x{im.height}), ueber dem Ziel'
            note = f'Store-Icon ist bereits {im.width}x{im.height} - vermutlich selbst erzeugt'
    else:
        note = 'Store-Icon fehlt'
    if master.exists():
        with Image.open(master) as im:
            return master, f'In-App-Master {MASTER} ({im.width}x{im.height}) - {note}'
    raise SystemExit(f'FEHLER: keine Quelle gefunden ({STORE_SOURCE} und {MASTER}).')


def main() -> int:
    src, why = pick_source()
    with Image.open(src) as im:
        original = (im.width, im.height, src.stat().st_size)
        im = im.convert('RGBA')
        print('=' * 70)
        print('PLAY-ICON')
        print('=' * 70)
        print(f'  Quelle:  {src.name}  {original[0]}x{original[1]}, {original[2]:,} Byte')
        print(f'  Grund:   {why}')

        if im.width != im.height:
            print('  X Quelle ist nicht quadratisch - Beschnitt noetig, '
                  'bitte manuell entscheiden.')
            return 1

        out = im.resize((TARGET, TARGET), Image.LANCZOS)
        data, how = quantize_until_fits(out, MAX_BYTES)
        kb = len(data) / 1024
        print(f'  Ziel:    {TARGET}x{TARGET}, {len(data):,} Byte ({kb:.0f} KB)')
        print(f'  Kodierung: {how}')
        if len(data) > MAX_BYTES:
            print('  X Budget trotz Quantisierung gerissen - bitte manuell '
                  'nachbearbeiten.')
            return 1

        for rel in TARGETS:
            p = ROOT / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
            print(f'  OK  {rel}')

    # Gegenprobe: Datei wirklich lesbar und in den Grenzen
    print()
    print('  Gegenprobe:')
    ok = True
    for rel in TARGETS:
        p = ROOT / rel
        with Image.open(p) as chk:
            size_ok = chk.size == (TARGET, TARGET)
            bytes_ok = p.stat().st_size <= MAX_BYTES
            mode_ok = chk.mode == 'RGBA'
            print(f'    {rel}: {chk.size[0]}x{chk.size[1]}  '
                  f'{p.stat().st_size:,} B  Modus {chk.mode}  '
                  f'-> {"OK" if size_ok and bytes_ok and mode_ok else "FEHLER"}')
            ok &= size_ok and bytes_ok and mode_ok
    print()
    print('OK: Icon erfuellt 512x512, 32-Bit-PNG (RGBA), <=1024 KB.' if ok
          else 'FEHLER: Grenzen nicht eingehalten.')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
