#!/usr/bin/env python3
"""Belegt live, dass der Transit-Funke auf der Gegenseite sichtbar wird.

BEFUND (07.11.2026, Betreiber): "Der Funke entsteht, aber es ist nichts
sichtbar."

DIE URSACHE (live geprueft, nicht vermutet): Die Paarung
public.match_proximity_spark meldete den Treffer nur dem ABSENDER.
Fuer die GEGENSEITE entstand kein sichtbarer Eintrag: kein Soft-Ping,
keine Meldung. Der Match lag zwar in der Datenbank (die Likes), aber
ohne Realtime blieb ihre Chatliste alt.

Zusaetzlich fehlte der Rolle `authenticated` das Ausfuehrungsrecht fuer
`accept_soft_ping` - das Annehmen schlug mit 403 fehl.

WENN DIESES SKRIPT SCHREIBT: Es legt Testzeilen in der Produktivdatenbank
an (Signale, einen Soft-Ping, beidseitige Likes und einen Match
zwischen den beiden Testkonten) und raeumt sie danach wieder weg. Der
Aufruf braucht deshalb ein ausdrueckliches `--yes`, und das Aufraeumen
laeuft immer - auch wenn mitten im Lauf etwas schiefgeht.

Aufruf::

    python tool/check_live_transit_flow.py --yes

Nach dem Lauf ist die Datenbank wieder im Ausgangszustand (das Skript
prueft das am Ende und meldet es).
"""

import json
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Die beiden Testkonten (siehe die Projekt-Dokumentation).
NUTZER_A = "46f3f558-b134-4d25-946b-4e052a8ab3b5"
NUTZER_B = "d177d5f9-f2d0-420e-981b-4d6ef5b77056"

# Feste Test-Tokens: 20 Hexzeichen, wie die RPC es verlangt. Sie
# erkennt die Testzeilen wieder und raeumt genau sie weg.
TOKEN_A = "1111111111111111aaaa"
TOKEN_B = "2222222222222222bbbb"

# Zwei gueltige Merkmale (aus dem Server-Katalog).
TAGS = ["hair_color", "sneaker"]


def env_laden() -> dict:
    werte = {}
    p = ROOT / ".env"
    if not p.exists():
        return werte
    for zeile in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in zeile and not zeile.strip().startswith("#"):
            k, v = zeile.split("=", 1)
            werte[k.strip()] = v.strip()
    return werte


ENV = env_laden()
URL = ENV.get("SUPABASE_URL", "").rstrip("/")
PUBLIC = ENV.get("SUPABASE_PUBLISHABLE_KEY", "")
SERVICE = (
    ENV.get("SUPABASE_SECRET_KEY_NEW")
    or ENV.get("SUPABASE_SECRET_KEY")
    or ENV.get("SUPABASE_SERVICE_ROLE_KEY", "")
)


