"""Repariert die durch PowerShell-Round-Trips oder fremde Editoren
zerstoerte UTF-8-Kodierung im Repo.

URSACHE
-------
In PowerShell 5.1 liest `Get-Content -Raw` eine UTF-8-Datei OHNE BOM als
System-Codepage (cp1252), nicht als UTF-8. Schreibt man das Ergebnis
mit `Set-Content -Encoding UTF8` zurueck, ist jeder Umlaut doppelt
kodiert: aus "u-umlaut" (UTF-8 C3 BC) wird erst "A-circumflex" +
"one-quarter" (cp1252-Lesung) und dann wieder UTF-8 geschrieben.

WIRKUNG
-------
Der Defekt faellt im Quelltext nicht auf. In
tool/make_feature_graphic.py stand woertlich `verschlA-...-sselt` in
einem Python-String - der Code lief, die Tests waren gruen, nichts hat
gemeckelt. Sichtbar wurde es erst auf dem gerenderten Play-Banner.
Eine Fehlerklasse, die nur im Artefakt auftaucht, braucht eine
Pruefung an der Quelle: check_mojibake.py.

AUSSCHLUESSE - WICHTIG
----------------------
Nicht jede Doppelkodierung ist ein Fehler. test/l10n_test.dart enthaelt
absichtlich die Zeichen U+00C3 und U+00C2, weil der Test damit in
app_strings.dart nach Doppelkodierungs-Resten sucht. Wird diese Datei
"repariert", zerstoert man das Pruefmittel und der Test laeuft ins Leere.
Aehnlich tool/check_mojibake.py, das dieselben Zeichen in seiner
Dokumentation zeigt.

Deshalb ist die Ausschlussliste Teil des Werkzeugs und nicht eine
Nebenbemerkung.

Aufruf:
    python tool/fix_mojibake.py            # nur melden
    python tool/fix_mojibake.py --apply    # reparieren
"""
from __future__ import annotations

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = pathlib.Path(r'C:\Users\Thoralf\AppData\Local\Temp\opencode\fix_mojibake_report.txt')

SUFFIXES = {'.py', '.md', '.dart', '.yml', '.yaml', '.toml', '.txt', '.sql',
            '.json', '.html', '.properties', '.gradle', '.kts', '.ps1', '.cfg'}
SKIP_DIRS = {'build', '.git', '.dart_tool', 'node_modules', 'releases',
             'third_party', 'ios', 'android'}

# Dateien, die die Fehlzeichen ABSICHTLICH enthalten
EXCLUDE_FILES = {
    'test/l10n_test.dart',      # sucht selbst nach U+00C3 / U+00C2
    'tool/check_mojibake.py',   # zeigt sie in der Doku
    'tool/fix_mojibake.py',     # dieses Skript
}

# Nicht versionierte Wegwerf-Ausgaben unter tool/ (gitignored)
EXCLUDE_PREFIXES = ('tool/asan', 'tool/asv', 'tool/chk', 'tool/dh',
                    'tool/fm', 'tool/nu', 'tool/p0', 'tool/q.', 'tool/rem')

# Beide Mengen werden ABGELEITET, nicht handgeschrieben. Grund: cp1252
# bildet die Bytes 0x80-0x9F auf typografische Sonderzeichen ab - 0x80 ist
# "Euro", 0x93/0x94 sind Gaenstriche, 0x96/0x97 Gedankenstriche. Eine
# handgeschriebene Menge 0x80-0xBF erfasst damit UTF-8-Dreibytezeichen
# wie "em dash" gar nicht: sie zerfallen in "a-circumflex" + "Euro" +
# '"', und der Lauf bricht nach einem Byte ab, weil U+20AC nicht im
# Bereich liegt. Genau das ergab 8 unaufgeloeste Stellen.
#
# Ausgangspunkt ist die Bytezahl, nicht das Zeichen: jedes Byte, das
# cp1252 als verwertbares Zeichen kennt, wird zu dem Zeichen, das diese
# Fehlkodierung erzeugt hat.
CONT: set[str] = set()
for _b in range(0x80, 0xC0):
    try:
        CONT.add(bytes([_b]).decode('cp1252'))
    except UnicodeDecodeError:
        pass

# Startbytes zweier- und dreier UTF-8-Sequenzen: 0xC2-0xDF bzw.
# 0xE0-0xEF. U+00C3 ('A-tilde') ist die cp1252-Lesung von 0xC3,
# U+00E2 ('a-circumflex') die von 0xE2.
LEAD: set[str] = set()
for _b in list(range(0xC2, 0xE0)) + list(range(0xE0, 0xF0)):
    try:
        LEAD.add(bytes([_b]).decode('cp1252'))
    except UnicodeDecodeError:
        pass

