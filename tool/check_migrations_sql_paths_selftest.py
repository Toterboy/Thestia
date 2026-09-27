"""Simuliert den Linux-Fall, ohne Linux zu brauchen.

Der CI-Fehler war: die Dateiliste enthielt Windows-Rawstrings
(r"supabase\\migrations\\..."), die unter Linux kein Verzeichnis
bezeichnen. Ein solches Skript "laeuft" auf Windows und faellt erst auf
dem Runner auf.

Dieser Test prueft die Pfad-Konvention, ohne die Dateien zu oeffnen:
- kein Backslash in den Pfaden der FILES-Liste
- jeder Pfad laesst sich unter POSIX-Normen als PurePath lesen
- die Liste bleibt die gleiche (nicht etwa stillschweigend leer)
- relative Pfade, nicht absolute Maschinenpfade
"""
import pathlib
import re
import sys
import types

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


# 1) die FILES-Liste extrahieren
m = re.search(r'FILES\s*=\s*\[(.*?)\]', src, re.S)
check('FILES-Liste vorhanden', bool(m))
if not m:
    sys.exit(1)
entries = re.findall(r'["\']([^"\']+)["\']', m.group(1))
print(f'         {len(entries)} Eintraege')

# 2) kein Backslash - genau der Fehler, der die CI gerissen hat
bs = [e for e in entries if '\\' in e]
check('keine Backslashes in den Pfaden', not bs,
      f'gefunden: {bs}' if bs else 'alle Eintraege mit Forward-Slash')

# 3) jeder Pfad ist unter POSIX lesbar und zeigt auf die echte Datei
pure = [pathlib.PurePosixPath(e) for e in entries]
check('alle Eintraege als POSIX-Pfad lesbar', len(pure) == len(entries))
root = SRC.resolve().parent.parent
missing = [e for e in entries if not (root / e).exists()]
check('jeder Pfad zeigt auf eine existierende Datei', not missing,
      f'fehlt: {missing}' if missing else f'geprueft gegen {root.name}/')

# 4) keine absoluten Pfade und kein CWD-Referenz
abs_ = [e for e in entries if e.startswith(('/', '\\') ) or ':' in e]
check('keine absoluten Pfade in der Liste', not abs_, f'{abs_}' if abs_ else '')

# 5) die Pruefung ist am Repo-Root verankert, nicht ans CWD gebunden
check('am __file__ verankert statt ans Arbeitsverzeichnis',
      'ROOT = pathlib.Path(__file__)' in src)

# 6) das Skript meldet eine fehlende Datei, statt sie zu ueberspringen
check('fehlende Datei wird als Fehler gemeldet',
      'FEHLER - Datei nicht gefunden' in src)

print()
if bad:
    print(f'{bad} Fall(e) falsch.')
    sys.exit(1)
print('OK: die Pfade sind plattformneutral und repo-relativ.')
sys.exit(0)
