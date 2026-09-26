"""Statische Vorpruefung fuer die 6 Fehlerklassen, die der Remote-Push
am 2026-09-26 aufgedeckt hat. Alle sechs sind mit pglast NICHT gefunden
worden - die echte Datenbank hat sie abgelehnt.

    python tool/check_migration_safety.py   # Syntax + Invarianten
    python tool/check_push_readiness.py     # + diese Vorpruefung

1) `REVOKE ... FROM anon` ohne `FROM PUBLIC` greift nicht, weil jede Rolle
   implizit Mitglied der Pseudo-Rolle PUBLIC ist.
2) Overloads: eine Signatur-Liste uebersieht `quiz_pick_personalized(6 Arg)`.
   -> Der Entzug muss dynamisch ueber pg_proc laufen.
3) Fail-Fast-Checks auf `pg_proc.prosrc` schlagen auf die eigenen Kommentare
   an, weil prosrc den Body MIT Kommentaren enthaelt.
4) `LANGUAGE sql` loest seinen Body bei CREATE auf -> Aufruf einer erst
   spaeter definierten public-Function ergibt 42883.
5) `CREATE OR REPLACE` kann Rueckabetyp, Argumenttypen und Parameternamen
   nicht aendern (42P13 / 42804).
6) `RAISE EXCEPTION name` OHNE Anfuehrungszeichen ist ein Condition-Name und
   ergibt bei CREATE 42704 "unrecognized exception condition".
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIG = ROOT / 'supabase' / 'migrations'
NEW = [f for f in sorted(MIG.glob('*.sql')) if f.name[:3] >= '123']
ALL = sorted(MIG.glob('*.sql'))

findings = []


def flag(cls, f, msg):
    findings.append((cls, f.name, msg))


def strip_comments(sql: str) -> str:
    sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.S)
    out, in_str, i = [], False, 0
    while i < len(sql):
        if sql[i] == "'":
            in_str = not in_str
        if not in_str and sql.startswith('--', i):
            j = sql.find('\n', i)
            i = len(sql) if j < 0 else j
            continue
        out.append(sql[i])
        i += 1
    return ''.join(out)


def read(f):
    return f.read_text(encoding='utf-8', errors='replace')


pat_fn = re.compile(
    r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-z_0-9]+)\s*\(', re.I)


def split_top(s):
    parts, depth, cur = [], 0, ''
    for ch in s:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def sig_at(c, pos):
    i = c.index('(', pos)
    depth, j = 0, i
    while j < len(c):
        if c[j] == '(':
            depth += 1
        elif c[j] == ')':
            depth -= 1
            if depth == 0:
                break
        j += 1
    args = []
    for a in split_top(c[i + 1:j]):
        toks = a.split()
        pname, ptype = (toks[0], ' '.join(toks[1:])) if len(toks) >= 2 else ('?', a)
        ptype = re.split(r'\bDEFAULT\b', ptype, flags=re.I)[0]
        args.append((pname.lower(), re.sub(r'\s+', ' ', ptype.strip().lower())))
    rest = c[j + 1:j + 900]
    m = re.search(r'RETURNS\s+([A-Za-z_][A-Za-z0-9_ ]*?(?:\([^)]*\))?)', rest, re.I)
    return (m.group(1).strip().lower() if m else '?'), args


# ---------------------------------------------------------------- 1
for f in NEW:
    code = strip_comments(read(f))
    for m in re.finditer(r'REVOKE\s+EXECUT\w*\s+ON\s+FUNCTION\s+[^;]*?FROM\s+([^;]+);',
                         code, re.I | re.S):
        # Rollennamen koennen aus einem format()-String stammen, also mit
        # Anfuehrungszeichen und Zusatztext: 'anon', r.sig)
        roles = {r.strip().strip("'\"").split()[0].lower()
                 for r in m.group(1).split(',') if r.strip()}
        if 'anon' in roles and 'public' not in roles:
            flag('1 PUBLIC-Revoke', f,
                 'REVOKE ... FROM anon ohne FROM PUBLIC - die Berechtigung '
                 'wird ueber die Pseudo-Rolle PUBLIC vererbt und bleibt bestehen')

# ---------------------------------------------------------------- 2
# Nur ein Problem, wenn eine MEHRFACH ueberladene Function per Signatur
# revokt wird. Normale Signatur-Listen fuer Client-RPCs sind korrekt.
overloads = {}
for f in ALL:
    c = read(f)
    for m in pat_fn.finditer(c):
        _, args = sig_at(c, m.start())
        overloads.setdefault(m.group(1).lower(), set()).add(tuple(a[1] for a in args))
multi = {k for k, v in overloads.items() if len(v) > 1}

for f in NEW:
    code = strip_comments(read(f))
    dynamic = 'regprocedure' in code
    # Pro Function: welche Signaturen werden tatsaechlich revokt?
    revoked = {}
    for m in re.finditer(
            r'REVOKE[^;]*?ON\s+FUNCTION\s+(?:public\.)?([a-z_0-9]+)\s*\(([^)]*)\)',
            code, re.I | re.S):
        name = m.group(1).lower()
        types = tuple(
            re.sub(r'\s+', ' ', re.split(r'\bDEFAULT\b', a, flags=re.I)[0]
                   .strip().lower()).split()[-1]
            for a in split_top(m.group(2)))
        revoked.setdefault(name, set()).add(types)

    for name, sigs in revoked.items():
        if name not in multi or dynamic:
            continue
        missing = overloads[name] - sigs
        if missing:
            pretty = ', '.join('(' + ', '.join(s) + ')' for s in sorted(missing))
            flag('2 Overloads', f,
                 f'{name} ist {len(overloads[name])}x ueberladen, aber '
                 f'{pretty} wird NICHT revokt - diese Variante bleibt aufrufbar')

# ---------------------------------------------------------------- 3
def bodies_of(c):
    out = {}
    for m in pat_fn.finditer(c):
        end = c.find('\n$$;', m.start())
        if end > 0:
            out.setdefault(m.group(1).lower(), []).append(c[m.start():end])
    return out


UNIVERSE = {}
for f in ALL:
    for name, lst in bodies_of(read(f)).items():
        UNIVERSE[name] = lst[-1]

def like_pattern(expr: str) -> str:
    """LIKE-Ausdruck symbolisch auswerten.

    `'%reason%'`                       -> %reason%
    `'%' || chr(39) || 'reason' || ..` -> 'reason'   (MIT Quotes!)
    """
    out = []
    for part in re.split(r'\|\|', expr):
        part = part.strip()
        if part == 'chr(39)':
            out.append("'")
        else:
            out.extend(re.findall(r"'([^']*)'", part))
    return ''.join(out)


def like_to_regex(pat: str) -> str:
    """SQL-LIKE -> Regex (nur % ist Platzhalter)."""
    return re.escape(pat).replace('%', '.*')


for f in NEW:
    # Kommentare entfernen: sie stehen zwischen `proname = ...` und `prosrc
    # LIKE` und wuerden das Suchfenster sprengen - und der Check soll
    # schliesslich Code pruefen, nicht Prosa.
    c = strip_comments(read(f))
    for m in re.finditer(
            r"proname\s*(?:=\s*'([a-z_0-9]+)'|IN\s*\(([^)]*)\))"
            r"[\s\S]{0,400}?prosrc\s+(NOT\s+)?LIKE\s+(.+?)\)\s*(?:THEN|RAISE)",
            c, re.I | re.S):
        negated = bool(m.group(3))
        pattern = like_pattern(m.group(4))
        if len(pattern.replace('%', '')) < 3:
            continue
        rx = like_to_regex(pattern)
        names = ([m.group(1)] if m.group(1) else
                 re.findall(r"'([a-z_0-9]+)'", m.group(2) or ''))
        for n in names:
            n = n.lower()
            if n not in UNIVERSE:
                continue
            in_code = re.search(rx, strip_comments(UNIVERSE[n]), re.I | re.S)
            in_full = re.search(rx, UNIVERSE[n], re.I | re.S)
            if negated and in_code:
                flag('3 prossrc-Check', f,
                     f'{n}: NOT-LIKE-Muster "{pattern}" trifft den echten Code '
                     f'-> der Check wuerde beim Apply fehlschlagen')
            elif not negated and in_code is None and in_full:
                flag('3 prossrc-Check', f,
                     f'{n}: LIKE-Muster "{pattern}" trifft nur den Kommentar - '
                     f'prosrc enthaelt Kommentare, der Check loest falsch aus')


# ---------------------------------------------------------------- 4
for f in NEW:
    c = read(f)
    known = set()
    for g in ALL:
        if g.name >= f.name:
            break
        known |= {m.group(1).lower() for m in pat_fn.finditer(read(g))}
    here = [(m.start(), m.group(1).lower()) for m in pat_fn.finditer(c)]
    for pos, name in here:
        end = c.find('\n$$;', pos)
        if end < 0:
            continue
        body = c[pos:end]
        head = body.split('AS $$')[0] if 'AS $$' in body else body[:400]
        if not re.search(r'LANGUAGE\s+sql\b', head, re.I):
            continue
        for callee in {x.lower() for x in re.findall(r'\bpublic\.([a-z_][a-z0-9_]*)\s*\(', body, re.I)}:
            if callee == name:
                continue
            earlier = [n for p, n in here if p < pos]
            if callee in known or callee in earlier:
                continue
            flag('4 LANGUAGE sql', f,
                 f'{name}() ruft public.{callee}(), das erst SPÄTER in der '
                 f'Migration definiert wird -> 42883 beim CREATE')

# ---------------------------------------------------------------- 5
alldefs = []
for f in ALL:
    c = read(f)
    for m in pat_fn.finditer(c):
        ret, args = sig_at(c, m.start())
        alldefs.append((f.name, m.group(1).lower(), ret, args))

for f in NEW:
    prev = {}
    for fn_name, fname, ret, args in alldefs:
        if fn_name >= f.name:
            break
        prev[(fname, tuple(a[1] for a in args))] = (fname, ret, args)
    c = read(f)
    for m in pat_fn.finditer(c):
        name = m.group(1).lower()
        ret, args = sig_at(c, m.start())
        key = (name, tuple(a[1] for a in args))
        if key not in prev:
            continue
        _pn, pret, pargs = prev[key]
        if pret != ret:
            flag('5 Signatur', f, f'{name}: RETURNS {pret} -> {ret} (42P13)')
        if [a[0] for a in pargs] != [a[0] for a in args]:
            flag('5 Signatur', f,
                 f'{name}: Parameternamen {[a[0] for a in pargs]} -> '
                 f'{[a[0] for a in args]} (42P13)')

# ---------------------------------------------------------------- 6
for f in NEW:
    c = strip_comments(read(f))
    for m in re.finditer(r'RAISE\s+EXCEPTION\s+([A-Za-z_][A-Za-z0-9_]*)\s*;', c, re.I):
        flag('6 RAISE', f,
             f'RAISE EXCEPTION {m.group(1)} ohne Anfuehrungszeichen wird als '
             f'Condition-Name gelesen -> 42704 beim CREATE')

# ---------------------------------------------------------------- Ausgabe
print('PUSH-VORPRUEFUNG (Fehlerklassen aus dem Remote-Push 2026-09-26)\n' + '=' * 74)
if not findings:
    print('  Keine Befunde - alle sechs Klassen sind abgedeckt.')
else:
    for cls, fn, msg in findings:
        print(f'  [{cls}] {fn}')
        print(f'      {msg}\n')
    print('=' * 74)
    print(f'{len(findings)} Befund(e)')
sys.exit(1 if findings else 0)