MAX_RUN = 4
REPLACEMENT = chr(0xFFFD)


def excluded(rel: str) -> bool:
    if rel in EXCLUDE_FILES:
        return True
    return any(rel.startswith(p) for p in EXCLUDE_PREFIXES)


def repair_line(line: str) -> tuple[str, int, int]:
    out: list[str] = []
    i = 0
    fixed = 0
    unresolved = 0
    while i < len(line):
        if line[i] in LEAD:
            # Start bei i+1, NICHT bei i: die Verdachtszeichen selbst
            # (U+00C2/C3/E2) liegen oberhalb von 0xBF und damit ausserhalb
            # von CONT. Mit j = i pruefte die Bedingung
            # `line[j] in CONT` sofort falsch, j blieb auf i, und
            # `i = j` bewegte den Zeiger nicht - Endlosschleife, die den
            # gesamten Lauf haengen liess. Fortschritt ist hier nicht
            # nur Performance, sondern Korrektheit.
            j = i + 1
            while j < len(line) and line[j] in CONT and (j - i) < MAX_RUN:
                j += 1
            run = line[i:j]
            try:
                out.append(run.encode('cp1252').decode('utf-8'))
                fixed += len(run)
            except (UnicodeEncodeError, UnicodeDecodeError):
                out.append(run)
                unresolved += 1
            assert j > i, 'Fortschrittsgarantie verletzt'
            i = j
        else:
            out.append(line[i])
            i += 1
    return ''.join(out), fixed, unresolved


def walk_files():
    """Alle relevanten Dateien, mit Pruning beim Wandern.

    pathlib.Path.rglob('*') durchsucht auch build/, .git/, android/ und
    ios/ und filtert erst DANACH nach Namen. Das sind zehntausende
    Dateien, der Lauf haengt. Deshalb os.walk mit Entfernen der
    Verzeichnisse aus dem Suchbaum - das bricht sie gar nicht erst auf.
    """
    import os
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if d not in SKIP_DIRS and not d.endswith('.git')]
        for name in filenames:
            p = pathlib.Path(dirpath) / name
            if p.suffix.lower() in SUFFIXES:
                yield p


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true',
                    help='schreiben statt nur melden')
    args = ap.parse_args()

    lines_out: list[str] = []
    total_files = 0
    total_fixed = 0
    total_unresolved = 0

    for p in sorted(walk_files()):
        rel = p.relative_to(ROOT).as_posix()
        if excluded(rel):
            continue
        try:
            raw = p.read_bytes()
            text = raw.decode('utf-8-sig')
        except (UnicodeDecodeError, OSError):
            continue
        src_lines = text.splitlines(keepends=True)
        new_lines: list[str] = []
        file_fixed = 0
        file_unresolved = 0
        for line in src_lines:
            body = line.rstrip('\n')
            tail = line[len(body):]
            fixed_body, n, u = repair_line(body)
            new_lines.append(fixed_body + tail)
            file_fixed += n
            file_unresolved += u
        if file_fixed:
            total_files += 1
            total_fixed += file_fixed
            total_unresolved += file_unresolved
            lines_out.append(f'{rel}: {file_fixed} Zeichen repariert'
                             + (f', {file_unresolved} unaufgeloest'
                                if file_unresolved else ''))
            if args.apply:
                # UTF-8 ohne BOM: der BOM kam aus demselben
                # PowerShell-Round-Trip und stoert andere Werkzeuge.
                p.write_text(''.join(new_lines), encoding='utf-8', newline='\n')

    lines_out.insert(0, f'{"REPARIERT" if args.apply else "GEMELDET"}: '
                        f'{total_files} Datei(en), {total_fixed} Zeichen, '
                        f'{total_unresolved} unaufgeloest')
    lines_out.append('')
    lines_out.append('Ausgeschlossen (enthalten die Fehlzeichen absichtlich):')
    for f in sorted(EXCLUDE_FILES):
        lines_out.append(f'  {f}')
    lines_out.append('  tool/*.txt (gitignorierte Wegwerf-Ausgaben)')

    OUT.write_text('\n'.join(lines_out) + '\n', encoding='utf-8')
    print('report written')
    print(f'  {total_files} Datei(en), {total_fixed} Zeichen'
          + (' - geschrieben' if args.apply else ' - nur gemeldet'))
    return 1 if total_unresolved else 0


if __name__ == '__main__':
    sys.exit(main())
