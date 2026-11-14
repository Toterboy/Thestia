"""Erweitert make_terms.py um die Dart-Ausgabe fuer die App.

WARUM (14.11.2026, Betreiber): "Die Nutzungsbedingungen funktionieren in
der App nicht." Die App verlinkte auf die Webseite - ein Browser muss
dann installiert sein, die Seite muss online sein, und in der App steht
selbst nichts. Die Datenschutzerklaerung macht es seit dem 03.11.2026
besser: ihr Volltext steht als Datei im Binary (lib/generated/) und wird
im App-Screen angezeigt. Die Nutzungsbedingungen bekommen denselben Weg:

  * dieselben Bloecke (PrivacyBlock),
  * denselben Bildschirm (LegalTextScreen),
  * dieselbe Sprache je App-Sprache (deutsch/englisch).

Damit kann die App die Bedingungen auch dann zeigen, wenn das Handy
keinen Browser hat oder das Netz weg ist - und Play findet die
Bedingungen in der App selbst (wie bei der Erklaerung).
"""

import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GEN = ROOT / "lib" / "generated"


def dart_quote(s: str) -> str:
    """Dart-String-Literal (wie in make_privacy_policy.py).

    Dart kennt kein rohes Mehrzeilen-Literal - jeder Zeilenumbruch wird
    zu \\n im normalen String.
    """
    out = s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
    return "'" + out + "'"


def render_dart(daten: dict, klasse: str) -> str:
    """Die Bedingungen als Liste von PrivacyBlock."""
    zeilen = [
        "// GENERIERTE DATEI - NICHT VON HAND AENDERN.",
        "// Quelle: tool/make_terms.py",
        "// Neu erzeugen mit: python tool/make_terms.py",
        "",
        "import 'package:thestia/generated/privacy_policy_blocks.dart';",
        "",
        "/// Die Nutzungsbedingungen als Bloecke, in der Reihenfolge der",
        "/// Quelle.",
        "const List<PrivacyBlock> %s = <PrivacyBlock>[" % klasse,
        "  PrivacyBlock('h1', %s)," % dart_quote(daten["titel"]),
        "  PrivacyBlock('p', %s)," % dart_quote(daten["lead"]),
    ]
    for art, inhalt in daten["bloecke"]:
        if art == "h2":
            zeilen.append("  PrivacyBlock('h2', %s)," % dart_quote(inhalt))
        elif art == "p":
            zeilen.append("  PrivacyBlock('p', %s)," % dart_quote(inhalt))
        elif art == "ul":
            # Jeder Listenpunkt wird ein eigener Block (kind 'li') - so
            # rendert der Bildschirm ihn als Aufzaehlung.
            for li in inhalt:
                zeilen.append("  PrivacyBlock('li', %s)," % dart_quote(li))
    zeilen.append("];")
    zeilen.append("")
    return "\n".join(zeilen)


def formatiere(pfad: pathlib.Path) -> None:
    """Formatiert die erzeugte Datei (die CI prueft das Format)."""
    for befehl in ('dart format "%s"' % pfad, 'flutter format "%s"' % pfad):
        try:
            ergebnis = subprocess.run(
                befehl,
                shell=(sys.platform == "win32"),
                capture_output=True,
                text=True,
                timeout=120,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if ergebnis.returncode == 0:
            return
    print("  (HINWEIS: %s nicht formatiert - bitte manuell)" % pfad.name)


def main() -> int:
    sys.path.insert(0, str(ROOT / "tool"))
    import make_terms  # noqa: E402  (die Inhalte stehen dort)

    GEN.mkdir(parents=True, exist_ok=True)
    paare = [
        (make_terms.DE, "kTermsDe", "terms_de.dart"),
        (make_terms.EN, "kTermsEn", "terms_en.dart"),
    ]
    for daten, klasse, name in paare:
        pfad = GEN / name
        pfad.write_text(render_dart(daten, klasse), encoding="utf-8", newline="\n")
        print("  -> lib\\generated\\%s" % name)
        formatiere(pfad)
    return 0


if __name__ == "__main__":
    sys.exit(main())
