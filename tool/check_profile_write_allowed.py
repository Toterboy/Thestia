#!/usr/bin/env python3
"""Prueft, ob das Profil-Speichern der App die Datenbank wirklich akzeptiert.

WARUM (13.11.2026, Betreiber: "Server Sync schlaegt fehl, wenn ich mein
Profil anpasse"):

   Ein PostgREST-UPDATE ist ATOMAR. Ein EINZIGES Feld, das der
   CHECK-Constraint ablehnt, macht das GANZE Update unmoeglich - und
   weil der Profil-Editor viele Felder in einem Rutsch schreibt, war
   damit auch der Name, die Bio und die Vorstellung nicht zu speichern.
   Der Betreiber sah nur "Server-Sync fehlgeschlagen".

   Der Fehler war ein Dart-Enum-Name ('distanceKm') anstelle des
   DB-Werts ('distance_km') - und ein Bundesland in `preferred_state`,
   dessen Spalte nur Beziehungswerte kennt.

DAS WERKZEUG macht den Schreibvorgang der App NACH:

   1. Es setzt die JWT-Claims eines Testkontos und wechselt in die
      Rolle `authenticated` - die RLS gilt also genau wie in der App.
   2. Es schreibt denselben Body, den der Profil-Editor schickt.
   3. Alles laeuft in einer Transaktion, die am Ende ZURUECKGEROLLT
      wird - die Produktivdaten werden nicht veraendert.

   Bricht der Schreibvorgang ab (CHECK-Constraint, fehlende Spalte,
   RLS), meldet das Werkzeug die Ursache und endet mit Exitcode 1.

Aufruf::

    python tool/check_profile_write_allowed.py

Der Testkonto ist das des Betreibers (46f3f558-...). Es wird nichts
veraendert - die Transaktion wird zurueckgerollt.
"""

import pathlib
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Das Testkonto (der Betreiber). Es wird nur zum SCHREIBEN benutzt -
# die Transaktion wird zurueckgerollt.
KONTO = "46f3f558-b134-4d25-946b-4e052a8ab3b5"

# Der Body aus dem Profil-Editor (lib/screens/profile/profile_edit_screen.dart).
# Die Werte sind die, die die App bei einem normalen Speichern schickt.
#
# WICHTIG: Der Body wird hier per TEXT geprueft - nicht per Import aus
# dem Dart-Code. Das Werkzeug soll den SERVER pruefen, nicht den
# Client. Dass der Client genau das schickt, sichert der Test
# test/profile_server_values_test.dart ab.
BODY = """
  bio = 'Pruef-Bio',
  name = 'Pruef-Name',
  state = 'Bremen',
  interests = '["Musik"]'::jsonb,
  intro_text = 'Pruef-Text',
  intro_audio_path = NULL,
  country = 'Deutschland',
  smoking = 'never',
  alcohol = 'occasionally',
  drugs = 'never',
  music_liked = ARRAY[]::text[],
  music_disliked = ARRAY[]::text[],
  favorite_song = '',
  favorite_band = '',
  birthday_style = 'midnight',
  habits_dealbreaker = false,
  photos = ARRAY[]::text[],
  max_distance_km = 100,
  distance_filter_mode = 'distance_km',
  preferred_state = NULL
"""

# Was der Client fuer preferred_state schickt, wenn dort ein BUNDESLAND
# steht (der Wert, der das Update kippen würde). Die Spalte kennt nur
# die Beziehungswerte - das Bundesland wird verworfen.
BODY_MIT_BUNDESLAND = BODY.replace(
    "preferred_state = NULL", "preferred_state = 'Bremen'"
)


def sql_bauen(body: str) -> str:
    return f"""
begin;
select set_config('request.jwt.claims',
  '{{"role":"authenticated","sub":"{KONTO}"}}', true);
select set_config('request.jwt.claim.sub', '{KONTO}', true);
set local role authenticated;
update public.profiles set
{body}
 where user_id = '{KONTO}';
rollback;
"""


def ausfuehren(sql: str) -> tuple[bool, str]:
    datei = ROOT / "_tmp_profile_write_check.sql"
    datei.write_text(sql, encoding="utf-8", newline="\n")
    # Auf Windows heisst der CLI-Aufruf "supabase.cmd" (der Rest ist ein
    # Shell-Skript) - dieselbe Form wie in den anderen Werkzeugen.
    cli = "supabase.cmd" if sys.platform == "win32" else "supabase"
    try:
        ergebnis = subprocess.run(
            [cli, "db", "query", "--linked", "--file", str(datei)],
            capture_output=True,
            text=True,
            cwd=str(ROOT),
            timeout=180,
        )
    except FileNotFoundError:
        print(
            "  (Das Supabase-CLI wurde nicht gefunden - der Test "
            "braucht es.)"
        )
        return True, ""
    finally:
        datei.unlink(missing_ok=True)
    text = (ergebnis.stdout or "") + (ergebnis.stderr or "")
    ok = ergebnis.returncode == 0 and "ERROR" not in text.upper()
    return ok, text.strip()


def ursache(text: str) -> str:
    """Die Fehlermeldung der Datenbank herausziehen."""
    treffer = re.search(r"(violates check constraint[^\\\"\\\\]*)", text)
    if treffer:
        return treffer.group(1).strip()
    treffer2 = re.search(r'ERROR: ([^"\\]*(?:\\.[^"\\]*)*)', text)
    if treffer2:
        return treffer2.group(1).strip()
    for zeile in text.splitlines():
        if "ERROR" in zeile.upper():
            return zeile.strip()
    return text.strip()[:300]


def main() -> int:
    print("=" * 70)
    print("PROFIL-SPEICHERN: nimmt die Datenbank den Schreibvorgang an?")
    print("=" * 70)
    print()
    print(f"  Testkonto: {KONTO}")
    print("  Die Transaktion wird zurueckgerollt - es wird nichts")
    print("  veraendert.")
    print()

    fehler = 0

    # (a) DER Body, den die App HEUTE schickt - der muss angenommen
    #     werden. Sonst kann der Betreiber sein Profil nicht speichern.
    ok, text = ausfuehren(sql_bauen(BODY))
    if ok:
        print("  OK    der Body, den der Profil-Editor heute schickt")
    else:
        fehler += 1
        print("  FEHLER der Body, den der Profil-Editor heute schickt")
        print(f"        {ursache(text)}")

    # (b) DER KÖDER: preferred_state mit einem Bundesland. Das ist der
    #     alte Fehler - er MUSS abgelehnt werden. Wird er
    #     angenommen, stimmt die CHECK-Constraint nicht mehr und das
    #     Werkzeug sagt einem anderen Fehler nach.
    ok2, text2 = ausfuehren(sql_bauen(BODY_MIT_BUNDESLAND))
    if ok2:
        fehler += 1
        print(
            "  FEHLER preferred_state mit einem Bundesland wird "
            "angenommen -"
        )
        print(
            "        die CHECK-Constraint gilt nicht mehr (dann ist "
            "etwas anderes"
        )
        print("        kaputt - das bitte melden).")
    else:
        print(
            "  OK    preferred_state mit einem Bundesland wird abgelehnt"
        )
        print(f"        ({ursache(text2)})")

    print()
    if fehler:
        print(
            "FEHLER: der Schreibvorgang der App wird von der Datenbank "
            "abgelehnt."
        )
        print(
            "  Ein PostgREST-UPDATE ist atomar - ein abgelehntes Feld "
            "kippt das"
        )
        print("  GANZE Update (Name, Bio, Vorstellung ...).")
        return 1

    print("OK: die Datenbank nimmt den Profil-Schreibvorgang an.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
