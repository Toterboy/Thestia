#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""Prueft, in welcher Supabase-Region das Projekt liegt.

WARUM (Sicherheits-Audit 16.11.2026, P1): Die Datenschutzerklaerung
behauptet, die Verarbeitung erfolge "in der EU-Region von Supabase" und
nennt "Supabase Europe B.V." als Auftragsverarbeiter. Das ist aus dem
Repository heraus NICHT belegbar - die Projekt-URL sieht auf jedem
Projekt gleich aus. Stimmt die Aussage nicht, passt der
Auftragsverarbeitungsvertrag nicht zum tatsaechlichen Verarbeiter.

DER WEG: Mit einem Personal Access Token (PAT) von
https://supabase.com/dashboard/account/tokens laesst sich die Region
abfragen. Der Token wird NIE gespeichert, nur fuer diesen Aufruf
verwendet.

    $env:SUPABASE_ACCESS_TOKEN = 'sbp_...'
    python tool\check_supabase_region.py

OHNE Token gibt das Werkzeug die manuellen Schritte aus (Dashboard ->
Projekt -> Settings -> General) und beendet sich ohne Fehler - es ist
ein Handwerkzeug, kein CI-Gate.

EXIT-CODES: 0 = alles in Ordnung (oder kein Token: nur Hinweis),
1 = Region passt NICHT zur Aussage der Datenschutzerklaerung.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Die Region, die die Datenschutzerklaerlung behauptet.
ERWARTETE_REGION = "eu-central-1"

# Regionen, die als EU gelten (fuer die Warnung, nicht fuer den Fehler).
EU_REGIONEN = {
    "eu-central-1",
    "eu-central-2",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-north-1",
    "eu-south-1",
    "eu-south-2",
}


def lies_env() -> dict:
    """Liest die .env (ohne sie zu veraendern)."""
    werte: dict = {}
    datei = ROOT / ".env"
    if not datei.exists():
        return werte
    for zeile in datei.read_text(encoding="utf-8", errors="replace").splitlines():
        treffer = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$", zeile)
        if not treffer:
            continue
        wert = treffer.group(2).strip().strip('"').strip("'")
        werte[treffer.group(1)] = wert
    return werte


def projekt_ref() -> str:
    """Die Projekt-Referenz aus SUPABASE_URL (oder der Umgebung)."""
    url = os.environ.get("SUPABASE_URL") or lies_env().get("SUPABASE_URL", "")
    treffer = re.match(r"https?://([a-z0-9]+)\.supabase\.", url)
    if treffer:
        return treffer.group(1)
    return ""


def frage_region(ref: str, token: str) -> str:
    """Fragt die Management-API nach der Region des Projekts."""
    url = f"https://api.supabase.com/v1/projects/{ref}"
    anfrage = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "thesia-check-region",
        },
    )
    with urllib.request.urlopen(anfrage, timeout=30) as antwort:
        daten = json.loads(antwort.read().decode("utf-8", errors="replace"))
    return str(daten.get("region", ""))


def main() -> int:
    ref = projekt_ref()
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()

    print("== Supabase-Region ==")
    if not ref:
        print(
            "FEHLER: Keine Projekt-Referenz gefunden. SUPABASE_URL in der .env "
            "pruefen."
        )
        return 1
    print(f"Projekt: {ref}")

    if not token:
        print()
        print("Kein SUPABASE_ACCESS_TOKEN gesetzt - die Region kann nicht")
        print("automatisch geprueft werden. Manuell so vorgehen:")
        print()
        print("  1. https://supabase.com/dashboard/project/<ref>/settings/general")
        print("  2. Dort steht die Region (z. B. 'eu-central-1').")
        print("  3. Sie muss mit der Angabe in der Datenschutzerklaerung")
        print(f"     uebereinstimmen (erwartet: {ERWARTETE_REGION}).")
        print()
        print("Oder mit einem Token (nur fuer diesen Aufruf, nicht speichern):")
        print("  $env:SUPABASE_ACCESS_TOKEN = 'sbp_...'")
        print("  python tool\\check_supabase_region.py")
        return 0

    try:
        region = frage_region(ref, token)
    except urllib.error.HTTPError as fehler:
        print(f"FEHLER: Die API antwortete mit HTTP {fehler.code}.")
        if fehler.code in (401, 403):
            print("Der Token ist vermutlich abgelaufen oder hat zu wenig Rechte.")
        return 1
    except urllib.error.URLError as fehler:
        print(f"FEHLER: Die API ist nicht erreichbar: {fehler.reason}")
        return 1

    print(f"Region: {region}")
    if region != ERWARTETE_REGION:
        print()
        print("ACHTUNG: Die Region passt NICHT zur Datenschutzerklaerung.")
        if region in EU_REGIONEN:
            print(
                f"'{region}' ist zwar eine EU-Region, die Erwaehnung in der "
                "Erklaerung muss aber zum Ort passen (nicht nur zur EU)."
            )
        else:
            print(
                f"'{region}' liegt ausserhalb der EU. Die Erklaerung "
                "(Abschnitt 2 und 6) und der Auftragsverarbeitungsvertrag "
                "muessen angepasst werden."
            )
        return 1

    print()
    print("OK: Die Region passt zur Datenschutzerklaerung.")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
