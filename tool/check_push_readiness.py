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
import os
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
# Welche Signaturen hat WELCHE Migration angelegt? Das braucht die
# Regel unten: wer eine Variante anlegt, muss sie auch sperren.
angelegt_pro_datei = {}
for f in ALL:
    # WICHTIG: mit strip_comments. Sonst zaehlt eine AUSKOMMENTIERTE
    # Definition als Ueberladung - eine Migration, die in ihrem
    # Kommentar ein Beispiel fuer eine alte Signatur nennt, erzeugt so
    # ein Phantom, und der Check meldet eine Variante als offen, die
    # es nie gab. Genau das ist passiert: die Erklaerung in Migration
    # 145 nennt die alte Signatur, und der Check flaggte daraufhin
    # genau diese - obwohl sie im Kommentar stand.
    c = strip_comments(read(f))
    angelegt_hier = {}
    for m in pat_fn.finditer(c):
        _, args = sig_at(c, m.start())
        sig = tuple(a[1] for a in args)
        name = m.group(1).lower()
        overloads.setdefault(name, set()).add(sig)
        angelegt_hier.setdefault(name, set()).add(sig)
    angelegt_pro_datei[f] = angelegt_hier
multi = {k for k, v in overloads.items() if len(v) > 1}

# Der erste dynamische Sweep (Migration 123). Alles, was VOR ihm
# angelegt wurde, hat er erfasst - er arbeitet ueber pg_proc und
# damit ueber den ganzen Bestand zur Zeit der Migration. Die statische
# Analyse sieht diese Sperren nicht (im Quelltext steht kein
# "REVOKE ... FUNCTION <name>(<typen>)" fuer sie).
#
# BEFUND (07.11.2026): Ohne diese Ausnahme meldete das Gate fuenf
# Varianten als offen, die live nachweislich fuer "anon" gesperrt
# sind (cool_match, end_match, hide_match, respark_match,
# quiz_pick_personalized - alle mit der bigint-Signatur aus der
# alten Generation).
# Die Indizes aller Sweeps. Ein Sweep arbeitet ueber pg_proc und
# erfasst damit den ganzen Bestand zur Zeit der Migration.
sweep_indizes = [i for i, f_sweep in enumerate(ALL)
                 if 'regprocedure' in strip_comments(read(f_sweep))]

# Wann wurde jede Variante zum LETZTEN angelegt? (CREATE OR REPLACE
# kann dieselbe Signatur mehrfach anlegen - massgeblich ist der letzte
# Anlage-Index.)
angelegt_index = {}
for i, f_anl in enumerate(ALL):
    c = strip_comments(read(f_anl))
    for m in re.finditer(
            r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-z_0-9]+)\s*\(',
            c, re.I):
        _, args = sig_at(c, m.start())
        angelegt_index[(m.group(1).lower(),
                        tuple(a[1] for a in args))] = i


def durch_sweep_gesperrt(name, sig):
    """Hat ein Sweep diese Variante erfasst?

    Der Sweep muss NACH ihrer Anlage laufen - sonst kann er sie nicht
    erfasst haben."""
    idx = angelegt_index.get((name, sig))
    if idx is None:
        return False
    return any(s > idx for s in sweep_indizes)

# Alle REVOKEs, ueber ALLE Migrationen gesammelt.
#
# WARUM alle und nicht nur die ab 123: Die historischen Sperren
# (Migration 123, 131, 156) zaehlen natuerlich auch - eine Variante,
# die dort gesperrt wurde, ist gesperrt. Die Regel unten ist
# repo-weit: es zaehlt, ob eine Variante aufrufbar ist, nicht ob eine
# bestimmte Datei sie selbst sperrt.
alle_revokes = {}
for f2 in ALL:
    code2 = strip_comments(read(f2))
    for m in re.finditer(
            r'REVOKE[^;]*?ON\s+FUNCTION\s+(?:public\.)?([a-z_0-9]+)\s*\(([^)]*)\)',
            code2, re.I | re.S):
        nm = m.group(1).lower()
        types = tuple(
            re.sub(r'\s+', ' ', re.split(r'\bDEFAULT\b', a, flags=re.I)[0]
                   .strip().lower()).split()[-1]
            for a in split_top(m.group(2)))
        alle_revokes.setdefault(nm, set()).add(types)

