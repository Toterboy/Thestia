"""Prüft die Syntax der Edge Functions unter supabase/functions/.

WARUM DIESES SKRIPT ES GIBT (04.11.2026):
==========================================

Am 04.11.2026 hat eine Änderung an check-location/index.ts die Datei
zerlegt: Ein Skript hatte den Hilfsblock an der falschen Stelle
ausgeschnitten, sodass die Schleife des Helpers offen blieb und der
Rest der Funktion in ihrem Körper lande.

Zwei Dinge machten das schlimm:

  1) Die Datei wurde committen. Der Deploy hat den Fehler dann zwar
     gefangen ("The module's source code could not be parsed"), aber
     bis dahin war die kaputte Version im Repository.

  2) Die Syntaxprüfung, die bis dahin lief, war
     "node --experimental-strip-types --check" - und die MELDET
     SICH NICHT. Sie meldete auch die zerlegte Datei als gültig.
     Eine Prüfung, die kaputten Code als gut meldet, ist schlimmer
     als keine Prüfung.

DAS SCRIPT PRÜFT DESHALB MIT ESBUILD
======================================

esbuild parst TypeScript, ohne es auszuführen, und meldet echte
Syntaxfehler. Die Prüfung läuft auf allen 23 Funktionen und auf dem
gemeinsamen Modul unter _shared/.

WENN ESBUILD NICHT DA IST:
Der Check meldet es laut und macht auf die Structural-Prüfung
zurück (Klammerbalance je Datei, ohne Strings und Kommentare). Die
Structural-Prüfung fängt grobe Bruche - sie fängt nicht jeden
Fehler. Deshalb steht im Ergebnis, welcher Modus lief: "grün aus der
Structural-Prüfung" ist nicht dasselbe wie "grün aus esbuild".
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

#: Die Wurzel des Projekts - der Ordner mit der pubspec.yaml.
#:
#: DER GRUND: Die Skripte liegen in Unterordnern von tool/. Statt
#: feste Ebenen zu zählen, wird die Wurzel gesucht - so brechen die
#: Pfade nicht, wenn sich die Tiefe ändert.
def _projektwurzel() -> pathlib.Path:
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / 'pubspec.yaml').exists():
            return kandidat
    # DER NOTFALL: Der Ordner mit den Migrationen - den hat auch das
    # kleine Test-Repo der Selbsttests (dort gibt es keine pubspec).
    for kandidat in pathlib.Path(__file__).resolve().parents:
        if (kandidat / 'supabase' / 'migrations').is_dir():
            return kandidat
    return pathlib.Path(__file__).resolve().parent.parent


ROOT = _projektwurzel()

FN = ROOT / "supabase" / "functions"


def esbuild_vorhanden() -> str | None:
    """Findet den Befehl, mit dem esbuild läuft."""
    exe = shutil.which("esbuild")
    if exe:
        return exe
    # über npx (Windows braucht npx.cmd, weil die Ausführungsrichtlinie
    # .ps1-Skripte blockiert)
    for name in ("npx.cmd", "npx"):
        exe = shutil.which(name)
        if exe:
            return exe
    return None


def dateien() -> list[pathlib.Path]:
    return sorted(FN.rglob("*.ts"))


def pruefe_mit_esbuild(befehl: str) -> tuple[list[str], bool]:
    """Gibt die Fehlerliste und True zurück, wenn esbuild lief."""
    fehler: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        for f in dateien():
            args = [befehl]
            if Path(befehl).name.startswith("npx"):
                args += ["--yes", "esbuild@0.25"]
            args += [str(f), "--outfile=" + str(pathlib.Path(tmp) / "out.js"),
                     "--log-level=error"]
            try:
                proc = subprocess.run(args, capture_output=True, text=True,
                                      timeout=180)
            except Exception as e:  # noqa: BLE001
                fehler.append("%s: esbuild konnte nicht laufen: %s"
                              % (f.relative_to(ROOT), e))
                return fehler, True
            if proc.returncode != 0:
                ausgabe = (proc.stderr or proc.stdout or "").strip()
                zeilen = [z for z in ausgabe.split("\n") if z.strip()][:6]
                fehler.append("%s:\n    %s"
                              % (f.relative_to(ROOT), "\n    ".join(zeilen)))
    return fehler, True


def pruefe_strukturell() -> list[str]:
    """Klammerbalance je Datei (ohne Strings und Kommentare)."""
    fehler: list[str] = []
    for f in dateien():
        text = f.read_text(encoding="utf-8")
        # Kommentare und Strings entfernen.
        text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
        text = re.sub(r"//[^\n]*", " ", text)
        text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
        text = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", text)
        text = re.sub(r"`(?:[^`\\]|\\.)*`", "``", text)
        for offen, zu in (("{", "}"), ("(", ")"), ("[", "]")):
            if text.count(offen) != text.count(zu):
                fehler.append(
                    "%s: %s/%s unausbalanciert (%d/%d)"
                    % (f.relative_to(ROOT), offen, zu,
                       text.count(offen), text.count(zu)))
    return fehler


def main() -> int:
    print("EDGE-FUNCTION-SYNTAX")
    print("=" * 72)

    alle = dateien()
    if not alle:
        print("FEHLER: keine .ts-Dateien unter supabase/functions/ gefunden.")
        return 1
    print("  %d Dateien" % len(alle))

    befehl = esbuild_vorhanden()
    fehler: list[str] = []
    modus = ""

    if befehl:
        fehler, lief = pruefe_mit_esbuild(befehl)
        if lief:
            modus = "esbuild"
            print("  Modus: esbuild (echter TypeScript-Parser)")
    else:
        fehler = pruefe_strukturell()
        modus = "strukturell"
        print("  Modus: STRUKTURELL (esbuild nicht gefunden)")
        print("  ACHTUNG: Das ist die schwache Pruefung - sie meldet nur")
        print("  unausbalancierte Klammern, nicht jeden Syntaxfehler.")

    print()
    if fehler:
        print("FEHLER:")
        for f in fehler:
            print("  - %s" % f)
        print()
        print("PROBLEME VORHANDEN")
        return 1

    print("  OK: alle Dateien syntaktisch gueltig (%s)." % modus)
    return 0


if __name__ == "__main__":
    sys.exit(main())
