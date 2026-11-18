"""Pinnt die GitHub-Actions in den Workflows auf Commit-SHAs.

WARUM (Sicherheits-Audit 16.11.2026, P2): Ein Action-**Tag** ist eine
veränderliche Referenz. Wer das Tag-Repository (oder ein Konto mit
Push-Recht darauf) kompromittiert, schiebt neuen Code in den
Workflow - und der Nachtlauf haette dann Zugriff auf die
Repository-Secrets (Supabase-Key, DB-Verbindung). Mit einem Commit-SHA
ist die ausgefuehrte Version fest.

NACH DEM LAUFEN: Die Tags nicht vergessen - jede neue Version muss
bewusst per SHA nachgezogen werden (das Skript unten macht das).

    python tool\pin_github_actions.py --check    # nur pruefen (CI-Gate)
    python tool\pin_github_actions.py --write    # auf SHAs umstellen
"""

from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"

# Aktuelle Stände (16.11.2026, gegen die GitHub-API geprueft).
BEKANNT = {
    "actions/checkout": "v5",
    "actions/setup-java": "v5",
    "actions/setup-python": "v6",
    "actions/upload-artifact": "v6",
    # Der Cache fuer die onnxruntime-Bibliothek (18.11.2026): ohne ihn
    # scheitert der Lauf am Download (GitHub-Antwortet dann mit einem
    # Timeout).
    "actions/cache": "v4",
    "subosito/flutter-action": "v2",
}

# Zeilen wie "uses: actions/checkout@v5" (mit optionalem Kommentar).
VERWENDUNG = re.compile(
    r"(?P<prefix>uses:\s*)(?P<repo>[\w.-]+/[\w.-]+)@(?P<tag>v?[\w.\-+]+)(?P<rest>\s*#.*)?$",
    re.MULTILINE,
)


def hole_sha(repo: str, tag: str) -> str:
    """Loest ein Tag auf den Commit-SHA auf (annotated tags mitfuehren)."""
    url = f"https://api.github.com/repos/{repo}/git/ref/tags/{tag}"
    anfrage = urllib.request.Request(
        url, headers={"User-Agent": "thesia-pin-actions", "Accept": "application/json"}
    )
    with urllib.request.urlopen(anfrage, timeout=30) as antwort:
        import json

        daten = json.loads(antwort.read().decode("utf-8", errors="replace"))
    objekt = daten["object"]
    if objekt["type"] == "tag":
        url2 = f"https://api.github.com/repos/{repo}/git/tags/{objekt['sha']}"
        anfrage2 = urllib.request.Request(
            url2,
            headers={"User-Agent": "thesia-pin-actions", "Accept": "application/json"},
        )
        with urllib.request.urlopen(anfrage2, timeout=30) as antwort2:
            daten2 = json.loads(antwort2.read().decode("utf-8", errors="replace"))
        return daten2["object"]["sha"]
    return objekt["sha"]


def main() -> int:
    schreiben = "--write" in sys.argv
    nur_pruefen = "--check" in sys.argv
    if not schreiben and not nur_pruefen:
        print("Aufruf: python tool\\pin_github_actions.py [--check|--write]")
        return 1

    shas: dict[str, str] = {}
    for repo, tag in BEKANNT.items():
        try:
            shas[repo] = hole_sha(repo, tag)
        except (urllib.error.URLError, urllib.error.HTTPError, KeyError) as fehler:
            print(f"FEHLER: {repo}@{tag} nicht abrufbar: {fehler}")
            return 1

    gefunden = False
    geaendert = 0
    for datei in sorted(WORKFLOWS.glob("*.yml")):
        text = datei.read_text(encoding="utf-8")
        neu = text
        for treffer in VERWENDUNG.finditer(text):
            repo = treffer.group("repo")
            tag = treffer.group("tag")
            if repo not in shas:
                continue
            if re.fullmatch(r"[0-9a-f]{40}", tag):
                continue  # schon gepinnt
            alt = f"{treffer.group('prefix')}{repo}@{tag}"
            neu_pinnt = f"{treffer.group('prefix')}{repo}@{shas[repo]}"
            if schreiben:
                neu = neu.replace(alt, neu_pinnt)
                geaendert += 1
            else:
                gefunden = True
                print(
                    f"{datei.relative_to(ROOT)}: NICHT gepinnt: {alt} "
                    f"(sollte {shas[repo]} sein)"
                )
        if schreiben and neu != text:
            datei.write_text(neu, encoding="utf-8", newline="\n")

    if schreiben:
        print(f"{geaendert} Verwendung(en) auf Commit-SHAs umgestellt.")
        for repo, sha in shas.items():
            print(f"  {repo} -> {sha}")
        return 0

    if gefunden:
        print()
        print("FEHLER: Es gibt Actions ohne SHA-Pin.")
        print("Beheben mit: python tool\\pin_github_actions.py --write")
        return 1
    print("OK: alle Actions sind auf Commit-SHAs gepinnt.")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
