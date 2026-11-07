#!/usr/bin/env python3
"""Prueft, ob jede Funktion, die die App aufruft, auch aufrufbar ist.

BEFUND (07.11.2026, Betreiber): "Blockierte-Liste mit Entblockieren" -
die Liste war da, aber das Entblockieren hat NIE funktioniert.

DIE URSACHE (live gemessen): Der Aufruf antwortete mit
  HTTP 403  permission denied for function unblock_user
Die Funktion public.unblock_user ist SECURITY DEFINER und existiert -
aber die Rolle "authenticated" hat KEIN Ausfuehrungsrecht darauf.
Bei der Rechte-Revoke-Migration (123) wurde sie vergessen: Ihre
Schwester block_user hat das Recht, unblock_user nicht.

WARUM DARAUS EIN WERKZEUG STATT EINES EINZELFIXES: Der Fehler ist
still. Die App zeigt "Entblockieren fehlgeschlagen", der Nutzer glaubt,
es liege an ihm. Und es kann an jeder der ~180 Funktionen passieren -
ein fehlendes GRANT sieht man im Quelltext nicht.

Diese Pruefung macht das sichtbar:
  1. Sie sammelt ALLE RPC-Namen, die der Client (Dart) und die
     Edge Functions (TypeScript) aufrufen.
  2. Sie fragt die PRODUKTIVDATENBANK, welche Rechte die Rolle
     "authenticated" tatsaechlich hat.
  3. Jede aufgerufene Funktion ohne Ausfuehrungsrecht wird gemeldet.

Aufruf::

    python tool/check_function_grants.py
"""

import json
import pathlib
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent

SQL = """
SELECT p.proname,
       p.oid::regprocedure::text AS sig,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS darf_auth,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS darf_anon,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS darf_service,
       p.prosecdef AS security_definer
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
 ORDER BY p.proname, sig;
"""

# Die Ausnahmen: Funktionen, die bewusst fuer "anon" offen sind.
#
# * check_email_ban_status - wird VOR der Anmeldung geprueft
#   (Registrierung: ist diese E-Mail gesperrt?).
# * distance_bucket_km, snap_location_to_grid - reine Rechnungen, sie
#   lesen und schreiben nichts.
#
# Alles andere, was der Client aufruft, gehoert einem angemeldeten
# Nutzer: sonst koennte jemand ohne Konto Likes setzen, Funken
# erzeugen oder Nachrichten zustellen.
ANON_ERLAUBT = {
    "check_email_ban_status": "wird vor der Anmeldung geprueft",
    "distance_bucket_km": "reine Rechnung, liest nichts",
    "snap_location_to_grid": "reine Rechnung, liest nichts",
}


def sammle_rpc_namen() -> dict:
    """Alle RPC-Namen, die der Client aufruft - nach Aufrufort."""
    namen = {"client": set(), "edge": set()}

    # Dart: rpc('name' ...) und .rpc('name')
    muster_dart = re.compile(r"\.rpc\(\s*'([a-zA-Z0-9_]+)'")
    for datei in list((ROOT / "lib").rglob("*.dart")) + list(
        (ROOT / "test").rglob("*.dart")
    ):
        text = datei.read_text(encoding="utf-8", errors="replace")
        for treffer in muster_dart.finditer(text):
            namen["client"].add(treffer.group(1))

    # TypeScript (Edge Functions): .rpc("name"
    muster_ts = re.compile(r"\.rpc\(\s*[\"']([a-zA-Z0-9_]+)[\"']")
    funktionen = ROOT / "supabase" / "functions"
    if funktionen.exists():
        for datei in funktionen.rglob("*.ts"):
            text = datei.read_text(encoding="utf-8", errors="replace")
            for treffer in muster_ts.finditer(text):
                namen["edge"].add(treffer.group(1))

    return namen


