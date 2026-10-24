import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

src = open("lib/l10n/app_strings.dart", encoding="utf-8").read()
de_block, en_block = src.split("'en':")
de_keys = set(re.findall(r"'([a-zA-Z0-9_.]+)'\s*:", de_block))
en_keys = set(re.findall(r"'([a-zA-Z0-9_.]+)'\s*:", en_block))

# BUG (gefunden am 22.10.2026): dieses Skript hat nie einen Exit-Code
# gesetzt. Fehlende Uebersetzungen, Gedankenstriche und undefinierte Keys
# haben die CI deshalb nicht rot werden lassen.
#
# Ausnahmen mit Begründung:
#   'de' - Sprachcode, kein UI-Text.
#   'km' - Einheitenabkuerzung, in beiden Sprachen gleich.
ALLOWED_DE_ONLY = {"de", "km"}

findings = []

de_only = sorted(de_keys - en_keys - ALLOWED_DE_ONLY)
en_only = sorted(en_keys - de_keys)
print("DE only:", sorted(de_keys - en_keys))
print("EN only:", sorted(en_keys - de_keys))
print("DE count:", len(de_keys), "EN count:", len(en_keys))
if de_only:
    findings.append("nur auf Deutsch: %s" % de_only)
if en_only:
    findings.append("nur auf Englisch: %s" % en_only)

# Gedankenstriche in Nutzer-Texten
for i, line in enumerate(src.splitlines(), 1):
    if "\u2013" in line or "\u2014" in line:
        print("GEDANKENSTRICH app_strings.dart:%d: %s" % (i, line.strip()[:100]))
        findings.append("Gedankenstrich in app_strings.dart:%d" % i)

# Verwendete, aber undefinierte Keys
used = set()
for root, dirs, files in os.walk("lib"):
    for f in files:
        if not f.endswith(".dart"):
            continue
        p = os.path.join(root, f)
        if p.endswith("app_strings.dart"):
            continue
        for m in re.findall(r"L10n\.tf?\(\s*context,\s*'([a-zA-Z0-9_.]+)'", open(p, encoding="utf-8").read()):
            used.add((m, p))
all_keys = de_keys | en_keys
missing = sorted({k for k, _ in used} - all_keys)
print("USED undefined keys:", missing if missing else "none")
from collections import defaultdict
by_file = defaultdict(list)
for k, p in used:
    if k in missing:
        by_file[p].append(k)
for p, ks in sorted(by_file.items()):
    print("  ", p, sorted(set(ks)))
if missing:
    findings.append("undefinierte Keys: %s" % missing)

print()
if findings:
    for f in findings:
        print("BEFUND:", f)
sys.exit(1 if findings else 0)
