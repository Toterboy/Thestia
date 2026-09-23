import re
import sys

src = open("lib/l10n/app_strings.dart", encoding="utf-8").read()
de = src.split("'en':")[0]
prefixes = sys.argv[1:] or [
    "mfa",
    "unban",
    "bugreport",
    "welcome",
    "random",
    "meet",
    "music",
    "admin",
    "personality",
    "dh",
]
for prefix in prefixes:
    keys = sorted(
        set(re.findall(r"'" + prefix + r"\.[a-zA-Z0-9_.]+'", de))
    )
    print(prefix, "->", len(keys))
    for k in keys:
        print("   ", k)
