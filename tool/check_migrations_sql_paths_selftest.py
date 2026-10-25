"""Simuliert den Linux-Fall, ohne Linux zu brauchen.

Der CI-Fehler war: die Dateiliste enthielt Windows-Rawstrings
(r"supabase\\migrations\\..."), die unter Linux kein Verzeichnis
bezeichnen. Ein solches Skript "laeuft" auf Windows und faellt erst auf
dem Runner auf.

Der Check ist seit dem umbenannt: FILES wird nicht mehr als feste Liste
geschrieben, sondern per Glob ueber das Migrationsverzeichnis erzeugt.
Der Grund (22.10.2026): die feste Liste hielt den Stand bei fuenf
Dateien fest, waehrend die Migrationen auf 158 weiterwuchsen - 109 bis
155 wurden also NIE geprueft, auch nicht die sicherheitskritischen 144,
149, 151 und 155. Der Glob waechst automatisch mit.

Der Test laeuft deshalb zweistufig:

1) Quelltext-Konvention: der Glob muss im Skript stehen, die
   Backslash-Formung muss dabei sein (das ist die eigentliche
   Linux-Reparatur), und die Pruefung muss am Repo-Root haengen.

2) Ergebnis-Konvention: der Check wird als eigener Prozess ausgefuehrt
   und die Anzahl seiner geprueften Dateien gegen eine unabhaengige
   Aufzaehlung des Verzeichnisses gestellt. So ist bewiesen, dass der
   Glob wirklich ALLE Migrationen erfasst - und nicht wieder eine
   stillschweigende Teilmenge.

Ein Import von check_migrations_sql als Modul ist bewusst KEIN Weg: das
Skript laeuft beim Import komplett durch und endet mit sys.exit - ein
abgebrochener Import liefert das Modulobjekt nicht zurueck.
"""
import os
import pathlib
import re
import subprocess
import sys

SRC = pathlib.Path(__file__).resolve().parent / 'check_migrations_sql.py'
src = SRC.read_text(encoding='utf-8')

print('=' * 72)
print('PFADKONVENTION check_migrations_sql.py')
print('=' * 72)
bad = 0


def check(name: str, ok: bool, detail: str = '') -> None:
    global bad
    if not ok:
        bad += 1
    print(f'  [{"OK  " if ok else "FEHL"}] {name}')
    if detail:
        print(f'         {detail}')


root = SRC.resolve().parent.parent

# ---------------------------------------------------------------- Stufe 1: Quelltext
check('FILES wird per Glob erzeugt',
      re.search(r'FILES\s*=\s*sorted\(', src) is not None
      and 'glob("*.sql")' in src)

# Kein Backslash im Ergebnis - genau der Fehler, der die CI gerissen
# hat. Die Formung muss deshalb im Quelltext stehen.
check('Backslash-Formung ist im Quelltext verankert',
      'replace("\\\\", "/")' in src)

check('am __file__ verankert statt ans Arbeitsverzeichnis',
      'ROOT = pathlib.Path(__file__)' in src)

check('fehlende Datei wird als Fehler gemeldet',
      'FEHLER - Datei nicht gefunden' in src)

# ---------------------------------------------------------------- Stufe 2: Ergebnis
# Unabhaengige Aufzaehlung des Migrationsverzeichnisses.
tatsaechlich = sorted(
    n for n in os.listdir(root / 'supabase' / 'migrations')
    if n.endswith('.sql')
)
erwartet = sorted(
    str(pathlib.PurePosixPath('supabase/migrations') / n)
    for n in tatsaechlich
)
check('jeder erwartete Pfad zeigt auf eine existierende Datei',
      all((root / e).exists() for e in erwartet),
      f'{len(erwartet)} Migrationen gezaehlt')

# Und der echte Lauf: exit 0 UND genau so viele "OK"-Zeilen wie Dateien.
proc = subprocess.run(
    [sys.executable, str(SRC)], cwd=root, capture_output=True,
    text=True, encoding='utf-8', errors='replace', timeout=300,
)
ok_zeilen = [l for l in proc.stdout.splitlines() if ': OK - ' in l]
check('der Check laeuft fehlerfrei', proc.returncode == 0,
      '' if proc.returncode == 0 else proc.stdout[-400:])
check('der Check prueft alle Migrationen', len(ok_zeilen) == len(erwartet),
      f'geprueft: {len(ok_zeilen)}, vorhanden: {len(erwartet)}')
if len(ok_zeilen) != len(erwartet):
    fehlen = sorted(set(erwartet) - {l.split(':')[0] for l in ok_zeilen})
    check('keine Migration wird uebersprungen', not fehlen,
          f'nicht geprueft: {fehlen[:5]}')

print()
if bad:
    print(f'{bad} Fall(e) falsch.')
    sys.exit(1)
print('OK: die Pfade sind plattformneutral, repo-relativ und lueckenlos.')
sys.exit(0)
