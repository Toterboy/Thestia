"""Selbsttest fuer check_namespace_migration.py.

Zwei Mutationen, die beide einen echten Release-Blocker erzeugen:
  A) signals komplett aus der Migrationsliste entfernen
  B) signals-Key-Liste leeren (stiller No-op)

Beide MUESSEN den Checker zum Scheitern bringen. Ein Checker, der einen
Datenverlust beim Update nicht sieht, ist schlimmer als keiner.
"""
import pathlib
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


def drop_signals(t):
    return t.replace('SecureNamespaces.signals: [\n  \'hive_encryption_key\',\n],\n', '')


def empty_signals(t):
    return t.replace("  'hive_encryption_key',\n", '')


def drop_session(t):
    return t.replace('SecureNamespaces.session: [],\n', '')


def drop_hive_key_param(t):
    # extraSessionKeys-Parameter entfernen -> session laeuft leer
    return t.replace('  List<String> extraSessionKeys = const [],\n', '')


print('SELBSTTEST check_namespace_migration.py\n' + '=' * 74)
results = [
    run_mutation('signals ganz aus der Migrationsliste', drop_signals, True),
    run_mutation('signals-Liste leer (stiller No-op)', empty_signals, True),
    run_mutation('session ganz aus der Migrationsliste', drop_session, True),
    run_mutation('extraSessionKeys-Parameter entfernt', drop_hive_key_param, True),
]
print('=' * 74)
if all(results):
    print(f'OK: alle {len(results)} Blocker-Mutationen werden erkannt')
    sys.exit(0)
print(f'{results.count(False)}/{len(results)} Mutationen NICHT erkannt')
sys.exit(1)
