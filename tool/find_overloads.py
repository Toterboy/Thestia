import os, re
from collections import defaultdict
sigs = defaultdict(list)
migdir = "supabase/migrations"
for fn in sorted(os.listdir(migdir)):
    if not fn.endswith(".sql"):
        continue
    src = open(os.path.join(migdir, fn), encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"CREATE OR REPLACE FUNCTION\s+(?:public\.)?(\w+)\s*\((.*?)\)\s*RETURNS", src, re.S | re.I):
        name, args = m.group(1), " ".join(m.group(2).split())
        # Split args on top-level commas
        depth, cur, parts = 0, "", []
        for ch in args:
            if ch in "([":
                depth += 1
            elif ch in ")]":
                depth -= 1
            if ch == "," and depth == 0:
                parts.append(cur.strip()); cur = ""
            else:
                cur += ch
        if cur.strip():
            parts.append(cur.strip())
        # normalize: name + type (strip DEFAULT ...)
        norm = []
        for p in parts:
            p2 = re.split(r"\s+DEFAULT\s+", p, flags=re.I)[0].strip()
            toks = p2.split()
            norm.append(" ".join(toks[-2:]) if len(toks) >= 2 else p2)
        sigs[name].append((fn, norm))
for name, versions in sorted(sigs.items()):
    uniq = []
    for fn, norm in versions:
        if norm not in [u[1] for u in uniq]:
            uniq.append((fn, norm))
    if len(uniq) > 1:
        print("OVERLOAD:", name)
        for fn, norm in versions:
            print("   ", fn, "(", ", ".join(norm), ")")
