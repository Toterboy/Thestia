import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..', 'hilfen'
    ),
)
import l10n_texts  # noqa: E402

# DIE TEXTE LIEGEN NACH THEMEN GETRENNT (lib/l10n/strings/).
de_block, en_block = l10n_texts.lies_sprachen()
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

# BUG (gefunden am 22.10.2026): dieses Skript hat nie einen Exit-Code
# gesetzt und nur ausgegeben, wie viele Keys es je Praefix fand. Ein
# fehlender englischer Schluessel fiel dadurch nicht auf.
#
# JETZT: fuer jeden Praefix muessen DE und EN dieselben Keys haben. Ein
# Schluessel, der nur in einer Sprache existiert, bricht die Anzeige in
# der anderen Sprache (L10n.faellt auf den Schluesselnamen zurueck).
findings = []

for prefix in prefixes:
    de_keys = set(
        re.findall(r"'" + prefix + r"\.[a-zA-Z0-9_.]+'", de_block)
    )
    en_keys = set(
        re.findall(r"'" + prefix + r"\.[a-zA-Z0-9_.]+'", en_block)
    )
    print(prefix, "-> DE:", len(de_keys), "EN:", len(en_keys))
    for k in sorted(de_keys):
        print("   ", k)

    only_de = sorted(de_keys - en_keys)
    only_en = sorted(en_keys - de_keys)
    if only_de:
        print("   FEHLT in EN:", only_de)
        findings.append("%s: nur auf Deutsch: %s" % (prefix, only_de))
    if only_en:
        print("   FEHLT in DE:", only_en)
        findings.append("%s: nur auf Englisch: %s" % (prefix, only_en))

print()
if findings:
    for f in findings:
        print("BEFUND:", f)
sys.exit(1 if findings else 0)