# Per Signatur gedroppte Überladungen gelten als unschädlich: ein
# DROP entfernt die aufrufbare Variante vollständig, ein Revoke
# allein nicht. Sonst würde jede saubere Bereinigung (Migration 131
# droppt die alten match_proximity_spark-Signaturen) fälschlich als
# offene Variante gemeldet - und die alte Signatur würde nur
# zusätzlich REVOKt, obwohl es sie nicht mehr gibt.
#
# BUG (gefunden am 24.10.2026, in der CI sichtbar): Diese Sammlung stand
# INNERHALB der Datei-Schleife und wurde pro Datei neu geleert. Die im
# Kommentar beschriebene Ausnahme ("Migration 131 dropt die alten
# Signaturen") hat damit nie gegriffen: als Migration 156 die Rechte
# der FUNKTIONIERENDEN Variante verengte, war der `dropped`-Stand leer
# und die seit 131 geloeschten Signaturen wurden als "weiter aufrufbar"
# gemeldet. Die Sammlung laeuft jetzt ueber ALLE Migrationen, genau wie
# `overloads` - ein DROP irgendwo entfernet die Variante fuer alles,
# was danach kommt.
dropped = {}
for f in ALL:
    code_d = strip_comments(read(f))
    for m in re.finditer(
            r'DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(?:public\.)?([a-z_0-9]+)\s*\(([^)]*)\)',
            code_d, re.I | re.S):
        name = m.group(1).lower()
        types = tuple(
            re.sub(r'\s+', ' ', re.split(r'\bDEFAULT\b', a, flags=re.I)[0]
                   .strip().lower()).split()[-1]
            for a in split_top(m.group(2)))
        dropped.setdefault(name, set()).add(types)

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

# Die Regel (BEFUND 07.11.2026, Migration 185):
#
#   Jede Variante, die irgendeine Migration ANLEGT, muss gesperrt
#   werden - von der Datei selbst oder von einer anderen. Ab ihrer
#   Anlage ist sie aufrufbar; eine Sperre, die erst in einer spaeteren
#   Migration kommt, ist zu spaet.
#
#   Der alte Check verglich jede Datei mit ALLEN jemals angelegten
#   Signaturen und verlangte, dass jede Datei ALLE Sperren selbst
#   enthaelt. Das ist formal falsch: eine Migration kann keine
#   Signatur revoken, die es noch gar nicht gibt. Er meldete deshalb
#   Migration 131 und 156 als fehlerhaft, obwohl die dortige Sperre
#   vollstaendig war - und Migration 185 als fehlerhaft, weil sie nur
#   ihre EIGENE Variante sperrte (die andere war schon in 156
#   gesperrt).
#
#   Geprueft wird jetzt repo-weit: eine Variante, die angelegt, nicht
#   gedroppt und NIRGENDS gesperrt wurde, bleibt aufrufbar - genau
#   das ist der Befund.
#
#   Ein Gate, das immer anschlaegt, wird irgendwann ignoriert.
for name, sigs in overloads.items():
    if name not in multi:
        continue
    offen = (sigs - alle_revokes.get(name, set())) - dropped.get(name, set())
    offen = set(s for s in offen
                if not durch_sweep_gesperrt(name, s))
    if offen:
        pretty = ', '.join('(' + ', '.join(s) + ')' for s in sorted(offen))
        flag('2 Overloads', MIG / 'alle',
             f'{name}: {pretty} wird nirgends revokt - diese Variante(n) '
             f'bleiben aufrufbar')


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

def _droppt_davor(sql: str, name: str, args) -> bool:
    """Steht in dieser Datei ein DROP FUNCTION mit genau dieser Signatur?

    Nur dann ist eine Signaturaenderung zulaessig: CREATE OR REPLACE
    kann den Rueckgabetyp nicht aendern (42P13/42804), ein
    vorausgehendes DROP dagegen schon.

    Wichtig fuer den Fall, dass die Argumente umbenannt werden: der
    DROP nennt die ALTEN Namen - deshalb wird nur der Typ verglichen.
    """
    for m in re.finditer(
            r'DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(?:public\.)?'
            r'([a-z_0-9]+)\s*\(([^)]*)\)',
            sql, re.I):
        if m.group(1).lower() != name.lower():
            continue
        drop_typen = [x.strip().lower() for x in m.group(2).split(",") if x.strip()]
        eigene = [a[1].lower() for a in args]
        if drop_typen == eigene:
            return True
    return False


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
        # WICHTIG (07.11.2026): Eine Signatur darf sich nur mit einem
        # DROP davor aendern - "CREATE OR REPLACE" kann den
        # Rueckgabetyp nicht aendern (42P13/42804). Der legitime Weg
        # ist also: DROP FUNCTION ...; CREATE FUNCTION ...
        #
        # Deshalb wird hier NICHT gemeldet, wenn die Migration die
        # Funktion vorher mit derselben Signatur droppt. Sonst wuerde
        # der Checker jede echte, korrekte Signaturaenderung als
        # Fehler melden.
        #
        # ACHTUNG: Nach dem DROP sind die RECHTE der Funktion weg (sie
        # haengen am Objekt, nicht an der Definition). Die MIGRATION
        # muss sie wieder setzen - sonst ist die Funktion fuer "anon"
        # offen. Das prueft tool/check_function_grants.py.
        if _droppt_davor(c, name, args):
            continue
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
