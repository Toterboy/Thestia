"""Findet Mojibake in Textdateien des Repos.

Mojibake entsteht, wenn eine UTF-8-Datei ohne BOM als System-Codepage
(cp1252) gelesen und wieder als UTF-8 geschrieben wird. In Windows
PowerShell 5.1 ist das der Normalfall bei

    (Get-Content -Raw) | Set-Content -Encoding UTF8

Korrekt waere Get-Content -Raw -Encoding UTF8, oder man fasst die Datei
gar nicht ueber die Shell an.

Warum ein eigener Checker noetig ist
------------------------------------
Der Defekt faellt im Quelltext nicht auf. In tool/make_feature_graphic.py
stand woertlich `E2E-verschlA-circumflex-one-quarter-sselt` in einem
Python-String - der Code lief, die Tests waren gruen, nichts hat
gemeckelt. Sichtbar wurde es erst auf dem gerenderten Play-Banner, in
dem plötzlich "verschlÃ¼sselt" stand. Eine Fehlerklasse, die nur im
Artefakt auftaucht, braucht eine Pruefung an der Quelle.

Alle gesuchten Zeichen sind als Codepoint notiert, nicht als Literal:
sonst wuerde genau diese Datei beim Schreiben durch dieselbe Shell
zerstoert, die sie diagnostizieren soll.
"""
from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUFFIXES = {'.py', '.md', '.dart', '.yml', '.yaml', '.toml', '.txt', '.sql',
            '.json', '.html', '.properties', '.gradle', '.kts', '.ps1', '.cfg'}
SKIP = {'build', '.git', '.dart_tool', 'node_modules', 'releases', 'third_party'}

# U+00C2, U+00C3, U+00E2 sind die cp1251/cp1252-Umschrift der
# UTF-8-Startbytes C2, C3, E2. Fehlt danach ein Fortsetzungsbyte
# (0x80-0xBF), ist es ein echter Treffer; folgt eines, ist es fast
# sicher Mojibake eines Mehrbyte-Zeichens.
LEAD = {chr(0xC2), chr(0xC3), chr(0xE2)}
CONT = {chr(c) for c in range(0x80, 0xC0)}
REPL = chr(0xFFFD)


def inspect(text: str) -> list[tuple[int, str]]:
    """Zeilen mit Mojibake-Spuren: (Zeilennummer, Beispielkette)."""
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        for j, ch in enumerate(line):
            if ch in LEAD:
                k = j
                while k < len(line) and line[k] in CONT:
                    k += 1
                run = line[j:k]
                # Versuch der Rueckdekodierung: gelingt sie, war es
                # Mojibake. Schlaegt sie fehl, ist es ein harmloses
                # Zeichen wie "a-circumflex" in spanischem Text.
                try:
                    decoded = run.encode('cp1252').decode('utf-8')
                except (UnicodeEncodeError, UnicodeDecodeError):
                    continue
                hits.append((i, f'U+{ord(ch):04X} -> {decoded!r}'))
                break
            if ch == REPL:
                hits.append((i, 'U+FFFD replacement character'))
                break
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--skip-known', action='store_true',
                    help='Dateien auslassen, die die Fehlzeichen absichtlich '
                         'enthalten (Pruefmittel und Dokumentation)')
    args = ap.parse_args()

    # Ausschlussliste aus dem Reparaturskript beziehen, damit beide
    # Werkzeuge dieselbe Quelle truth. Zweimal getippte Ausschlusslisten
    # driften auseinander - und eine zu weite ausschliesst echte Fehler.
    known: set[str] = set()
    prefix_excluded = None
    if args.skip_known:
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            'fixmoji', pathlib.Path(__file__).resolve().parent / 'fix_mojibake.py')
        mod = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(mod)
            known = set(mod.EXCLUDE_FILES)
            prefix_excluded = mod.excluded
        except Exception:  # noqa: BLE001
            print('WARNUNG: Ausschlussliste nicht ladbar, pruefe alle Dateien.')

    print('=' * 72)
    print('MOJIBAKE-CHECK')
    print('=' * 72)
    by_file: dict[str, list[tuple[int, str]]] = {}
    scanned = 0
    for p in sorted(ROOT.rglob('*')):
        if not p.is_file() or p.suffix.lower() not in SUFFIXES:
            continue
        if any(part in SKIP for part in p.parts):
            continue
        rel = p.relative_to(ROOT).as_posix()
        if rel in known:
            continue
        if prefix_excluded is not None and prefix_excluded(rel):
            continue
        try:
            text = p.read_text(encoding='utf-8-sig')
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        hits = inspect(text)
        if hits:
            by_file[rel] = hits

    print(f'\n{scanned} Textdateien geprueft.'
          + (f' ({len(known)} mit absichtlichen Fehlzeichen ausgenommen)'
             if known else ''))
    if not by_file:
        print('\nOK: keine Mojibake-Spuren.')
        return 0
    total = sum(len(v) for v in by_file.values())
    print(f'\n{total} Fundstellen in {len(by_file)} Datei(en):\n')
    for f, hits in by_file.items():
        print(f'  {f}  ({len(hits)}x)')
        for i, detail in hits[:4]:
            print(f'    Zeile {i}: {detail}')
        if len(hits) > 4:
            print(f'    ... und {len(hits) - 4} weitere')
        print()
    print('Reparatur: python tool/fix_mojibake.py')
    return 1


if __name__ == '__main__':
    sys.exit(main())
