import re
import sys

import sqlglot

path = sys.argv[1]
sql = open(path, encoding="utf-8").read()
stripped = re.sub(r"\$\$.*?\$\$", "$$ DOLLAR_BODY $$", sql, flags=re.S)
print("dollar-marker:", stripped.count("$$"))
merged = stripped
prev = None
while prev != merged:
    prev = merged
    merged = re.sub(
        r"('(?:[^']|'')*')(\s*\n\s*|\s*\|\|\s*)('(?:[^']|'')*')",
        r"\1&&\3",
        merged,
    )
merged = merged.replace("&&", "")
no_strings = re.sub(r"'(?:[^']|'')*'", "''", merged)
no_strings = re.sub(r"--[^\n]*", "", no_strings)
print("paren:", no_strings.count("("), no_strings.count(")"))
try:
    stmts = [s for s in sqlglot.parse(merged, read="postgres") if s]
    print("PARSE OK:", [type(s).__name__ for s in stmts])
except Exception as e:
    print("FEHLER:", str(e)[:400])
