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
                    if t.strip() and t not in ("…", "...", "000000"):
                        print(p, i, "|", t[:85])
                    break
