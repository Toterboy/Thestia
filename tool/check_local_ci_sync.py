"""Prueft, dass tool/check_local_ci.ps1 dieselben Gates abbildet wie die CI.

Warum es das geben muss (04.11.2026)
-----------------------------------
`tool/check_local_ci.ps1` ist der Spiegel der CI. Ein Spiegel, der
nicht mehr spiegelt, ist schlimmer als gar keiner: Er meldet "alle
Gates gruen", while er ein Gate gar nicht ausfuehrt.

Genau das ist beim Bauen des Skripts passiert: Der Aufruf
"Nur static-checks" lieferte eine leere Ergebnisliste - das Skript
hatte nichts geprueft und trotzdem "ALLE GATES GRUEN" gemeldet. Der
Fehler wurde nur sichtbar, weil die Ergebnisliste leer war.

Diese Pruefung vergleicht daher zwei Listen:

  1) Alle Skripte, die .github/workflows/ci.yml aufruft
  2) Alle Skripte, die tool/check_local_ci.ps1 aufruft

Und meldet:

  FEHLER  Ein Skript der CI fehlt im lokalen Spiegel. Dann kann die
          CI rot werden, ohne dass die lokale Pruefung es merkt.

  FEHLER  Ein Skript des Spiegels laeuft in der CI nicht. Dann prueft
          man lokal etwas, das die CI nicht prueft - mit dem
          Risiko, dass man auf ein Wegbrechen des Gates hereingeht.

Ausgenommen sind Schritte mit "continue-on-error: true": Die sind in
der CI ausdruecklich nur informativ (Netlify-Vergleich, Artefakt-
check ohne Artefakte im Checkout). Sie zu einem lokalen Gate zu
machen waere falsch - sie brauchen Netz oder Dateien, die es lokal
nicht gibt.

Der Check laeuft in der CI selbst (als Teil von static-checks), damit
eine Aenderung an ci.yml ohne angepassten Spiegel sofort auffaellt.
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
CI_YML = ROOT / ".github" / "workflows" / "ci.yml"
SPIEGEL = ROOT / "tool" / "check_local_ci.ps1"

# Ein Aufruf sieht so aus: "python3 tool/check_x.py --lock" oder
# "python tool/check_y.py". Beide Python-Namen sind in der CI im
# Gebrauch (die Jobs benutzen einmal python3, einmal python).
#
# Gruppe 1 ist der reine Skriptname ("check_x.py"), Gruppe 2 die
# Schalter. Beide Seiten (CI und Spiegel) benutzen dieselbe Form -
# sonst vergleicht man Aepfel mit Birnen und meldet grundlos einen
# Unterschied.
AUFruf = re.compile(r"python3?\s+tool[/\\](check_[a-z0-9_]+\.py)((?:\s+--?[\w-]+)*)")

# continue-on-error: true - nur informativ, kein Gate.
WEICH = re.compile(r"continue-on-error:\s*true")


def _skripte_aus_ci() -> tuple[set[str], set[str]]:
    """Liefert (harte Gates, informative Aufrufe) aus ci.yml."""
    hart: set[str] = set()
    weich: set[str] = set()

    zeilen = CI_YML.read_text(encoding="utf-8").splitlines()
    # Ein Schritt beginnt mit "- name:" oder "- run:". Ab da gilt der
    # Zustand "weich" bis zum naechsten Schritt.
    weicher_schritt = False
    for zeile in zeilen:
        stripped = zeile.strip()
        if stripped.startswith("- name:") or stripped.startswith("- run:"):
            weicher_schritt = False
        if WEICH.search(stripped):
            weicher_schritt = True
            continue
        treffer = AUFruf.search(stripped)
        if not treffer:
            continue
        name = treffer.group(1).replace("\\", "/")
        (weich if weicher_schritt else hart).add(name)

    return hart, weich


def _skripte_aus_spiegel() -> set[str]:
    text = SPIEGEL.read_text(encoding="utf-8")
    gefunden: set[str] = set()
    for m in re.finditer(r"tool[/\\](check_[a-z0-9_]+\.py)", text):
        gefunden.add(m.group(1).replace("\\", "/"))
    return gefunden

def vergleiche(hart: set[str], weich: set[str],
               spiegel: set[str]) -> tuple[list[str], list[str]]:
    """Vergleicht die Gates der CI mit dem Spiegel.

    Getrennt von main(), damit der Selbsttest die Logik ohne Dateien
    pruefen kann - ein Selbsttest, der echte Dateien im Repository
    veraendern muesste, waere selbst ein Risiko.
    """
    fehlt = sorted(hart - spiegel)
    extra = sorted(spiegel - hart - weich)
    return fehlt, extra


def main() -> int:
    if not CI_YML.exists():
        print(f"FEHLER: {CI_YML} fehlt.")
        return 1
    if not SPIEGEL.exists():
        print(f"FEHLER: {SPIEGEL} fehlt - ohne den Spiegel ist die "
              f"lokale Pruefung nicht mehr aussagekraeftig.")
        return 1

    hart, weich = _skripte_aus_ci()
    spiegel = _skripte_aus_spiegel()
    fehlt, extra = vergleiche(hart, weich, spiegel)

    print("=" * 72)
    print("SPIEGEL DER CI: tool/check_local_ci.ps1")
    print("=" * 72)
    print(f"  harte Gates in der CI : {len(hart)}")
    print(f"  im Spiegel            : {len(spiegel)}")
    print(f"  nur informativ (CI)   : {len(weich)}")
    print()

    if weich:
        print("  Informativ in der CI (kein Gate, deshalb kein Spiegel):")
        for s in sorted(weich):
            print(f"    - {s}")
        print()

    ok = True

    if fehlt:
        ok = False
        print("  FEHLER - diese Gates der CI fehlen im lokalen Spiegel:")
        for s in fehlt:
            print(f"    - {s}")
        print("  -> Der Spiegel muss ergaenzt werden. Sonst kann die CI")
        print("     rot werden, ohne dass die lokale Pruefung es merkt.")
    else:
        print("  OK: jedes harte Gate der CI ist im Spiegel.")

    if extra:
        ok = False
        print()
        print("  FEHLER - der Spiegel prueft Skripte, die die CI nicht prueft:")
        for s in extra:
            print(f"    - {s}")
        print("  -> Entweder in die CI aufnehmen oder aus dem Spiegel")
        print("     entfernen. Ein Gate, das es nur lokal gibt, bricht")
        print("     beim naechsten Aenderung der CI weg - ohne Hinweis.")
    else:
        print("  OK: der Spiegel prueft nichts, was die CI nicht prueft.")

    print()
    if ok:
        print("OK: der lokale Spiegel bildet die CI vollstaendig ab.")
        return 0
    print("PROBLEME VORHANDEN")
    return 1


if __name__ == "__main__":
    sys.exit(main())
