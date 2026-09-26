"""Selbsttest fuer check_push_readiness.py.

Ein Checker, der nie ausloest, ist wertlos. Fuer jede der sechs im
Remote-Push gefundenen Fehlerklassen wird eine Kopie der Migrationen
minimal muendlich gebrochen; der Checker MUSS dann anschlagen.

    python tool/check_push_readiness_selftest.py
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
CHECKER = REPO / 'tool' / 'check_push_readiness.py'


def m_anon_ohne_public(c):
    # format()-String des Sweeps: PUBLIC entfernen
    return c.replace(
        "'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated'",
        "'REVOKE EXECUTE ON FUNCTION %s FROM anon'", 1)


def m_overload_luecke(c):
    return c.replace(
        'REVOKE ALL ON FUNCTION public.profile_discovery_visible(uuid, uuid) '
        'FROM PUBLIC, anon, authenticated;', '', 1)


def m_prosrc_kommentar(c):
    # Muster OHNE Quotes: trifft auch das Wort im Kommentar des Bodies.
    # Das war der Originalfehler in 127 - die "sichere" chr(39)-Form ist
    # ausdruecklich NICHT die Fehlerklasse.
    return c.replace(
        "AND p.prosrc LIKE '%' || chr(39) || 'reason' || chr(39) || '%') THEN",
        "AND p.prosrc LIKE '%reason%') THEN", 1)


def m_language_sql(c):
    # LANGUAGE-sql-Funktion, die eine erst spaeter definierte Function ruft
    probe = ("CREATE OR REPLACE FUNCTION public.zz_selftest_probe()\n"
             "RETURNS boolean\n"
             "LANGUAGE sql\n"
             "AS $$ SELECT public.get_public_profiles('{}'::uuid[]) IS NOT NULL $$;\n\n")
    i = c.index('CREATE OR REPLACE FUNCTION')
    return c[:i] + probe + c[i:]


def m_rueckabetyp(c):
    return c.replace('CREATE OR REPLACE FUNCTION public.relay_ack(p_ids bigint[])\n'
                     'RETURNS void',
                     'CREATE OR REPLACE FUNCTION public.relay_ack(p_ids bigint[])\n'
                     'RETURNS jsonb', 1)


def m_raise_bare(c):
    return c.replace(
        "RAISE EXCEPTION USING\n"
        "      ERRCODE = '42501',\n"
        "      MESSAGE = 'auth_strength_insufficient';",
        "RAISE EXCEPTION auth_strength_insufficient;")


MUTATIONS = [
    ('1 PUBLIC-Revoke', 'REVOKE ... FROM anon ohne FROM PUBLIC',
     '123_revoke_public_execute.sql', m_anon_ohne_public),
    ('2 Overloads', 'eine Variante einer ueberladenen Function bleibt offen',
     '126_discovery_privacy_filters.sql', m_overload_luecke),
    ('3 prossrc-Check', 'Fail-Fast-Muster steht nur im Kommentar',
     '127_remaining_db_hardening.sql', m_prosrc_kommentar),
    ('4 LANGUAGE sql', 'spricht eine spaeter definierte Function an',
     '126_discovery_privacy_filters.sql', m_language_sql),
    ('5 Signatur', 'CREATE OR REPLACE aendert den Rueckabetyp',
     '128_server_side_auth_strength.sql', m_rueckabetyp),
    ('6 RAISE', 'RAISE EXCEPTION ohne Anfuehrungszeichen',
     '128_server_side_auth_strength.sql', m_raise_bare),
]

print('SELBSTTEST check_push_readiness.py\n' + '=' * 74)
fails = []

for cls, desc, target, mutate in MUTATIONS:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        shutil.copytree(REPO / 'supabase' / 'migrations',
                        root / 'supabase' / 'migrations')
        (root / 'tool').mkdir()
        shutil.copy(CHECKER, root / 'tool' / 'check_push_readiness.py')

        f = root / 'supabase' / 'migrations' / target
        original = f.read_text(encoding='utf-8', errors='replace')
        mutated = mutate(original)
        if mutated == original:
            fails.append((cls, 'Mutation wirkungslos - Test ungueltig'))
            print(f'  UNGUELTIG     {cls:16} Mutation hat nichts geaendert')
            continue
        f.write_text(mutated, encoding='utf-8', newline='\n')

        r = subprocess.run(
            [sys.executable, str(root / 'tool' / 'check_push_readiness.py')],
            capture_output=True, text=True)
        detected = r.returncode != 0 and cls in r.stdout
        print(f'  {"OK          " if detected else "NICHT ERKANNT"} {cls:16} {desc}')
        if detected:
            detail = next((l.strip() for l in r.stdout.splitlines()
                           if l.strip().startswith('[')), '')
            print(f'                -> {detail[:92]}')
        else:
            fails.append((cls, 'Checker erkennt den eingebauten Fehler nicht'))
            for l in [x for x in r.stdout.splitlines() if x.strip()][:5]:
                print(f'                {l.strip()[:92]}')

print('=' * 74)
if fails:
    print(f'{len(fails)} PROBLEM(E):')
    for cls, why in fails:
        print(f'  {cls}: {why}')
    sys.exit(1)
print(f'OK: alle {len(MUTATIONS)} Fehlerklassen werden erkannt '
      f'(und der reale Stand ist fehlerfrei)')
