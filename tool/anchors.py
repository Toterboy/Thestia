import re

src = open("lib/l10n/app_strings.dart", encoding="utf-8").read()
parts = src.split("'en':")
de = parts[0]
anchors = [
    "common.back",
    "auth.email",
    "dh.chat.hint",
    "meet.ideas",
    "random.connecting",
    "profile.detail.music",
    "bugreport.sendFailed",
    "mfa",
    "unban",
    "music",
    "admin",
    "personality",
    "onboarding.done",
    "welcome",
    "auth.keepLoggedIn",
]
for anchor in anchors:
    ms = [
        (m.start(), m.group(0)[:48])
        for m in re.finditer("'" + anchor, de)
    ]
    print(anchor, "->", len(ms))
    for pos, t in ms[:8]:
        print("   L", de[:pos].count("\n") + 1, t)
