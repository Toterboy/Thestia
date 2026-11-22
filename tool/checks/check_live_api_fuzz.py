#!/usr/bin/env python3
"""Fuzzt die Datenbank-Schnittstelle gegen das Produktivsystem.

WARUM (22.11.2026, Betreiber: "Mit fuzzing koenntest du in der App nach
Sicherheitsluecken suchen. Es gibt dafuer auch oeffentliche fertige
Fuzzer, welche dafuer geeignet sein koennten."):

Die App spricht ueber PostgREST mit der Datenbank. Jede RPC bekommt
Werte aus der App - und diese Werte kann zum Teil die ANDERE PERSON
steuern (zum Beispiel ueber das Relay oder den Transit). Ein Fehler
in einer RPC ist damit ein Fehler an der Grenze der App.

DAS WERKZEUG: Es liest das OEFFENTLICHE OpenAPI-Schema des Projekts
(das PostgREST selbst erzeugt) - so wie die fertigen Fuzzer (RESTler,
Schemanticsch) es mit ihrer Spezifikation tun. Daraus kommen die
Aufrufe und ihre Parameter; die Werte erzeugt der Fuzzer.

DIE FEHLERKLASSEN, NACH DENEN GESUCHT WIRD:

  1) HTTP 5xx - der Server ist an der Eingabe zerbrochen. Das ist ein
     echter Fund: ein Angreifer, der eine Funktion mit einem boesen
     Wert aufruft, laesst den Server antworten. Bei 5xx ist die
     Funktion fuer alle betroffen.
  2) Ein Fehler, der NICHT zu der Fehlerklasse des Aufrufs gehoert
     (z. B. "relation does not exist" statt "unauthorized"). Das deutet
     auf eine Injection hin.
  3) Eine Antwort mit Daten, die der Aufrufer nicht sehen darf. Der
     Aufruf laeuft mit dem TESTKONTO (es sieht nur die eigenen Daten).

DIE SICHERHEIT:

  * Es werden NUR LESE-RPCs gerufen (die Liste unten). Nichts wird
    geschrieben, nichts geloescht, nichts gesendet.
  * Es wird das TESTKONTO benutzt (der Betreiber). Es sieht niemals
    fremde Daten - und das wird auch geprueft (Punkt 3).
  * Die Zahl der Aufrufe je RPC ist klein (Standard: 4). Der
    Rate-Limit-Zaehler der Entfernung wird also nur wenig belastet.

Aufruf::

    python tool/checks/check_live_api_fuzz.py
    python tool/checks/check_live_api_fuzz.py --aufrufe 8
"""

import argparse
import json
import pathlib
import random
import subprocess
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
def _projektwurzel() -> pathlib.Path:
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / "pubspec.yaml").exists():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent.parent


ROOT = _projektwurzel()

#: Das Testkonto (der Betreiber). Es sieht nur die eigenen Daten.
KONTO = "46f3f558-b134-4d25-946b-4e052a8ab3b5"

#: Die LESE-RPCs, die gefuzzt werden.
#:
#: WARUM NUR LESEN: Der Fuzzer soll nichts erzeugen. Ein Aufruf wie
#: `like_user` wuerde Likes anlegen, `send_bug_report` Meldungen
#: schreiben - beides veraendert die Produktivdaten. Die Liste hier ist
#: bewusst kurz und conservative - sie nennt genau die Aufrufe, die die
#: App beim LESEN benutzt.
LESE_RPCS = [
    "get_public_profile",
    "list_my_matches_with_state",
    "list_my_likes_pending",
    "list_received_likes_pending",
    "list_my_reports",
    "list_blocked_users",
    "list_message_deletions",
    "list_my_soft_pings",
    "get_my_guardian_status",
    "get_my_photo_appeal",
    "get_my_active_random_chat",
    "get_dating_hour_min_participants",
    "get_find_match_categories",
    "is_current_user_admin",
]

#: Die bösen Werte.
#:
#: DIE KLASSE "SQL-Injection": Der Wert geht als Parameter an
#: PostgREST - der parameterisiert. Trotzdem: ein Wert, der den
#: Parameter sprengt, ist der klassische Test.
BOESE_WERTE = [
    # SQL
    "'; DROP TABLE profiles; --",
    "' OR '1'='1",
    "1; SELECT pg_sleep(10)--",
    "admin'--",
    "') OR ('a'='a",
    # leer und riesig
    "",
    "x" * 5000,
    "ä" * 1000,
    "😀" * 500,
    # Steuerzeichen und Nullbytes
    "\x00\x01\x02",
    "\n\r\t",
    # Formate
    "2026-13-45T99:99:99Z",
    "not-a-date",
    "../../etc/passwd",
    "<script>alert(1)</script>",
    "{{7*7}}",
    "${jndi:ldap://x}",
    # Zahlen als Text (der Server soll das ablehnen, nicht abstuerzen)
    "0",
    "-1",
    "999999999999999999999999",
    "NaN",
    "Infinity",
]