def hole_funktionen():
    sql = ROOT / "supabase" / "_pruef_grants.sql"
    sql.write_text(SQL, encoding="utf-8")
    ergebnis = subprocess.run(
        ["supabase.cmd", "db", "query", "--linked", "--file", str(sql)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    sql.unlink(missing_ok=True)
    kombi = ergebnis.stdout + ergebnis.stderr
    start = kombi.find("\n{")
    if start < 0:
        start = kombi.find("{")
    if start < 0:
        return None, kombi[:400]
    zeile = kombi[start:]
    try:
        obj = json.loads(zeile[:zeile.rfind("}") + 1])
    except Exception as e:  # noqa: BLE001
        return None, "%s | %s" % (e, kombi[:300])
    if obj.get("_tag") == "Error":
        return None, json.dumps(obj)[:400]
    return obj.get("rows", []), None


def main() -> int:
    print("=" * 70)
    print("FUNKTIONS-RECHTE: kann der Server jeden Aufruf bedienen?")
    print("=" * 70)

    aufgerufen = sammle_rpc_namen()
    print()
    print("  Der Client ruft %d RPCs auf, die Edge Functions %d."
          % (len(aufgerufen["client"]), len(aufgerufen["edge"])))

    funktionen, fehler = hole_funktionen()
    if funktionen is None:
        print("  ! Die Funktionen sind nicht lesbar: %s" % (fehler or "")[:300])
        return 1

    # Nach Namen gruppieren: eine Funktion kann mehrere Ueberladungen
    # haben (z. B. match_proximity_spark mit 5 und 6 Parametern).
    nach_name = {}
    for f in funktionen:
        nach_name.setdefault(f["proname"], []).append(f)

    fehlend = []
    for name in sorted(aufgerufen["client"]):
        eintraege = nach_name.get(name)
        if not eintraege:
            fehlend.append((name, None, "Die Funktion gibt es nicht."))
            continue
        # Der Dart-Client nutzt den oeffentlichen Schluessel. Ohne
        # Anmeldung ist das die Rolle "anon", mit Anmeldung
        # "authenticated". Mindestens EINE der beiden muss die Funktion
        # ausfuehren duerfen - und mindestens EINE Ueberladung.
        if not any(e["darf_auth"] or e["darf_anon"] for e in eintraege):
            fehlend.append((name, eintraege, "kein Ausfuehrungsrecht"))

    # Die Edge Functions laufen mit der Service-Role - fuer sie zaehlt
    # nur das Recht dieser Rolle.
    for name in sorted(aufgerufen["edge"] - aufgerufen["client"]):
        eintraege = nach_name.get(name)
        if not eintraege:
            continue
        if not any(
            e["darf_service"] or e["darf_auth"] or e["darf_anon"]
            for e in eintraege
        ):
            fehlend.append(
                (name, eintraege, "kein Ausfuehrungsrecht (Edge Function)")
            )

    fehler = 0
    # Und die Gegenseite: eine Funktion, die der Client aufruft, darf
    # NICHT fuer "anon" (also ohne Anmeldung) aufrufbar sein.
    #
    # BEFUND (07.11.2026): Zwei Like-Funktionen waren fuer jeden
    # aufrufbar - auch ohne Konto. Das fiel nur auf, weil eine
    # Migration die Funktion per DROP/CREATE ersetzt hat: beim DROP
    # gehen die Rechte verloren.
    zu_offen = []
    for name in sorted(aufgerufen["client"]):
        if name in ANON_ERLAUBT:
            continue
        for e in nach_name.get(name, []):
            if e["darf_anon"]:
                zu_offen.append((name, e))

    print()
    if zu_offen:
        print("  X %d aufgerufene Funktion(en) ist fuer die Rolle 'anon'"
              " aufrufbar - also OHNE Anmeldung:" % len(zu_offen))
        print("    (Jeder koennte sie benutzen - etwa Likes setzen,"
              " Funken erzeugen")
        print("     oder Nachrichten zustellen.)")
        for name, e in zu_offen:
            print()
            print("      %s" % e["sig"])
            print("        -> fuer anon aufrufbar")
        print()
        print("    Loesung: REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon;")
        print("             GRANT EXECUTE ON FUNCTION ... TO authenticated;")
        print()
        print("    ACHTUNG: Nach einem DROP/CREATE sind die Rechte weg -")
        print("    die Migration muss sie ausdruecklich wieder setzen.")
        fehler += len(zu_offen)

    print()
    if fehlend:
        print("  X %d aufgerufene Funktion(en) kann der Server NICHT ausfuehren:"
              % len(fehlend))
        print("    (403 permission denied - die App zeigt nur einen")
        print("     Fehlertext, der Nutzer glaubt, es liege an ihm)")
        for name, eintraege, grund in fehlend:
            print()
            print("      %s  (%s)" % (name, grund))
            if eintraege:
                for e in eintraege:
                    print("        %-44s security_definer=%s"
                          % (e["sig"], e["security_definer"]))
        return 1

    if zu_offen:
        # Die Meldung ist schon gedruckt - der Exit-Code muss aber
        # ebenfalls_signalisieren, dass ein Release gestoppt ist.
        return 1

    print("  OK: jede aufgerufene Funktion ist aufrufbar - und keine ist"
          " fuer 'anon' offen.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
