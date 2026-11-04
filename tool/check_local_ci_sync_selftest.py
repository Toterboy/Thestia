"""Selbsttest fuer tool/check_local_ci_sync.py.

Warum es den gibt
-----------------
Ein Pruefer, der nur gruen melden kann, ist wertlos. Dieser Selbsttest
baut die negativen Faelle nach - also Faelle, in denen der Pruefer
einen Befund MUSS liefern:

  1) Ein Skript der CI fehlt im Spiegel  -> der Spiegel laeuft der CI
     hinterher, die CI kann rot werden, ohne dass man es lokal sieht.
  2) Der Spiegel enthaelt ein Skript, das die CI nicht kennt -> lokal
     wird etwas geprueft, das in der CI nicht gilt.
  3) continue-on-error-Schritte sind keine Gates -> sie duerfen den
     Spiegel nicht verlangen.
  4) Ein vollstaendiger Spiegel meldet nichts.
  5) Beide Schreibweisen des Python-Aufrufs (python3, python).

Der Test arbeitet mit Dateien im TEMP-Ordner und veraendert nichts im
Repository.

HINWEIS ZUR NAMENSFORM: Beide Seiten werden auf den reinen Skriptnamen
gebracht ("check_x.py", ohne "tool/"). Deshalb heissen die Erwartungen
unten "check_a.py" und nicht "tool/check_a.py". Beide Seiten benutzen
dieselbe Form - sonst vergleicht man Aepfel mit Birnen.
"""
import pathlib
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import check_local_ci_sync as sync  # noqa: E402

FEHLER = 0


def pruefe(name: str, bedingung: bool) -> None:
    global FEHLER
    if bedingung:
        print(f"  OK    {name}")
    else:
        print(f"  FEHL  {name}")
        FEHLER += 1


def schreibe(pfad: pathlib.Path, text: str) -> None:
    pfad.write_text(text, encoding="utf-8", newline="\n")


def main() -> int:
    print("=" * 72)
    print("SELBSTTEST: check_local_ci_sync.py")
    print("=" * 72)

    with tempfile.TemporaryDirectory() as tmp:
        basis = pathlib.Path(tmp)

        ci = basis / "ci.yml"
        spiegel = basis / "spiegel.ps1"

        # --- Fall 1: ein Gate fehlt im Spiegel ---------------------
        schreibe(ci, """
jobs:
  static-checks:
    steps:
      - name: Pruefer
        run: |
          python3 tool/check_a.py
          python tool/check_b.py
""")
        schreibe(spiegel, """
          Gate 'a' @($py, 'tool/check_a.py')
""")
        sync.CI_YML = ci
        sync.SPIEGEL = spiegel
        hart, weich = sync._skripte_aus_ci()
        sp = sync._skripte_aus_spiegel()
        fehlt, extra = sync.vergleiche(hart, weich, sp)

        pruefe("die CI hat zwei harte Gates erkannt", len(hart) == 2)
        pruefe("check_a.py liegt in den harten Gates", "check_a.py" in hart)
        pruefe("check_b.py liegt in den harten Gates", "check_b.py" in hart)
        pruefe("der fehlende Spiegel wird als FEHLT gemeldet",
               fehlt == ["check_b.py"])
        pruefe("es wird nichts zusaetzlich gemeldet", extra == [])

        # --- Fall 2: der Spiegel kennt ein Skript, das die CI nicht kennt
        schreibe(spiegel, """
          Gate 'a' @($py, 'tool/check_a.py')
          Gate 'b' @($py, 'tool/check_b.py')
          Gate 'c' @($py, 'tool/check_c.py')
""")
        hart, weich = sync._skripte_aus_ci()
        sp = sync._skripte_aus_spiegel()
        fehlt, extra = sync.vergleiche(hart, weich, sp)
        pruefe("ein zusaetzliches Skript wird als EXTRA gemeldet",
               extra == ["check_c.py"])
        pruefe("und nichts fehlt", fehlt == [])

        # --- Fall 3: continue-on-error ist kein Gate ----------------
        schreibe(ci, """
jobs:
  dependency-audit:
    steps:
      - name: Hart
        run: python tool/check_a.py
      - name: Weich
        continue-on-error: true
        run: python tool/check_informativ.py
""")
        hart, weich = sync._skripte_aus_ci()
        pruefe("continue-on-error wird NICHT als hartes Gate gezaehlt",
               "check_informativ.py" not in hart)
        pruefe("continue-on-error wird als informativ gezaehlt",
               "check_informativ.py" in weich)

        # Der Zustand "weich" gilt nur fuer den einen Schritt.
        schreibe(ci, """
jobs:
  j:
    steps:
      - name: Weich
        continue-on-error: true
        run: python tool/check_informativ.py
      - name: Hart
        run: python tool/check_a.py
""")
        hart, weich = sync._skripte_aus_ci()
        pruefe("nach dem weichen Schritt ist der naechste wieder hart",
               "check_a.py" in hart)

        # --- Fall 4: vollstaendiger Spiegel ------------------------
        schreibe(spiegel, """
          Gate 'a' @($py, 'tool/check_a.py')
          Gate 'informativ' @($py, 'tool/check_informativ.py')
""")
        hart, weich = sync._skripte_aus_ci()
        sp = sync._skripte_aus_spiegel()
        fehlt, extra = sync.vergleiche(hart, weich, sp)
        pruefe("ein vollstaendiger Spiegel meldet nichts", not fehlt and not extra)

        # --- Fall 5: beide Schreibweisen des Python-Aufrufs -------
        schreibe(ci, """
jobs:
  j:
    steps:
      - name: Hart
        run: |
          python3 tool/check_a.py
          python tool/check_b.py --lock
""")
        hart, weich = sync._skripte_aus_ci()
        pruefe("python3 UND python werden erkannt", len(hart) == 2)

        # --- Fall 6: ein Skript ohne tool/-Praefix wird NICHT gezaehlt
        # (es gehoert nicht zu den Pruefern dieses Projekts)
        schreibe(ci, """
jobs:
  j:
    steps:
      - name: Hart
        run: python3 check_x.py
""")
        hart, weich = sync._skripte_aus_ci()
        pruefe("ein Aufruf ohne tool/ wird nicht als Gate gezaehlt",
               len(hart) == 0)

    print()
    if FEHLER == 0:
        print("OK: der Spiegel-Pruefer findet die negativen Faelle.")
        return 0
    print(f"{FEHLER} FEHLER")
    return 1


if __name__ == "__main__":
    sys.exit(main())
