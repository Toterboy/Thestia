import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'hilfen'
    ),
)
import l10n_texts  # noqa: E402

# DIE TEXTE LIEGEN NACH THEMEN GETRENNT (lib/l10n/strings/).
de, _en = l10n_texts.lies_sprachen()
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
