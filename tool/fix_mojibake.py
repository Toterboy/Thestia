"""Repariert die durch PowerShell-Round-Trips zerstoerte UTF-8-Kodierung.

Ursache
-------
In PowerShell 5.1 liest `Get-Content -Raw` eine UTF-8-Datei OHNE BOM als
System-Codepage (cp1252), nicht als UTF-8. Schreibt man das Ergebnis
mit `Set-Content -Encoding UTF8` zurueck, ist jeder Umlaut doppelt
kodiert: aus "u-umlaut" (UTF-8 C3 BC) wird erst "A-circumflex" +
"one-quarter" (cp1252-Lesung) und dann wieder UTF-8-Byte fuer Byte
geschrieben. Die Datei enthaelt fortan U+00C3 U+00BC statt U+00FC.

Deshalb ist `Set-Content -Encoding UTF8` fuer Dateien mit Umlauten
grundsaetzlich der falsche Weg. Korrekt waere `Get-Content -Raw
-Encoding UTF8`. Oder gar kein Round-Trip: der Editor bzw. das
Schreibwerkzeug gehoert an die Datei, nicht die Shell.

Wirkung
-------
Der Defekt fiel erst bei der Bildschau der Feature Graphic auf: der
Text auf dem Banner stand als "verschlA-circumflex-one-quarter-sselt".
In einem Python-String faellt das nicht auf, solange niemand die
Ausgabe ansieht - deshalb dieser Checker.

Wirkung des Repairs
-------------------
Der Schritt ist exakt umkehrbar: cp1252 kodieren, dann als UTF-8
lesen. Zeichen, die cp1252 nicht kennt, werden uebersprungen und
gemeldet statt still zu verlieren.
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGETS = [
    'tool/make_feature_graphic.py',
    'tool/make_play_icon.py',
    'tool/check_migrations_sql.py',
    'tool/check_migrations_sql_paths_selftest.py',
    'tool/check_passkey_assetlinks.py',
]

# Zeichen, die im Fehlerbild typischerweise auftreten, ausschliesslich
# als Codepoint. Nicht als Literal: genau die Dateien, die hier
# entstehen, werden von der Shell bearbeitet, die literale Nicht-ASCII-
# Zeichen wuerde zuverlaessig zerstoeren. chr() ist gegen jede
# Kodierungsebene immun - das ist der eigentliche Fix, nicht die
# Reparatur danach.
SUSPECTS = {chr(0x00C2), chr(0x00C3), chr(0x00E2)}   # A^, A-tilde, a^
# UTF-8-Fortsetzungsbytes. Ein Mojibake-Paar besteht aus einem
# Verdachtszeichen (U+00C2/C3/E2, lateinisch-1-Kodierung der
# UTF-8-Startbytes C2/C3/E2) gefolgt von einem Byte im Bereich
# 0x80-0xBF. Die Run-Erkennung darf deshalb nicht bei der
# Verdachtsliste stoppen - U+00BC etwa ist selbst harmlos, gehoert aber
# untrennbar zum U+00C3 davor. Ohne diesen Bereich war jede Run
# Laenge 1 und die Dekodierung schlug bei jedem Zeichen fehl.
CONTINUATION = {chr(c) for c in range(0x80, 0xC0)}
REPLACEMENT = chr(0xFFFD)


def looks_broken(text: str) -> bool:
    return any(c in text for c in SUSPECTS) or REPLACEMENT in text


def repair(text: str) -> tuple[str, int, list[str]]:
    """Mojibake-Zeichenketten zusammenhaengend dekodieren.

    Wichtig: nicht zeichenweise. Das Fehlerbild fuer "u-umlaut" besteht
    aus ZWEI Zeichen (U+00C3 U+00BC). UTF-8 ist byteorientiert, ein
    einzelnes U+00C3 ist eine unvollstaendige Sequenz und laesst sich
    nicht dekodieren - der erste Versuch scheiterte deshalb an jedem
    Zeichen einzeln. Deshalb werden maximal zusammenhaengende Ketten
    aus Verdachtszeichen als Block ueber cp1252 nach UTF-8 gewandelt.
    """
    out: list[str] = []
    fixed = 0
    problems: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] in SUSPECTS:
            j = i
            while j < n and (text[j] in SUSPECTS or text[j] in CONTINUATION):
                j += 1
            run = text[i:j]
            try:
                decoded = run.encode('cp1252').decode('utf-8')
                out.append(decoded)
                fixed += len(run)
            except (UnicodeEncodeError, UnicodeDecodeError) as e:
                out.append(run)
                problems.append(f'U+{ord(run[0]):04X}x{len(run)} ({type(e).__name__})')
            i = j
        else:
            out.append(text[i])
            i += 1
    return ''.join(out), fixed, problems


def main() -> int:
    print('=' * 72)
    print('MOJIBAKE-REPARATUR')
    print('=' * 72)
    for rel in TARGETS:
        p = ROOT / rel
        if not p.exists():
            print(f'\n  {rel}: fehlt, uebersprungen')
            continue
        raw = p.read_bytes()
        had_bom = raw[:3] == b'\xef\xbb\xbf'
        text = raw.decode('utf-8-sig')
        if not looks_broken(text):
            print(f'\n  {rel}: unauffaellig - nicht angefasst')
            continue
        fixed_text, n, problems = repair(text)
        still = looks_broken(fixed_text)
        print(f'\n  {rel}')
        print(f'    BOM:              {"ja (wird entfernt)" if had_bom else "nein"}')
        print(f'    reparierte Zeichen: {n}')
        if problems:
            print(f'    nicht reparierbar: {len(problems)}x {problems[:5]}')
        print(f'    danach noch Fehler: {"JA" if still else "nein"}')
        if still:
            print('    X Datei bleibt beschaedigt - nicht geschrieben.')
            return 1
        # Ohne BOM schreiben: der BOM war eine Nebenwirkung desselben
        # PowerShell-Round-Trips und stoert Python nicht, aber er macht
        # die Datei fuer andere Werkzeuge unsichtbar kaputt.
        p.write_text(fixed_text, encoding='utf-8', newline='\n')
        print('    geschrieben (UTF-8, ohne BOM)')
    print()
    return 0


if __name__ == '__main__':
    sys.exit(main())
