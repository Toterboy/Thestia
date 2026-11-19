#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""Prueft die Zertifikat-Pins gegen die Live-Zertifikate.

WARUM (Sicherheits-Audit 16.11.2026, P2): Am 16.11.2026 war der in
der App gepinnte Leaf-Pin seit dem 24.10.2026 veraltet - Let's Encrypt
hatte rotiert. Die App lief dadurch ausschliesslich ueber den
(damals dauerhaft offenen) Aussteller-Fallback, ohne dass jemand es
bemerkt haette. Ein zweiter Fund: das Rotations-Werkzeug hatte eine
eigene, FALSCHE SHA-256 (es fehlte das w[i-7] in der
Nachrichtenplanung) - damit passte kein Pin, den es erzeugt hatte.

Diese Pruefung liest die EINE Quelle der Wahrheit
(lib/utils/security/cert_pins.dart) und vergleicht sie mit dem Live-Zertifikat:

  * Leaf-Pin passt nicht               -> FEHLER (Rotation noetig)
  * Leaf laeuft bald ab                -> FEHLER (vor dem Release erneuern)
  * Gueltigkeit in der Tabelle falsch -> FEHLER (Datum pflegen)
  * Host nicht erreichbar              -> WARNUNG (Netz, kein Pin-Problem)

Das Rotations-Werkzeug (tool/scripts/rotate_cert_pins.dart) nutzt dieselbe
Tabelle und hat einen Selbsttest fuer seine eigene SHA-256.

Aufruf:  python tool\check_cert_pins.py
"""

from __future__ import annotations

import base64
import hashlib
import re
import socket
import ssl
import sys
from datetime import datetime, timezone
from pathlib import Path

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zaehlen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe aendert.
def _projektwurzel() -> Path:
    for kandidat in Path(__file__).resolve().parents:
        if (kandidat / 'pubspec.yaml').exists():
            return kandidat
    # DER NOTFALL: Der Ordner mit den Migrationen - den hat auch das
    # kleine Test-Repo der Selbsttests (dort gibt es keine pubspec).
    for kandidat in Path(__file__).resolve().parents:
        if (kandidat / 'supabase' / 'migrations').is_dir():
            return kandidat
    return Path(__file__).resolve().parent.parent


ROOT = _projektwurzel()

QUELLE = ROOT / "lib" / "utils" / "security" / "cert_pins.dart"

# Ab hier gilt der Pin als "zu alt" (Tage bis zum Ablauf).
MIN_TAGE_BIS_ABLAUF = 30


def lies_pins() -> dict:
    """Liest Hosts, Pins und Gueltigkeit aus lib/utils/security/cert_pins.dart."""
    if not QUELLE.exists():
        print(f"FEHLER: {QUELLE} fehlt.")
        sys.exit(1)
    text = QUELLE.read_text(encoding="utf-8", errors="replace")

    bloecke = re.findall(
        r"'(?P<host>[a-z0-9.\-]+\.[a-z]{2,})':\s*PinnedHost\((?P<inhalt>.*?)\n  \),",
        text,
        re.S,
    )
    ergebnis: dict = {}
    for host, inhalt in bloecke:
        pins = re.findall(r"'([A-Za-z0-9+/=]{40,})'", inhalt)
        ablauf = re.search(r"leafNotAfterEpoch:\s*(\d+)", inhalt)
        beginn = re.search(r"leafNotBeforeEpoch:\s*(\d+)", inhalt)
        ergebnis[host] = {
            "pins": pins,
            "ablauf": int(ablauf.group(1)) if ablauf else None,
            "beginn": int(beginn.group(1)) if beginn else None,
        }
    if not ergebnis:
        print("FEHLER: In cert_pins.dart wurde keine Pin-Tabelle gefunden.")
        sys.exit(1)
    return ergebnis


def hole_leaf(host: str):
    """Holt das Leaf-Zertifikat (DER) und dessen Metadaten."""
    kontext = ssl.create_default_context()
    with socket.create_connection((host, 443), timeout=25) as s:
        with kontext.wrap_socket(s, server_hostname=host) as ss:
            kette = ss.get_verified_chain()
            if not kette:
                raise ssl.SSLError("leere Zertifikatskette")
            return kette[0], ss.getpeercert()


def parse_datum(wert: str) -> datetime:
    """'Jan 22 14:22:32 2027 GMT' -> datetime (UTC)."""
    return datetime.strptime(wert, "%b %d %H:%M:%S %Y %Z").replace(
        tzinfo=timezone.utc
    )


def main() -> int:
    print("== Zertifikat-Pins ==")
    pins = lies_pins()
    fehler = 0
    warnung = 0
    jetzt = datetime.now(timezone.utc)

    for host, daten in sorted(pins.items()):
        print(f"Host: {host}")
        try:
            leaf, meta = hole_leaf(host)
        except (OSError, ssl.SSLError, ValueError) as ausnahme:
            print(f"  WARNUNG: Host nicht erreichbar ({ausnahme}).")
            print("           (Netzproblem - die Pins wurden nicht geprueft.)")
            warnung += 1
            continue

        leaf_hash = base64.b64encode(hashlib.sha256(leaf).digest()).decode()

        if leaf_hash in daten["pins"]:
            print(f"  OK: Leaf-Pin stimmt ({leaf_hash}).")
        else:
            fehler += 1
            print("  FEHLER: Leaf-Pin STIMMT NICHT - Rotation noetig!")
            print(f"         aktueller Leaf-Hash: {leaf_hash}")
            print(
                "         eintragen in lib/utils/security/cert_pins.dart "
                "(kPinnedHosts) - alten Pin zunaechst behalten."
            )

        try:
            not_after = parse_datum(meta["notAfter"])
        except (KeyError, ValueError):
            not_after = None

        if not_after is not None and daten["ablauf"]:
            tabelle = datetime.fromtimestamp(daten["ablauf"], tz=timezone.utc)
            if abs((tabelle - not_after).total_seconds()) > 36 * 3600:
                fehler += 1
                print(
                    "  FEHLER: Das Ablaufdatum in der Tabelle passt nicht zum "
                    f"Zertifikat (Tabelle {tabelle.date()}, "
                    f"Zertifikat {not_after.date()})."
                )
            tage = (not_after - jetzt).days
            if tage < MIN_TAGE_BIS_ABLAUF:
                fehler += 1
                print(
                    f"  FEHLER: Der Leaf laeuft in nur {tage} Tagen ab - "
                    "jetzt erneuern, sonst bricht die App beim Rotieren ab."
                )
            else:
                print(f"  OK: Der Leaf laeuft noch {tage} Tage.")

    print()
    if fehler:
        print(f"FEHLER: {fehler} Pin-Problem(e).")
        print("Beheben: python tool\\rotate_cert_pins.dart (Ausgabe eintragen)")
        return 1
    if warnung:
        print(f"OK (mit {warnung} Warnung(en) - Netz, nicht die Pins).")
        return 0
    print("OK: alle Pins stimmen mit den Live-Zertifikaten ueberein.")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
