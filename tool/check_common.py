import re

src = open("lib/l10n/app_strings.dart", encoding="utf-8").read()
seen = set()
for m in re.finditer(r"'(common\.[a-zA-Z0-9_.]+)'\s*:\s*'([^']*)'", src):
    key = m.group(1)
    if key not in seen:
        seen.add(key)
        print(key, "=", m.group(2)[:60])