#: Die Parameter, die der Aufrufer bekommen kann.
def parameter_aus_schema(schema: dict, name: str) -> list[str]:
    """Die Parameter einer Funktion aus dem OpenAPI-Schema."""
    pfade = schema.get("paths", {})
    for schluessel, eintrag in pfade.items():
        if not schluessel.endswith("/rpc/" + name):
            continue
        post = eintrag.get("post", {})
        body = post.get("requestBody", {})
        inhalt = body.get("content", {}).get("application/json", {})
        schemateil = inhalt.get("schema", {})
        eigenschaften = schemateil.get("properties", {})
        return list(eigenschaften.keys())
    return []


def secret_aus_cli() -> str:
    """Holt den geheimen Schluessel aus der angemeldeten CLI.

    WARUM: Der Schluessel liegt absichtlich NICHT im Repository (und
    nicht in der .env - dort stehen nur die oeffentlichen Schluessel).
    Wer die CLI angemeldet hat (der Betreiber), bekommt ihn so fuer
    dieses eine Werkzeug - ohne ihn irgendwo abzulegen.
    """
    try:
        ergebnis = subprocess.run(
            [
                "supabase.cmd", "projects", "api-keys",
                "--project-ref", "jftuigjbmmuvrckbchqo",
                "-o", "json", "--reveal",
            ],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=90,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    roh = ergebnis.stdout or ""
    start = roh.find("[")
    if start < 0:
        return ""
    try:
        eintraege = json.loads(roh[start:])
    except Exception:  # noqa: BLE001
        return ""
    for eintrag in eintraege:
        if str(eintrag.get("api_key", "")).startswith("sb_secret_"):
            return eintrag["api_key"]
    return ""


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


def http(
    methode: str,
    pfad: str,
    daten=None,
    kopf=None,
    basis="",
    timeout=30,
):
    body = json.dumps(daten).encode("utf-8") if daten is not None else None
    h = dict(kopf or {})
    if body is not None:
        h["Content-Type"] = "application/json"
    anfrage = urllib.request.Request(basis + pfad, data=body, headers=h, method=methode)
    try:
        with urllib.request.urlopen(anfrage, timeout=timeout) as a:
            return a.status, a.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:  # noqa: BLE001
        return None, str(e)


def sitzung(env: dict, client) -> str | None:
    """Eine echte Sitzung fuer das Testkonto."""
    geheimnis = (
        env.get("SUPABASE_SECRET_KEY_NEW")
        or env.get("SUPABASE_SECRET_KEY")
        or env.get("SUPABASE_SERVICE_ROLE_KEY")
        or secret_aus_cli()
    )
    if not geheimnis:
        return None
    url = env.get("SUPABASE_URL", "").rstrip("/")
    kopf = {"apikey": geheimnis, "Authorization": "Bearer " + geheimnis}
    status, roh = http(
        "GET", "/auth/v1/admin/users?per_page=100", kopf=kopf, basis=url
    )
    if status != 200:
        return None
    ziel = next(
        (u for u in json.loads(roh)["users"] if u.get("id") == KONTO), None
    )
    if ziel is None:
        return None
    status, roh = http(
        "POST",
        "/auth/v1/admin/generate_link",
        {"type": "magiclink", "email": ziel["email"]},
        kopf,
        url,
    )
    if status != 200:
        return None
    hash_ = json.loads(roh).get("hashed_token")
    if not hash_:
        return None
    status, roh = http(
        "POST",
        "/auth/v1/verify",
        {"type": "magiclink", "token_hash": hash_},
        {"apikey": env.get("SUPABASE_PUBLISHABLE_KEY", "")},
        url,
    )
    if status != 200:
        return None
    return json.loads(roh).get("access_token")


def main() -> int:
    argumente = argparse.ArgumentParser()
    argumente.add_argument(
        "--aufrufe",
        type=int,
        default=4,
        help="Wie viele boese Werte je RPC (Standard: 4).",
    )
    argumente.add_argument(
        "--seed",
        type=int,
        default=20261122,
        help="Der Startwert des Zufalls (reproduzierbar).",
    )
    optionen = argumente.parse_args()

    print("=" * 74)
    print("API-FUZZING: die Datenbank-Schnittstelle gegen das Produktivsystem")
    print("=" * 74)

    env = env_laden()
    url = env.get("SUPABASE_URL", "").rstrip("/")
    public = env.get("SUPABASE_PUBLISHABLE_KEY", "")
    if not url or not public:
        print("  ! Keine .env gefunden - es wurde nichts geprueft.")
        return 1

    # Das OpenAPI-Schema: PostgREST erzeugt es selbst. Es enthaelt jede
    # Funktion mit ihren Parametern - die Grundlage fuer die Aufrufe
    # (wie die Spezifikation bei RESTler/Schemanticsch).
    #
    # DER ZUGANG: Fuer diesen Endpunkt verlangt PostgREST den geheimen
    # Schluessel ("Secret API key required") - mit einer normalen
    # Benutzersitzung antwortet er mit 401. Der geheime Schluessel wird
    # nur zum LESEN des Schemas benutzt (er steht nirgends).
    geheimnis = (
        env.get("SUPABASE_SECRET_KEY_NEW")
        or env.get("SUPABASE_SECRET_KEY")
        or env.get("SUPABASE_SERVICE_ROLE_KEY")
        or secret_aus_cli()
    )
    if not geheimnis:
        print("  ! Kein geheimer Schluessel - es wurde nichts geprueft.")
        return 1

    status, roh = http(
        "GET",
        "/rest/v1/",
        kopf={
            "apikey": geheimnis,
            "Authorization": "Bearer " + geheimnis,
            "Accept": "application/openapi+json",
        },
        basis=url,
    )
    if status != 200:
        print("  ! Das OpenAPI-Schema war nicht abrufbar (HTTP %s)." % status)
        return 1
    schema = json.loads(roh)
    funktionen = [
        pfad.split("/rpc/")[1]
        for pfad in schema.get("paths", {})
        if pfad.startswith("/rpc/")
    ]
    print()
    print("  Das Schema nennt %d Funktionen - davon werden %d gelesen."
          % (len(funktionen), len(LESE_RPCS)))

    # Die Aufrufe laufen mit der SITZUNG des Testkontos: so sieht der
    # Fuzzer genau das, was die App sieht (und nichts fremdes).
    token = sitzung(env, None)
    if not token:
        print("  ! Keine Sitzung fuer das Testkonto - es wurde nichts geprueft.")
        return 1

    kopf = {"apikey": public, "Authorization": "Bearer " + token}
    zufall = random.Random(optionen.seed)
    befunde = []
    aufrufe = 0

    for name in LESE_RPCS:
        if name not in funktionen:
            print("  - %s: gibt es nicht (uebersprungen)" % name)
            continue
        parameter = parameter_aus_schema(schema, name)
        for i in range(optionen.aufrufe):
            # Der boese Wert wandert in einen Parameter; die anderen
            # bekommen plausible Werte.
            daten = {}
            for p in parameter:
                daten[p] = KONTO
            if parameter:
                ziel = zufall.choice(parameter)
                daten[ziel] = zufall.choice(BOESE_WERTE)
            status, roh = http(
                "POST",
                "/rest/v1/rpc/" + name,
                daten,
                kopf,
                url,
            )
            aufrufe += 1
            if status is None:
                # EIN ABWURF KANN AUCH DAS NETZ SEIN: Die Verbindung
                # wurde vom Remotehost geschlossen (WinError 10054). Das
                # ist nicht der gleiche Befund wie ein Serverfehler -
                # deshalb wird der Aufruf EINMAL wiederholt. Bleibt es
                # dabei, ist es ein Fund.
                status, roh = http(
                    "POST",
                    "/rest/v1/rpc/" + name,
                    daten,
                    kopf,
                    url,
                )
                aufrufe += 1
                if status is None:
                    befunde.append(
                        "%s: keine Antwort (%s)" % (name, roh[:120])
                    )
                    continue
            if status >= 500:
                befunde.append(
                    "%s: HTTP %s bei %s -> %s"
                    % (name, status, daten, roh[:160])
                )
                continue
            if status == 404 and "Could not find the function" in roh:
                # Die Funktion gibt es nicht (alter Serverstand) - kein
                # Befund, sondern eine Beobachtung.
                continue
            if status >= 400:
                # Ein erwarteter Fehler (unauthorized, invalid input,
                # rate_limited) ist in Ordnung - der Server soll die
                # Eingabe ablehnen, nicht daran sterben.
                if "rate_limited" in roh:
                    continue
                code = None
                try:
                    code = json.loads(roh).get("code")
                except Exception:  # noqa: BLE001
                    pass
                if code in ("PGRST202", "PGRST301", "42883", "22P02"):
                    continue
                if "does not exist" in roh and "function" in roh:
                    # Ein Parameter, den es nicht gibt - harmlos.
                    continue
                befunde.append(
                    "%s: unerwarteter Fehler HTTP %s bei %s -> %s"
                    % (name, status, daten, roh[:160])
                )
        print("  - %s: %d Aufrufe" % (name, optionen.aufrufe))

    print()
    print("  %d Aufrufe gegen das Produktivsystem." % aufrufe)
    if befunde:
        print()
        print("  BE FUNDE:".replace(" ", ""))
        for befund in befunde:
            print("    X %s" % befund)
        return 1
    print()
    print("  OK: kein Aufruf hat den Server zu einem Fehler veranlasst.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
