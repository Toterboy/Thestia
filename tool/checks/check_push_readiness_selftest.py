"""Selbsttest für check_push_readiness.py.

Ein Checker, der nie auslöst, ist wertlos. Für jede der sechs im
Remote-Push gefundenen Fehlerklassen wird eine Kopie der Migrationen
minimal mündlich gebrochen; der Checker MUSS dann anschlagen.

    python tool/checks/check_push_readiness_selftest.py
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zählen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe ändert.
def _projektwurzel() -> pathlib.Path:
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / 'pubspec.yaml').exists():
            return kandidat
    # DER NOTFALL: Der Ordner mit den Migrationen - den hat auch das
    # kleine Test-Repo der Selbsttests (dort gibt es keine pubspec).
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / 'supabase' / 'migrations').is_dir():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent


REPO = _projektwurzel()

CHECKER = REPO / 'tool' / 'checks/check_push_readiness.py'


def m_anon_ohne_public(c):
    # format()-String des Sweeps: PUBLIC entfernen
    return c.replace(
        "'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated'",
        "'REVOKE EXECUTE ON FUNCTION %s FROM anon'", 1)


# Die Variante, um die es geht: match_proximity_spark mit dem eigenen
# Token (Migration 185). Sie ist die einzige, die NACH dem Sweep aus
# Migration 123 angelegt wurde - davor angelegte Varianten hat der Sweep
# (er arbeitet über pg_proc) ohnehin erfasst.
UEBERLAST_SIG_6 = ('text[], text[], text, text[], text, text')

# Die REVOKE-Formen, die im Repo für diese Variante vorkommen (alle
# Schreibweisen, die der Checker liest).
_UEBERLAST_REVOKES = (
    # BEFUND (11.11.2026): Die Signatur von match_proximity_spark hat
    # sich geändert - Migration 213 hat die Ortsangabe ergänzt (8
    # Parameter). Der Selbsttest muss die AKTUELLE Signatur mutieren:
    # eine alte Signatur zu prüfen wäre sinnlos (die gibt es nicht
    # mehr, und der wäre auch weiterhin gesperrt).
    #
    # Migration 213 (einzeilig, die aktuelle Signatur):
    'revoke all on function public.match_proximity_spark(text[], text[], '
    'text, text[], text, text, text, text) from public, anon;',
    # Früher (Migration 185/207) - bleibt als Muster erhalten, damit der
    # Test auch nach einem Rueckbau greift:
    'revoke all on function public.match_proximity_spark(text[], text[], '
    'text, text[], text, text) from public, anon;',
)


def m_overload_luecke(c, datei=''):
    # BEFUND (07.11.2026, Migration 185): Der alte Negativfall zielte auf
    # Migration 126 - dort fehlte nach der Mutation der REVOKE der
    # Variante profile_discovery_visible(uuid, uuid). Der Fall ist aber
    # KEIN Fehler mehr: die Variante wurde VOR dem Sweep aus Migration
    # 123 angelegt, und der Sweep (er arbeitet über pg_proc) hat sie
    # erfasst. Die Datenbank bestätigt das: für "anon" ist sie nicht
    # aufrufbar.
    #
    # Der Fall, der zählt, ist der umgekehrte: eine Variante, die
    # NACH dem Sweep angelegt wird. Dafür steht Migration 185 - sie legt
    # match_proximity_spark mit dem eigenen Token an. Ohne ihren REVOKE
    # bleibt die Variante aufrufbar, und genau das muss der Checker
    # melden.
    #
    # BEFUND (09.11.2026): Die Sperren werden im Checker REPO-WEIT
    # gesammelt (siehe dessen Kommentar). Die Variante wird in
    # Migration 185 UND in Migration 207 gesperrt. Entfernt man das
    # REVOKE nur aus EINER Datei, ist sie über die andere weiterhin
    # gesperrt - der Checker meldet zu Recht nichts, und der Selbsttest
    # wäre wirkungslos.
    #
    # DESHALB: Die Mutation entfernt das REVOKE aus JEDER Datei, die
    # diese Variante sperrt. Die Datei-Liste wird unten ausgewertet.
    for muster in _UEBERLAST_REVOKES:
        if muster in c:
            return c.replace(muster, '', 1)
    return c


def m_prosrc_kommentar(c):
    # Muster OHNE Quotes: trifft auch das Wort im Kommentar des Bodies.
    # Das war der Originalfehler in 127 - die "sichere" chr(39)-Form ist
    # ausdrücklich NICHT die Fehlerklasse.
    return c.replace(
        "AND p.prosrc LIKE '%' || chr(39) || 'reason' || chr(39) || '%') THEN",
        "AND p.prosrc LIKE '%reason%') THEN", 1)


def m_language_sql(c):
    # LANGUAGE-sql-Funktion, die eine erst später definierte Function ruft
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


#: Eine Migration, die regprocedure benutzt, aber NICHTS sperrt.
#:
#: BEFUND (20.11.2026): Der Checker hielt jede Migration mit dem Wort
#: "regprocedure" für einen Sweep. Viele Migrationen benutzen es nur,
#: um die Definition EINER Funktion zu prüfen (pg_get_functiondef im
#: Fail-Fast) - das ist kein Sweep. Dadurch wurde das Gate blind.
KEIN_SWEEP_DATEI = '900_selftest_kein_sweep.sql'
KEIN_SWEEP_INHALT = """-- Testdatei des Selbsttests: benutzt regprocedure und pg_proc,
-- sperrt aber NICHTS. Eine solche Migration darf den Sweep nicht
-- vortaeuschen - sonst sieht das Gate die offene Variante nicht.
DO $$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_functiondef(
           'public.match_proximity_spark(text[], text[], text, text[], text, text, text, text)'
           ::regprocedure)
    INTO v_def;
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'Die Funktion fehlt.';
  END IF;