def http(method, pfad, daten=None, kopf=None, timeout=40):
    body = json.dumps(daten).encode("utf-8") if daten is not None else None
    h = dict(kopf or {})
    if body is not None:
        h["Content-Type"] = "application/json"
    r = urllib.request.Request(URL + pfad, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as a:
            return a.status, a.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # noqa: BLE001
        return None, str(e).encode("utf-8", errors="replace")


def sitzung(user_id: str) -> str | None:
    """Holt eine echte Sitzung fuer den Testnutzer (Admin-Magic-Link)."""
    st, roh = http(
        "GET",
        "/auth/v1/admin/users?per_page=50",
        kopf={"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}"},
    )
    if st != 200:
        return None
    ziel = next(
        (u for u in json.loads(roh)["users"] if u.get("id") == user_id), None
    )
    if ziel is None:
        return None
    st, roh = http(
        "POST",
        "/auth/v1/admin/generate_link",
        {"type": "magiclink", "email": ziel["email"]},
        {"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}"},
    )
    if st != 200:
        return None
    hash_ = json.loads(roh).get("hashed_token")
    if not hash_:
        return None
    st, roh = http(
        "POST",
        "/auth/v1/verify",
        {"type": "magiclink", "token_hash": hash_},
        {"apikey": PUBLIC},
    )
    if st != 200:
        return None
    return json.loads(roh).get("access_token")


def sql(text: str):
    pfad = ROOT / "supabase" / "_pruef_transit_flow.sql"
    pfad.write_text(text, encoding="utf-8")
    ergebnis = subprocess.run(
        ["supabase.cmd", "db", "query", "--linked", "--file", str(pfad)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    pfad.unlink(missing_ok=True)
    kombi = ergebnis.stdout + ergebnis.stderr
    start = kombi.find("\n{")
    if start < 0:
        start = kombi.find("{")
    if start < 0:
        return None
    zeile = kombi[start:]
    try:
        obj = json.loads(zeile[:zeile.rfind("}") + 1])
    except Exception:  # noqa: BLE001
        return None
    if obj.get("_tag") == "Error":
        return None
    return obj.get("rows", [])


def aufraeumen() -> None:
    """Entfernt die Testzeilen - Signale, Pings, Likes und den Match."""
    sql(
        """
DELETE FROM public.transit_signals
 WHERE self_token IN ('{a}', '{b}');
DELETE FROM public.transit_soft_pings
 WHERE encounter_token IN ('{a}', '{b}');
DELETE FROM public.matches
 WHERE ((user_one_id = '{ua}' AND user_two_id = '{ub}')
     OR (user_one_id = '{ub}' AND user_two_id = '{ua}'))
   AND created_at > now() - interval '30 minutes';
DELETE FROM public.likes
 WHERE ((user_id = '{ua}' AND liked_user_id = '{ub}')
     OR (user_id = '{ub}' AND liked_user_id = '{ua}'))
   AND created_at > now() - interval '30 minutes';
""".format(a=TOKEN_A, b=TOKEN_B, ua=NUTZER_A, ub=NUTZER_B)
    )


def main() -> int:
    if "--yes" not in sys.argv:
        print(__doc__)
        print("  Zum Ausfuehren: python tool/check_live_transit_flow.py --yes")
        return 2

    if not URL or not PUBLIC or not SERVICE:
        print("  ! .env fehlt oder ist unvollstaendig.")
        return 1

    print("=" * 70)
    print("LIVE: wird der Transit-Funke auf der Gegenseite sichtbar?")
    print("=" * 70)
    print()
    print("  Achtung: Das Skript legt Testzeilen in der Produktivdatenbank")
    print("  an und raeumt sie danach wieder weg.")

    token_a = sitzung(NUTZER_A)
    token_b = sitzung(NUTZER_B)
    if not token_a or not token_b:
        print("  ! Keine Sitzung fuer die Testkonten.")
        return 1

    kopf_a = {"apikey": PUBLIC, "Authorization": f"Bearer {token_a}"}
    kopf_b = {"apikey": PUBLIC, "Authorization": f"Bearer {token_b}"}

    fehler = 0
    try:
        # Vorher aufraeumen (ein voriger Lauf kann unterbrochen worden sein).
        aufraeumen()

        # 1) B funkt.
        st, roh = http(
            "POST",
            "/rest/v1/rpc/match_proximity_spark",
            {
                "p_tokens": [TOKEN_A],
                "p_tags": TAGS,
                "p_mode": "transit",
                "p_self_tags": [],
                "p_self_note": "Live-Nachweis",
                "p_self_token": TOKEN_B,
            },
            kopf_b,
        )
        if st != 200:
            print()
            print("  1) B funkt: HTTP %s %s"
                  % (st, roh[:160].decode("utf-8", "replace")))
            fehler += 1
        else:
            print()
            print("  1) B funkt: gespeichert (noch kein Match)")

        # 2) A funkt passend dazu -> Match.
        st, roh = http(
            "POST",
            "/rest/v1/rpc/match_proximity_spark",
            {
                "p_tokens": [TOKEN_B],
                "p_tags": TAGS,
                "p_mode": "transit",
                "p_self_tags": [],
                "p_self_note": "Live-Nachweis",
                "p_self_token": TOKEN_A,
            },
            kopf_a,
        )
        match = json.loads(roh) if st == 200 else {}
        if match.get("matched"):
            print("  2) A funkt: MATCH mit %s"
                  % str(match.get("partner", ""))[:8])
        else:
            print("  2) A funkt: kein Match (HTTP %s) %s"
                  % (st, roh[:160].decode("utf-8", "replace")))
            fehler += 1

        # 3) B sieht den Ping in seinem Eingang.
        st, roh = http(
            "POST", "/rest/v1/rpc/list_my_soft_pings", {}, kopf_b
        )
        pings = json.loads(roh) if st == 200 else []
        if pings:
            print("  3) B sieht %d Ping(s) im Eingang -> der Funke ist"
                  " sichtbar" % len(pings))
        else:
            print("  3) B sieht KEINEN Ping - der Funke ist unsichtbar")
            fehler += 1

        # 4) B nimmt den Ping an.
        if pings:
            st, roh = http(
                "POST",
                "/rest/v1/rpc/accept_soft_ping",
                {"p_id": pings[0]["id"]},
                kopf_b,
            )
            if st == 200:
                print("  4) B nimmt an: HTTP 200 -> %s"
                      % roh[:110].decode("utf-8", "replace"))
            else:
                print("  4) B nimmt an: HTTP %s %s"
                      % (st, roh[:200].decode("utf-8", "replace")))
                fehler += 1
    finally:
        aufraeumen()

    # Die Kontrolle: es darf nichts mehr da sein.
    rest = sql(
        """
SELECT (SELECT count(*) FROM public.transit_signals
         WHERE self_token IN ('{a}', '{b}')) AS signale,
       (SELECT count(*) FROM public.transit_soft_pings
         WHERE encounter_token IN ('{a}', '{b}')) AS pings,
       (SELECT count(*) FROM public.likes
         WHERE created_at > now() - interval '30 minutes'
           AND ((user_id = '{ua}' AND liked_user_id = '{ub}')
             OR (user_id = '{ub}' AND liked_user_id = '{ua}'))) AS likes,
       (SELECT count(*) FROM public.matches
         WHERE created_at > now() - interval '30 minutes'
           AND ((user_one_id = '{ua}' AND user_two_id = '{ub}')
             OR (user_one_id = '{ub}' AND user_two_id = '{ua}'))) AS matches;
""".format(a=TOKEN_A, b=TOKEN_B, ua=NUTZER_A, ub=NUTZER_B)
    )
    print()
    if rest:
        z = rest[0]
        sauber = (
            int(z["signale"]) == 0
            and int(z["pings"]) == 0
            and int(z["likes"]) == 0
            and int(z["matches"]) == 0
        )
        print("  Aufgeraeumt: Signale %s, Pings %s, Likes %s, Matches %s"
              % (z["signale"], z["pings"], z["likes"], z["matches"]))
        if not sauber:
            fehler += 1
    else:
        print("  ! Die Kontrolle nach dem Aufraeumen war nicht lesbar.")
        fehler += 1

    print()
    if fehler:
        print("  X %d Punkt(e) sind nicht in Ordnung." % fehler)
        return 1
    print("  OK: der Funke entsteht UND ist auf der Gegenseite sichtbar.")
    print("      Die Datenbank ist wieder im Ausgangszustand.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
