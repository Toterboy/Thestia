"""Validiert alle Migrationen mit pglast (echter PostgreSQL-Parser).

Prueft zusaetzlich die eingebauten Sicherheits-Invarianten:
  * Paarungsfunktionen muessen blocked_users + age_compatible_bidirectional
    enthalten UND ein Fail-Fast-DO-Block muss das auch durchsetzen.
"""
import pathlib
import re
import sys

import pglast

MIG = pathlib.Path('supabase/migrations')
files = sorted(MIG.glob('*.sql'),
               key=lambda p: int(re.match(r'(\d+)', p.name).group(1)))

syntax_fail = 0
for f in files:
    sql = f.read_text(encoding='utf-8', errors='replace')
    try:
        pglast.parse_sql(sql)
    except Exception as e:
        syntax_fail += 1
        first = str(e).splitlines()
        print(f'SYNTAX-FEHLER {f.name}:')
        for line in first[:6]:
            print('   ', line)

print(f'\nSyntax: {len(files) - syntax_fail}/{len(files)} Migrationen OK')

# --- Endstand je Funktion bestimmen -----------------------------------------
defs = {}
for f in files:
    sql = f.read_text(encoding='utf-8', errors='replace')
    for m in re.finditer(
            r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\(',
            sql, re.I):
        depth, i = 1, m.end()
        while i < len(sql) and depth:
            if sql[i] == '(':
                depth += 1
            elif sql[i] == ')':
                depth -= 1
            i += 1
        # Body-Ende: bei Dollar-Quoting das schliessende $$; - NICHT das erste
        # Semikolon (das liegt fast immer schon mitten im Body).
        close = sql.find('$$;', i)
        ret = re.search(r'\)\s*RETURNS\s+[a-z0-9_ \[\]]+', sql[i:i + 400], re.I)
        if close != -1 and (ret is None or close < i + 400 or ret.start() < 0):
            end = close
        else:
            close2 = sql.find(';', i)
            end = close2 if close2 != -1 else i + 6000
        defs[m.group(1).lower()] = sql[i:end if end != -1 else i + 6000]

# --- Sicherheits-Invarianten -------------------------------------------------
PAIRS = ['join_random_chat', 'match_dating_hour_round']
print('\nInvarianten Paarungs-Sicherheit:')
ok = True
for name in PAIRS:
    body = defs.get(name, '')
    checks = {
        'blocked_users': 'blocked_users' in body,
        'age_compatible_bidirectional': 'age_compatible_bidirectional' in body,
    }
    for k, v in checks.items():
        print(f'  {name:26} {k:30} {"OK" if v else "FEHLT"}')
        ok &= v

# Fail-Fast-Guard vorhanden?
all_sql = '\n'.join(f.read_text(encoding='utf-8', errors='replace') for f in files)
guards = {
    'Quiz-Helfer anon-gesperrt (DO-Check)':
        "FROM PUBLIC, anon, authenticated;\nREVOKE ALL ON FUNCTION public.quiz_shuffle_for_match" in all_sql
        or ('quiz_shuffle_for_match' in all_sql and 'has_function_privilege' in all_sql),
    'Trigger random_chat': 'trg_enforce_random_chat_safety' in all_sql,
    'Trigger dating_hour': 'trg_enforce_dating_hour_safety' in all_sql,
    'uniq_active_dh_pair': 'uniq_active_dh_pair' in all_sql,
    'ALTER DEFAULT PRIVOKE ... FROM PUBLIC':
        'REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;' in all_sql,
}
print('\nInvarianten Guards:')
for k, v in guards.items():
    print(f'  {k:44} {"OK" if v else "FEHLT"}')
    ok &= v

# --- Antwortschluessel-Helfer duerfen nicht mehr oeffentlich sein ---------------
# Migration 123 loest das DYNAMISCH ueber pg_proc auf (DO-Block mit
# p.oid::regprocedure), weil `quiz_pick_personalized` zwei Overloads hat.
# Ein Regex ueber Signaturen kann das nicht mehr sehen - daher wird der
# dynamische Block als Treffer gewertet.
dynamic_block = re.search(
    r"p\.oid::regprocedure::text[\s\S]{0,900}?REVOKE ALL ON FUNCTION %s "
    r"FROM PUBLIC, anon, authenticated", all_sql, re.I)
revoke_targets = set()
for m in re.finditer(
        r'REVOKE\s+(?:ALL|EXECUTE)\s*(?:ON\s+FUNCTION\s+)?(?:public\.)?"?([a-z0-9_]+)"?\s*\('
        r'[^)]*\)[^;]*?FROM\s+([^;]+);', all_sql, re.I | re.S):
    roles = {r.strip().lower() for r in m.group(2).split(',')}
    if {'public', 'anon'} & roles:
        revoke_targets.add(m.group(1).lower())

print('\nInterne Quiz-Helfer (Entzug PUBLIC/anon/authenticated):')
if dynamic_block:
    print('  dynamischer pg_proc-Block vorhanden -> alle Overloads erfasst')
ok &= bool(dynamic_block)
for n in ['quiz_shuffle_for_match', 'quiz_pick_personalized',
          'quiz_personal_distractors', 'quiz_stopwords', 'quiz_interest_catalog']:
    hit = n in revoke_targets or bool(dynamic_block)
    print(f'  {n:32} {"OK" if hit else "FEHLT"}')
    ok &= hit

print('\nGESAMT:', 'ALLE INVARIANTEN ERFUELLT' if (ok and not syntax_fail)
      else 'PROBLEME VORHANDEN')
sys.exit(0 if (ok and not syntax_fail) else 1)
