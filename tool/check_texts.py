import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

# Alle String-Literale in UI-Positionen ohne L10n (ohne Umlaut-Filter).
targets = sys.argv[1:] or None

pats = [
    re.compile(r"Text\(\s*'((?:[^'\\]|\\.)*)'"),
    re.compile(r'Text\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r"label:\s*Text\(\s*'((?:[^'\\]|\\.)*)'"),
    re.compile(r"title:\s*Text\(\s*'((?:[^'\\]|\\.)*)'"),
    re.compile(r"subtitle:\s*Text\(\s*'((?:[^'\\]|\\.)*)'"),
    re.compile(r"hintText:\s*'((?:[^'\\]|\\.)*)'"),
    re.compile(r"labelText:\s*'((?:[^'\\]|\\.)*)'"),
    re.compile(r"tooltip:\s*'((?:[^'\\]|\\.)*)'"),
    re.compile(r"label:\s*'((?:[^'\\]|\\.)*)'"),
]

skip_files = {"app_strings.dart"}

# Ausnahmen: Texte, die bewusst NICHT uebersetzt werden.
#
# Drei Faenge, alle mit Begründung - sonst wird die Ausnahme stillschweigend
# zur Regel:
#   1. Eigennamen von Firmen und Diensten ("Supabase Inc.", "Brevo"):
#      die bleiben in jeder Sprache gleich.
#   2. Fehlercodes aus dem Backend ("moderation_disabled"): das sind
#      Schluessel, keine Woert fuer die Anzeige.
#   3. Aufzaehlungszeichen ("•"): das ist ein Glyph, kein Text.
ALLOWED = {
    "Supabase Inc.",
    "Google LLC (Firebase)",
    "Brevo",
    "Cloudflare Inc.",
    "Netlify Inc.",
    "Apple Inc.",
    "moderation_disabled",
    "moderation_unavailable",
}

findings = []

for root, dirs, files in os.walk("lib"):
    for f in files:
        if not f.endswith(".dart") or f in skip_files:
            continue
        p = os.path.join(root, f)
        if targets and not any(
            t.replace("/", os.sep) in p for t in targets
        ):
            continue
        for i, line in enumerate(
            open(p, encoding="utf-8").read().split("\n"), 1
        ):
            if "L10n" in line:
                continue
            for pat in pats:
                m = pat.search(line)
                if m:
                    t = m.group(1)
                    # Interpolationen ("$maxValue") sind keine festen
                    # Texte - sie stammen aus Werten und nicht aus einem
                    # Wortlaut im Code.
                    if "$" in t:
                        break
                    # Reine Glyphen (Aufzaehlungszeichen) sind keine Texte.
                    if all(ord(ch) > 0x2000 or ch in " \t" for ch in t):
                        break
                    if t.strip() and t not in ("…", "...", "000000") \
                            and t not in ALLOWED:
                        findings.append("%s:%d | %s" % (p, i, t[:85]))
                    break

print("\n".join(findings) if findings else "KEINE festen Texte ohne L10n")
print("TOTAL:", len(findings))

# BUG (gefunden am 22.10.2026): dieses Skript hatte keinen Exit-Code.
# Ein Treffer hat die CI nicht rot werden lassen - die Pruefung hat
# nichts gemeldet und nichts verhindert.
sys.exit(1 if findings else 0)
