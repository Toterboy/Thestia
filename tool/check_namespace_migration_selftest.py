"""Selbsttest fuer check_namespace_migration.py.

Sechs Mutationen, die alle einen echten Release-Blocker erzeugen:
  A) signals komplett aus der Migrationsliste entfernen
  B) signals-Key-Liste leeren (stiller No-op)
  C) session aus der Migrationsliste entfernen
  D) extraSessionKeys-Parameter entfernen
  E) contacts nicht mehr als "neu ohne Migration" deklariert
  F) einen MIGRierten Namespace zusaetzlich als "neu" deklariert

Alle MUESSEN den Checker zum Scheitern bringen. Ein Checker, der einen
Datenverlust beim Update nicht sieht, ist schlimmer als keiner.

WICHTIG: Die Mutationen suchen per REGEX, nicht per exaktem Text. Sonst
bricht der Selbsttest bei der naechsten Formatierungs-Aenderung des
Quelltextes (Zeilenumbrueche, Einrueckung) - ein Selftest, der an
Formatierung klebt, prueft die Sache nicht mehr, sondern nur noch den
Formatierer.
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
CHECKER = REPO / 'tool' / 'check_namespace_migration.py'
TARGET = 'lib/services/secure_storage_namespaces.dart'


def run_mutation(label, mutate, expect_fail):
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        shutil.copytree(REPO / 'lib', root / 'lib')
        shutil.copytree(REPO / 'tool', root / 'tool')
        p = root / TARGET
        t = p.read_text(encoding='utf-8')
        t2 = mutate(t)
        if t2 == t:
            print(f'  UNGUELTIG  {label}: Mutation wirkungslos')
            return False
        p.write_text(t2, encoding='utf-8', newline='\n')

        r = subprocess.run([sys.executable, str(root / 'tool' /
                                                'check_namespace_migration.py')],
                           capture_output=True, text=True)
        failed = r.returncode != 0
        ok = failed == expect_fail
        mark = 'OK          ' if ok else 'NICHT ERKANNT'
        print(f'  {mark}  {label}')
        print(f'              Exitcode={r.returncode} '
              f'(erwartet {"1" if expect_fail else "0"})')
        for l in r.stdout.splitlines():
            s = l.strip()
            if s.startswith('X '):
                print(f'              {s[:92]}')
        return ok


def _sub(t, pattern, repl, count=1):
    return re.sub(pattern, repl, t, count=count, flags=re.S)


def drop_signals(t):
    # signals komplett aus der Migrationsliste entfernen
    return _sub(t, r'SecureNamespaces\.signals:\s*\[[^\]]*\],?\s*', '')


def empty_signals(t):
    # signals-Key-Liste leeren (stiller No-op)
    return _sub(t, r'SecureNamespaces\.signals:\s*\[[^\]]*\]',
                'SecureNamespaces.signals: []')


def drop_session(t):
    return _sub(t, r'SecureNamespaces\.session:\s*\[\],?\s*', '')


def drop_hive_key_param(t):
    # extraSessionKeys-Parameter entfernen -> session laeuft leer
    return _sub(t, r'List<String>\s+extraSessionKeys\s*=\s*const\s*\[\],\s*', '')


def drop_new_declaration(t):
    # contacts aus der "neu ohne Migration"-Deklaration entfernen:
    # der Checker muss den Namespace dann wieder als Blocker melden.
    return _sub(t, r'withoutMigration\s*=\s*<String>\{[^}]*\}',
                'withoutMigration = <String>{}')


def declare_migrated_as_new(t):
    # signals als "neu" deklarieren, obwohl es migriert wird:
    # das ist widerspruechlich und muss auffallen.
    def repl(m):
        inhalt = m.group(1)
        return 'withoutMigration = <String>{' + inhalt + ', signals}'
    return _sub(t, r'withoutMigration\s*=\s*<String>\{([^}]*)\}', repl)


print('SELBSTTEST check_namespace_migration.py\n' + '=' * 74)
results = [
    run_mutation('signals ganz aus der Migrationsliste', drop_signals, True),
    run_mutation('signals-Liste leer (stiller No-op)', empty_signals, True),
    run_mutation('session ganz aus der Migrationsliste', drop_session, True),
    run_mutation('extraSessionKeys-Parameter entfernt', drop_hive_key_param, True),
    run_mutation('contacts nicht mehr als neu deklariert',
                 drop_new_declaration, True),
    run_mutation('migrierter Namespace zugleich als neu deklariert',
                 declare_migrated_as_new, True),
]
print('=' * 74)
if all(results):
    print(f'OK: alle {len(results)} Blocker-Mutationen werden erkannt')
    sys.exit(0)
print(f'{results.count(False)}/{len(results)} Mutationen NICHT erkannt')
sys.exit(1)