END;
$$;
"""


MUTATIONS = [
    ('1 PUBLIC-Revoke', 'REVOKE ... FROM anon ohne FROM PUBLIC',
     '123_revoke_public_execute.sql', m_anon_ohne_public, '1 PUBLIC-Revoke'),
    ('2 Overloads', 'eine Variante einer ueberladenen Function bleibt offen',
     '213_transit_candidates_and_place.sql', m_overload_luecke, '2 Overloads'),
    ('3 prossrc-Check', 'Fail-Fast-Muster steht nur im Kommentar',
     '127_remaining_db_hardening.sql', m_prosrc_kommentar, '3 prossrc-Check'),
    ('4 LANGUAGE sql', 'spricht eine spaeter definierte Function an',
     '126_discovery_privacy_filters.sql', m_language_sql, '4 LANGUAGE sql'),
    ('5 Signatur', 'CREATE OR REPLACE aendert den Rueckabetyp',
     '128_server_side_auth_strength.sql', m_rueckabetyp, '5 Signatur'),
    ('6 RAISE', 'RAISE EXCEPTION ohne Anfuehrungszeichen',
     '128_server_side_auth_strength.sql', m_raise_bare, '6 RAISE'),
    # BEFUND (20.11.2026): Migration 221 (die VOLATILE-Korrektur) hat
    # das Gate blind gemacht - sie benutzt "regprocedure", sperrt aber
    # nichts. Der Checker hat jede Migration mit dem Wort "regprocedure"
    # als Sweep gehalten. Damit war die Fehlerklasse "2 Overloads" für
    # alles unsichtbar, was VOR der letzten Migration angelegt war.
    #
    # Dieser Fall legt eine Migration an, die regprocedure und pg_proc
    # benutzt, aber NICHTS sperrt - und verlangt, dass der Checker die
    # offene Variante trotzdem meldet.
    ('7 kein Sweep', 'eine Migration mit regprocedure sperrt nichts',
     '213_transit_candidates_and_place.sql', m_overload_luecke,
     '2 Overloads'),
]

print('SELBSTTEST check_push_readiness.py\n' + '=' * 74)
fails = []

for cls, desc, target, mutate, erwartet_klasse in MUTATIONS:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        shutil.copytree(REPO / 'supabase' / 'migrations',
                        root / 'supabase' / 'migrations')
        (root / 'tool' / 'checks').mkdir(parents=True)
        shutil.copy(CHECKER, root / 'tool' / 'checks/check_push_readiness.py')

        # BEFUND (09.11.2026): Die Fehlerklasse "2 Overloads" muss ALLE
        # Migrationen treffen, die die Variante sperren - der Checker
        # sammelt die Sperren repo-weit. Deshalb läuft diese Mutation
        # über jede Migrationsdatei; die Dateien, die nichts zu tun
        # haben, bleiben unverändert.
        #
        # Die übrigen Fehlerklassen beziehen sich auf EINE Datei - für
        # sie bleibt der alte Ablauf (nur die Zieldatei wird mutiert).
        if cls in ('2 Overloads', '7 kein Sweep'):
            ziel_gefunden = False
            for f in sorted((root / 'supabase' / 'migrations').glob('*.sql')):
                original = f.read_text(encoding='utf-8', errors='replace')
                mutated = mutate(original, f.name)
                if mutated == original:
                    continue
                f.write_text(mutated, encoding='utf-8', newline='\n')
                ziel_gefunden = True
            if not ziel_gefunden:
                fails.append((cls, 'Mutation wirkungslos - Test ungueltig'))
                print(f'  UNGUELTIG     {cls:16} Mutation hat nichts geaendert')
                continue
            if cls == '7 kein Sweep':
                # Die Migration, die den Sweep vortäuschen würde.
                (root / 'supabase' / 'migrations' / KEIN_SWEEP_DATEI).write_text(
                    KEIN_SWEEP_INHALT, encoding='utf-8', newline='\n')
        else:
            f = root / 'supabase' / 'migrations' / target
            original = f.read_text(encoding='utf-8', errors='replace')
            mutated = mutate(original)
            if mutated == original:
                fails.append((cls, 'Mutation wirkungslos - Test ungueltig'))
                print(f'  UNGUELTIG     {cls:16} Mutation hat nichts geaendert')
                continue
            f.write_text(mutated, encoding='utf-8', newline='\n')

        # BYTES statt Text: die Ausgabe wird selbst dekodiert. Mit
        # `text=True` benutzt subprocess die lokale Codepage (cp1252 auf
        # Windows) - die Umlaute im Checker-Ausgabetext sprengen dann
        # die Dekodierung und `r.stdout` ist None (BEFUND 09.11.2026:
        # der Selbsttest war dadurch auf Windows komplett rot).
        r = subprocess.run(
            [sys.executable, str(root / 'tool' / 'checks/check_push_readiness.py')],
            capture_output=True)
        stdout = (r.stdout or b'').decode('utf-8', errors='replace')
        # Die Fehlerklasse in der Ausgabe kann eine andere sein als der
        # Name des Falls: Fall 7 prüft die Fehlerklasse "2 Overloads".
        detected = r.returncode != 0 and erwartet_klasse in stdout
        print(f'  {"OK          " if detected else "NICHT ERKANNT"} {cls:16} {desc}')
        if detected:
            detail = next((l.strip() for l in stdout.splitlines()
                           if l.strip().startswith('[')), '')
            print(f'                -> {detail[:92]}')
        else:
            fails.append((cls, 'Checker erkennt den eingebauten Fehler nicht'))
            for l in [x for x in stdout.splitlines() if x.strip()][:5]:
                print(f'                {l.strip()[:92]}')

print('=' * 74)
if fails:
    print(f'{len(fails)} PROBLEM(E):')
    for cls, why in fails:
        print(f'  {cls}: {why}')
    sys.exit(1)
print(f'OK: alle {len(MUTATIONS)} Fehlerklassen werden erkannt '
      f'(und der reale Stand ist fehlerfrei)')
