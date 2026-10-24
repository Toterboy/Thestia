import os
import sys

hits = []
for root, dirs, files in os.walk("lib"):
    for f in files:
        if not f.endswith(".dart"):
            continue
        p = os.path.join(root, f)
        # lib/generated/ entfaellt: die Datei wird aus dem
        # Datenschutztext erzeugt. Die Gedankenstriche dort sind
        # Satzzeichen eines Fliesstexts (z. B. "v0.10.0 - Aussehen-Merkmale"
        # in der Aenderungstabelle), keine UI-Beschriftung. Die Pruefung
        # gilt fuer den App-Text, den die Nutzer als Button- oder
        # Dialogbeschriftung lesen.
        if os.path.normpath(p).startswith(os.path.join("lib", "generated")):
            continue
        for i, line in enumerate(open(p, encoding="utf-8").read().splitlines(), 1):
            s = line.strip()
            # Kommentare/Zeilen ohne String-Literale ignorieren
            if s.startswith("//") or s.startswith("///"):
                continue
            if "\u2013" in line or "\u2014" in line:
                # Nur melden, wenn in einem String-Literal
                q1 = line.find("'")
                q2 = line.find('"')
                pos = min([x for x in (q1, q2) if x >= 0] or [10**9])
                e1 = max(line.find("\u2013"), line.find("\u2014"))
                if pos < e1:
                    hits.append("%s:%d: %s" % (p, i, line.strip()[:110]))
print("\n".join(hits) if hits else "KEINE Gedankenstriche in Nutzer-Texten")
print("TOTAL:", len(hits))

# BUG (gefunden am 22.10.2026): dieses Skript hat nie einen Exit-Code
# gesetzt. Ein Treffer hat die CI deshalb nicht rot werden lassen - die
# Pruefung war dekorativ. Zwei eigene Gedankenstriche in app_strings.dart
# blieben dadurch wochenlang unentdeckt.
sys.exit(1 if hits else 0)
