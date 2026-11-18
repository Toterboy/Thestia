import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l10n_texts  # noqa: E402

# DIE TEXTE LIEGEN NACH THEMEN GETRENNT (lib/l10n/strings/).
src = l10n_texts.lies_alle()
seen = set()
for m in re.finditer(r"'(common\.[a-zA-Z0-9_.]+)'\s*:\s*'([^']*)'", src):
    key = m.group(1)
    if key not in seen:
        seen.add(key)
        print(key, "=", m.group(2)[:60])
