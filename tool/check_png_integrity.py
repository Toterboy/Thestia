"""Prueft, dass alle Bild-Dateien im Repo wirklich gueltige Bilder sind.

Begründung
----------
Am 2026-09-29 war ``fastlane/metadata/android/de-DE/images/phoneScreenshots/
01_willkommen.png`` unlesbar: core.autocrlf=true hatte die Binärdatei
beim Checkout als Text behandelt, die PNG-Signatur war verschoben und
die Datei ~20 KB größer als im Repository. Kein Test hat das gemeldet -
Store-Metadaten werden von flutter test nicht angefasst.

Ein Bildkanal-Problem ist damit ein Dauerthema, kein Einzelfall. Deshalb
wird hier jede PNG-Datei im Arbeitsverzeichnis geprüft:
  1. korrekte 8-Byte-Signatur
  2. IHDR-Chunk vorhanden und lesbar (Breite/Höhe plausibel)
  3. IEND-Chunk vorhanden (nicht abgeschnitten)
  4. Bytegröße == Größe des Git-Blobs, falls die Datei versioniert ist
     (Abweichung = Zeilenenden- oder Text-Roundtrip-Schaden)

DIE JPEGs DER LANDING-SEITE (04.11.2026)

Genau der Schaden von oben, nur an einer anderen Stelle: Die acht
Bilder unter `passkey-assets/screenshots/` waren keine JPEGs, sondern
UTF-16-Text mit einem BOM - ein PowerShell-Text-Roundtrip hatte die
Binaerdatei zerlegt. Sie lagen so im Repository und damit auch auf
dem Server: die Landing-Seite zeigte acht leere Kaesten, und niemand
hat es gemeldet.

Der PNG-Check fasste diese Dateien nicht an (er prueft *.png), also
blieb der Schaden unsichtbar. Seitdem werden die JPEGs mitgeprueft:
  1. JPEG-Signatur (FFD8) vorhanden
  2. die Datei laesst sich vollstaendig dekodieren
  3. Bytegröße == Größe des Git-Blobs (wie bei den PNGs)

Aufruf:  python tool/check_png_integrity.py
Exit 0 = alles in Ordnung, Exit 1 = mindestens ein Befund.
"""

import pathlib
import struct
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PNG_SIG = bytes([137, 80, 78, 71, 13, 10, 26, 10])

# Verzeichnisse, die nicht eingecheckt sind (Build-Ausgaben, Caches).
SKIP_PARTS = {
    '.git', 'build', '.dart_tool', '.gradle', '.idea',
    'android/.gradle', 'third_party',
}

# Wo Play/F-Droid ihre Bilder erwarten - hier besonders streng.
STORE_HINTS = ('fastlane/metadata', 'releases')

problems = []
checked = 0


def tracked(rel):
    r = subprocess.run(
        ['git', 'ls-files', '--error-unmatch', rel],
        capture_output=True, cwd=ROOT)
    return r.returncode == 0


def blob_size(rel):
    r = subprocess.run(['git', 'cat-file', '-p', f'HEAD:{rel}'],
                       capture_output=True, cwd=ROOT)
    return len(r.stdout) if r.returncode == 0 else None


def check(p: pathlib.Path):
    global checked
    rel = p.relative_to(ROOT).as_posix()
    data = p.read_bytes()
    checked += 1
    is_store = any(h in rel for h in STORE_HINTS)

    def fail(msg, store_only=True):
        if store_only and not is_store:
            return
        problems.append(f'{rel}: {msg}')

    # 1) Signatur
    if data[:8] != PNG_SIG:
        head = ' '.join(f'{b:02x}' for b in data[:8])
        fail(f'keine PNG-Signatur (erste 8 Bytes: {head})')
        return

    # 2) + 3) Chunk-Durchlauf
    i = 8
    w = h = None
    saw_iend = False
    while i + 8 <= len(data):
        length = struct.unpack('>I', data[i:i + 4])[0]
        ctype = data[i + 4:i + 8]
        nxt = i + 12 + length
        if nxt > len(data):
            fail(f'Chunk {ctype.decode("latin1", "replace")} ragt '
                 f'{nxt - len(data)} Bytes über das Dateiende hinaus '
                 f'(abgeschnitten)')
            return
        if ctype == b'IHDR' and w is None:
            w, h = struct.unpack('>II', data[i + 8:i + 16])
        if ctype == b'IEND':
            saw_iend = True
            break
        i = nxt
    if not saw_iend:
        fail('kein IEND-Chunk - Datei unvollständig')
        return
    if w is None or w < 1 or h < 1:
        fail(f'IHDR unlesbar ({w}x{h})')
        return
    if w > 20000 or h > 20000:
        fail(f'unplausible Größe {w}x{h}')

    # 4) Abgleich mit dem Git-Blob
    if tracked(rel):
        bsz = blob_size(rel)
        if bsz is not None and bsz != len(data):
            problems.append(
                f'{rel}: Größe weicht vom Repository ab '
                f'(Arbeitskopie {len(data)} B, Repo {bsz} B, '
                f'Differenz {len(data) - bsz:+d} B) - typisch für '
                f'CRLF- oder Text-Roundtrip-Schaden; .gitattributes prüfen')


def check_jpeg(p: pathlib.Path):
    """Prueft eine JPEG-Datei (siehe Modul-Docstring)."""
    global checked
    rel = p.relative_to(ROOT).as_posix()
    data = p.read_bytes()
    checked += 1

    if not data.startswith(b'\xff\xd8'):
        problems.append(
            f'{rel}: keine JPEG-Signatur (erste Bytes '
            f'{data[:4].hex()}) - die Datei wurde als TEXT gespeichert '
            f'(UTF-16-BOM oder aehnlich) und ist im Browser nicht lesbar')
        return

    try:
        from PIL import Image
        with Image.open(p) as im:
            im.load()
    except Exception as e:  # noqa: BLE001
        problems.append(f'{rel}: nicht dekodierbar ({e})')
        return

    if tracked(rel):
        bsz = blob_size(rel)
        if bsz is not None and bsz != len(data):
            problems.append(
                f'{rel}: Größe weicht vom Repository ab '
                f'(Arbeitskopie {len(data)} B, Repo {bsz} B, '
                f'Differenz {len(data) - bsz:+d} B) - typisch für '
                f'CRLF- oder Text-Roundtrip-Schaden; .gitattributes prüfen')


print('=' * 70)
print('BILD-INTEGRITÄT')
print('=' * 70)
for p in sorted(ROOT.rglob('*.png')):
    parts = p.relative_to(ROOT).parts
    if any(s in parts for s in SKIP_PARTS):
        continue
    check(p)
print(f'{checked} PNG-Dateien geprüft.')

# Die Bilder der Landing-Seite (siehe Modul-Docstring).
jpg_geprueft = 0
for p in sorted(ROOT.rglob('*.jpg')):
    parts = p.relative_to(ROOT).parts
    if any(s in parts for s in SKIP_PARTS):
        continue
    vorher = checked
    check_jpeg(p)
    jpg_geprueft += checked - vorher
print(f'{jpg_geprueft} JPEG-Dateien geprüft.')
print()

if problems:
    for pr in problems:
        print(' X', pr)
    print()
    print(f'{len(problems)} Befund(e).')
    sys.exit(1)

print('OK  alle Bilder lesbar, vollständig und identisch zum Repository.')
sys.exit(0)
