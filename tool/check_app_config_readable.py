"""Prueft: die app_config-Schalter, die die App liest, sind fuer sie erreichbar.

BEFUND (08.11.2026): ZWEI Sicherheitsmechanismen waren STUMM, weil die
App `app_config` direkt ueber PostgREST liest, die Policy aber
`USING (false)` hatte:

* `min_app_version_build` - der Update-Hinweis fuer zu alte Clients
  erschien nie. Damit liefen alte Builds weiter, deren
  Zertifikatspruefung die gesperrten Zwischenzertifikate noch
  akzeptiert (Advisory GHSA-frr6-h895-5pxp, High).
* `transit_spark_enabled` - die NOTBREMSE fuer Transit Spark. Der
  Schalter, mit dem der Betreiber das Feature abschalten kann, wenn der
  BLE-Geraetetest nicht besteht.

Der Fehler war nicht sichtbar: die App behandelt beide Werte als
"fail-open" (kein Update-Hinweis, Feature an). Man konnte also weder
am Bildschirm noch im Log erkennen, dass die Schalter nicht ankommen.

DAS GATE holt eine echte Sitzung fuer ein Testkonto und fragt genau so
ab, wie es die App tut. Es schlaegt an, wenn:
* ein Wert fehlt, den die App braucht (die Schlaege kommen nicht an),
* oder ein Wert lesbar ist, der NICHT fuer den Client gedacht ist
  (die interne Konfiguration waere ausgeliefert).

Aufruf:
    python tool/check_app_config_readable.py
"""
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
KONTO = "46f3f558-b134-4d25-946b-4e052a8ab3b5"

# Was die App braucht (lib/services/app_config_service.dart).
BRAUCHT = ["min_app_version_build", "transit_spark_enabled"]

# Was NICHT fuer den Client gedacht ist: interne Flags.
INTERN = ["enforce_aal2", "enforce_email_confirmed",
          "location_retention_days", "quiz_cooldown_seconds"]


def env_lesen():
    werte = {}
    datei = ROOT / ".env"
    if not datei.exists():
        return werte
    for zeile in datei.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in zeile and not zeile.strip().startswith("#"):
            k, w = zeile.split("=", 1)
            werte[k.strip()] = w.strip()
    return werte


def hole(url, daten=None, kopf=None):
    anfrage = urllib.request.Request(
        url,
        data=json.dumps(daten).encode() if daten is not None else None,
        headers=kopf or {},
        method="POST" if daten is not None else "GET",
    )
    try:
        with urllib.request.urlopen(anfrage, timeout=45) as antwort:
            return antwort.status, antwort.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def main() -> int:
    print("=" * 74)
    print("PRUEFUNG: die app_config-Schalter kommen bei der App an")
    print("=" * 74)
    print()
    env = env_lesen()
    url = env.get("SUPABASE_URL", "")
    public = env.get("SUPABASE_PUBLISHABLE_KEY", "")
    secret = (env.get("SUPABASE_SECRET_KEY_NEW") or env.get("SUPABASE_SECRET_KEY")
              or env.get("SUPABASE_SERVICE_ROLE_KEY") or "")
    if not url or not public or not secret:
        print("  SKIP: keine .env (SUPABASE_URL / Keys fehlen).")
        return 0

    admin = {"apikey": secret, "Authorization": "Bearer %s" % secret,
             "Content-Type": "application/json"}

    # 1) Eine Sitzung fuer das Testkonto (wie im Live-Test).
    status, body = hole("%s/auth/v1/admin/users?per_page=50" % url, kopf=admin)
    if status != 200:
        print("  FEHLER: Die Nutzerliste liess sich nicht lesen (HTTP %s)." % status)
        return 1
    roh = json.loads(body)
    nutzer = roh if isinstance(roh, list) else roh.get("users", [])
    email = next((n.get("email") for n in nutzer if n.get("id") == KONTO), None)
    if not email:
        print("  SKIP: Das Testkonto existiert nicht mehr.")
        return 0
    status, body = hole("%s/auth/v1/admin/generate_link" % url,
                         {"type": "magiclink", "email": email}, admin)
    hash_ = json.loads(body).get("hashed_token")
    status, body = hole("%s/auth/v1/verify" % url,
                         {"type": "magiclink", "token_hash": hash_},
                         {"apikey": public, "Content-Type": "application/json"})
    token = json.loads(body).get("access_token")
    if not token:
        print("  FEHLER: Keine Sitzung bekommen.")
        return 1

    # 2) Die Abfrage, die die App beim Start macht.
    status, body = hole(
        "%s/rest/v1/app_config?select=key,value" % url,
        kopf={"apikey": public, "Authorization": "Bearer %s" % token})
    print("  Die Abfrage der App: HTTP %s" % status)
    if status != 200:
        print("  X  Die Abfrage schlug fehl: %s" % body[:200])
        return 1
    try:
        zeilen = json.loads(body)
    except json.JSONDecodeError:
        print("  X  Die Antwort war kein JSON: %s" % body[:200])
        return 1
    gelesen = {z.get("key"): z.get("value") for z in zeilen}
    print("  Die App liest: %s" % (", ".join("%s=%s" % (k, v)
                                            for k, v in sorted(gelesen.items()))
                                    or "(nichts)"))
    print()

    fehler = 0
    for key in BRAUCHT:
        if key in gelesen:
            print("  OK  %s kommt an (%s)" % (key, gelesen[key]))
        else:
            print("  X  %s kommt NICHT an - der Mechanismus waere stumm."
                  % key)
            fehler += 1
    for key in INTERN:
        if key in gelesen:
            print("  X  %s ist fuer den Client lesbar - die interne"
                  " Konfiguration wird ausgeliefert." % key)
            fehler += 1
        else:
            print("  OK  %s bleibt gesperrt" % key)

    print()
    if fehler:
        print("FEHLER: %d Punkt(e)." % fehler)
        return 1
    print("OK: die Schalter der App kommen an, die interne Konfiguration nicht.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
