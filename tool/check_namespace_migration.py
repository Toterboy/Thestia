"""Regressionstest fuer den Release-Blocker vom 2026-09-27.

Die Keystore-Namespaces wurden umgestellt, aber zwei davon wurden nicht
migriert. Das faellt im Review NICHT auf, weil der Code je fuer sich
korrekt ist - erst beim Update bricht es:

  - `session`  -> alle Bestandsnutzer abgemeldet
  - `signals`  -> neuer Hive-Schluessel, verschluesselte Boxen unlesbar
                  (bei Signal-Keys: Verlust der E2E-Identitaet)

Der Test liest deshalb die QUELLDATEIEN statisch und vergleicht jede
Umstellung eines Namespaces mit der Migrationsliste. Eine Umstellung ohne
mpassenden Migrations-Eintrag ist ein Fehler.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = ROOT / 'lib'


def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8', errors='replace')


ns_src = read('lib/services/secure_storage_namespaces.dart')

# ---------------------------------------------------------------- Namespaces
declared = dict(re.findall(r"static const String (\w+)\s*=\s*'([^']+)';", ns_src))
print('Deklarierte Namespaces:')
for k, v in sorted(declared.items()):
    print(f'   {k:10s} = {v}')

# ---------------------------------------------------------------- Migrationsliste
m = re.search(r'_legacyKeys\s*=\s*\{(.*?)\n\};', ns_src, re.S)
if not m:
    print('FEHLER: _legacyKeys nicht gefunden')
    sys.exit(1)
legacy_block = m.group(1)
migrated = set(re.findall(r'SecureNamespaces\.(\w+):', legacy_block))
print(f'\nIn _legacyKeys migriert: {sorted(migrated)}')

# Keys je Namespace
keys_per_ns = {}
for nm in re.finditer(
        r'SecureNamespaces\.(\w+):\s*\[(.*?)\]', legacy_block, re.S):
    ks = re.findall(r"'([^']+)'", nm.group(2))
    keys_per_ns[nm.group(1)] = ks

# ---------------------------------------------------------------- Umstellungen finden
results = []
UMLAUT = {0x00E4, 0x00F6, 0x00FC, 0x00DF}


def norm(s):
    return s.lower()


for f in sorted(LIB.rglob('*.dart')):
    rel = f.relative_to(ROOT).as_posix()
    src = f.read_text(encoding='utf-8', errors='replace')
    if 'secure_storage_namespaces' not in src and 'storageNamespace' not in src:
        continue
    used = set(re.findall(r'SecureNamespaces\.(\w+)', src))
    # Nur Dateien, die den Namespace auch tatsaetzlich an WEAK GIFTEN
    if 'storageNamespace' not in src and 'accountName' not in src:
        continue
    # Die Migrationsdatei selbst referenziert alle Namespaces nur als
    # Map-Schluessel - das ist kein Umstellungs-Fund. Ebenso ist \_\ der
    # private Konstruktor, kein Namespace.
    if rel == 'lib/services/secure_storage_namespaces.dart':
        continue
    used = {n for n in used if n != '_'}
    for ns in sorted(used):
        results.append((rel, ns))

print('\nUmgestellte Namespaces im Code:')
for rel, ns in results:
    mark = 'OK  ' if ns in migrated else 'FEHLT'
    print(f'   {mark} {rel:46s} {ns}')

# ---------------------------------------------------------------- Bewertung
print('\n' + '=' * 74)
problems = []

for rel, ns in results:
    if ns not in migrated:
        problems.append(f'{rel}: {ns} wird benutzt, aber NICHT migriert '
                        f'-> Datenverlust beim Update')
    else:
        ks = keys_per_ns.get(ns, [])
        if ks:
            print(f'  migriert: {ns:10s} Keys={ks}')
        else:
            # Leer ist nur erlaubt, wenn der Key dynamisch nachgereicht wird
            if 'extraSessionKeys' not in ns_src:
                problems.append(f'{ns}: Eintrag ist leer und es gibt keine '
                                f'Nachreichung -> nichts migriert')

if problems:
    print('RELEASE-BLOCKER:\n')
    for p in problems:
        print('  X', p)
    print('\nEin Namespace-Wechsel OHNE Migrations-Eintrag bedeutet: beim')
    print('Update sind die Daten unerreichbar. Bei `resetOnError: true')
    print('(Default) loescht zusaetzlich der erste Dekrypt-Fehlschlag die')
    print('Werte der anderen Namespaces mit.')
    sys.exit(1)

# -------------------------------------------------
# Zweite Ebene: ein Namespace-NAME allein reicht nicht.
# Eine leere Key-Liste ist ein stiller No-op - die
# Migration laeuft durch und kopiert nichts.
# -------------------------------------------------
print('\nZweite Ebene: leere Migrationslisten')
empty_problems = []
# Wichtig: es muss die DEKLARATION des Parameters geprueft werden, nicht
# nur seine Erwaehnung. Sonst waere ein entfernter Parameter (Kompilier-
# fehler) fuer diesen Text-Checker unsichtbar.
runtime_ok = bool(re.search(
    r'List<String>\s+extraSessionKeys\s*=', ns_src))
if not runtime_ok:
    print('  X    extraSessionKeys wird verwendet, aber nicht deklariert '
          '-> der Code kompiliert nicht')
    empty_problems.append('extraSessionKeys-Deklaration fehlt')
for rel, ns in results:
    ks = keys_per_ns.get(ns, [])
    if ks:
        print(f'  OK   {ns:10s} {len(ks)} Key(s) migriert')
    elif ns == 'session' and runtime_ok:
        print(f'  OK   {ns:10s} leer, aber Keys werden zur Laufzeit '
              f'ueber extraSessionKeys nachgereicht')
    else:
        empty_problems.append(ns)
        print(f'  X    {ns:10s} LEER - die Migration kopiert nichts '
              f'(stiller No-op)')

if empty_problems:
    print('\nRELEASE-BLOCKER: leere Migrationslisten')
    sys.exit(1)

print('\nOK: jeder umgestellte Namespace ist auch migriert,')
print('    und jede Liste enthaelt tatsaechlich Keys')
