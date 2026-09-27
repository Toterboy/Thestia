"""Negativtest fuer tool/check_migrations_sql.py.

Die Umgehung in Abschnitt 2b (sqlglot-Parserluecke bei
LANGUAGE sql SECURITY DEFINER) darf den Check nicht entschaerfen. Der
Test laesst bewusst kaputte SQL durch dieselbe Pipeline laufen und
verlangt, dass die vorhandenen Schritte anschlagen.

Aufruf: python tool/check_migrations_sql_selftest.py
"""
import re
import sys

import sqlglot

CASES = [
    (
        'gueltige Funktion mit LANGUAGE sql SECURITY DEFINER',
        'CREATE OR REPLACE FUNCTION public.f() RETURNS jsonb\n'
        'LANGUAGE sql SECURITY DEFINER\n'
        'AS $$ SELECT 1; $$;\n',
        False,
        None,
    ),
    (
        'unbalancierte Klammer',
        'CREATE TABLE public.t (\n  id uuid PRIMARY KEY ;\n',
        True,
        'FEHLER',
    ),
    (
        'unbalanciertes Dollar-Quoting',
        'CREATE OR REPLACE FUNCTION public.f() RETURNS int AS $$ SELECT 1;\n',
        True,
        'FEHLER',
    ),
    (
        'Klammerfehler trotz intakter Funktion drumherum',
        'CREATE OR REPLACE FUNCTION public.f() RETURNS jsonb\n'
        'LANGUAGE sql SECURITY DEFINER\n'
        'AS $$ SELECT 1; $$;\n'
        'CREATE TABLE public.t ( id uuid PRIMARY KEY;\n',
        True,
        'FEHLER',
    ),
]


def pipeline(sql: str) -> tuple[bool, str]:
    """ dieselbe Logik wie in check_migrations_sql.check() """
    if sql.count('$$') % 2 != 0:
        return False, 'FEHLER: Dollar-Quotes unausbalanciert'
    merged = re.sub(r'\$\$.*?\$\$', '$$ DOLLAR_BODY $$', sql, flags=re.S)
    prev = None
    while prev != merged:
        prev = merged
        merged = re.sub(
            r"('(?:[^']|'')*')(\s*\n\s*|\s*\|\|\s*)('(?:[^']|'')*')",
            r'\1&&\3', merged)
    merged = merged.replace('&&', '')
    no_strings = re.sub(r"'(?:[^']|'')*'", "''", merged)
    no_strings = re.sub(r'--[^\n]*', '', no_strings)
    if no_strings.count('(') != no_strings.count(')'):
        return False, 'FEHLER: Klammern unausbalanciert'
    merged = re.sub(r'(LANGUAGE\s+sql)\s+(SECURITY\s+DEFINER)',
                    r'\1 SET search_path = pg_temp \2', merged, flags=re.I)
    try:
        sqlglot.parse(merged, read='postgres')
    except Exception as e:  # noqa: BLE001
        return False, f'FEHLER: Parse {str(e)[:60]}'
    return True, 'OK'


def main() -> int:
    print('=' * 72)
    print('NEGATIVTEST check_migrations_sql')
    print(f'sqlglot {sqlglot.__version__}')
    print('=' * 72)
    bad = 0
    for name, sql, should_fail, expect in CASES:
        # pipeline liefert (bestanden, Meldung) - nicht (fehlgeschlagen, ...)
        passed, msg = pipeline(sql)
        ok = (passed == (not should_fail))
        if not ok:
            bad += 1
        verdict = 'durchgelassen' if passed else f'erkannt ({msg})'
        print(f'  [{"OK  " if ok else "FEHL"}] {name}')
        print(f'         erwartet: {"Fehler" if should_fail else "kein Fehler"}'
              f'  ->  {verdict}')
        if should_fail and not expect:
            print('         (kein Meldungstext erwartet)')
    print()
    if bad:
        print(f'{bad} Fall(e) falsch - der Check ist nicht mehr aussagekraeftig.')
        return 1
    print('OK: der Check erkennt weiterhin echte Fehler, und die gueltige')
    print('    LANGUAGE sql SECURITY DEFINER -Variante laeuft durch.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
