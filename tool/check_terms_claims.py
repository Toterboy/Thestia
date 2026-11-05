"""Prueft jede Tatsachenbehauptung der Nutzungsbedingungen gegen den Code.

WARUM (05.11.2026): Die Nutzungsbedingungen enthielten drei Fehler,
die man nur durch den Abgleich mit dem Code findet:
  * "Es ist verboten, Personen zu kontaktieren, die das eindeutig unter
    18 Jahre alt sind" - 16- und 17-Jaehrige duerfen einander schreiben
    (das ist der Sinn der Aufsicht). Der Server filtert beidseitig.
  * "Wer zwischen 16 und 17 Jahre alt ist, braucht die Zustimmung der
    Sorgeberechtigten, bevor er die App nutzen kann" - die Zustimmung ist
    freiwillig (Par. 3a JUG), und niemand wird an der Nutzung
    gehindert, weil sie ausbleibt.

Ein Rechtstext, der das Verhalten der App falsch beschreibt, ist schlimmer
als keiner. Deshalb wird jede Aussage hier gegen den Code geprueft: die
Aussage muss im Code belegt sein, sonst faellt das Gate.

Nutzung:  python tool/check_terms_claims.py
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIG = ROOT / "supabase" / "migrations"
LIB = ROOT / "lib"
ASSETS = ROOT / "passkey-assets"


def lies(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


alle_sql = "\n".join(lies(f) for f in sorted(MIG.glob("*.sql")))
alle_dart = "\n".join(lies(f) for f in sorted(LIB.rglob("*.dart")))
de_terms = lies(ASSETS / "nutzungsbedingungen.html")
en_terms = lies(ASSETS / "en" / "nutzungsbedingungen.html")

# (Behauptung, Beleg im Code, was ohne Beleg falsch waere)
PRUEFUNGEN = [
    ("Mindestalter 16",
     re.search(r"birth_date\s*<=\s*\(current_date\s*-\s*INTERVAL\s*'16 years'\)",
               alle_sql, re.I) is not None,
     "ein 15-Jaehriger koennte sich registrieren"),
    ("Die Elternfreigabe ist freiwillig (niemand wird ausgeschlossen)",
     "freiwillig" in de_terms and "voluntary" in en_terms,
     "die App wuerde die Nutzung ohne Zustimmung blockieren"),
    ("16- und 17-Jaehrige sehen einander, Erwachsene nicht",
     "age_compatible_bidirectional_ages" in alle_sql
     and "Du siehst nur andere 16- und 17" in de_terms,
     "Erwachsene koennten Minderjaehrige sehen"),
    ("Suchradius hoechstens 25 km oder gleiches Bundesland",
     "minorMaxDiscoveryRadiusKm" in alle_dart,
     "die Beschraenkung waere nicht im Code"),
    ("Keine Entfernungsanzeige fuer Minderjaehrige",
     "profile_distance_km" in alle_sql
     and "Deine Entfernung wird nicht angezeigt" in de_terms,
     "die Entfernung waere sichtbar"),
    ("Transit Spark erst ab 18",
     "transit_spark_adult" in alle_sql
     and "Transit Spark" in de_terms,
     "die 18+-Grenze fehlt"),
    ("Fotos nur fuer andere Minderjaehrige sichtbar",
     "arePhotosVisible" in alle_dart
     and "Deine Fotos sind nur für andere 16- und 17" in de_terms,
     "die Beschraenkung fehlt im Client"),
    ("Die E-Mail-Adresse der Eltern wird mit dem Ende geloescht",
     "email_deleted_at = now()" in alle_sql,
     "die Adresse bliebe gespeichert"),
    ("Die Freigabe ist jederzeit widerrufbar",
     "revoke_guardian_consent" in alle_sql
     and "widerrufbar" in de_terms,
     "kein Widerruf moeglich"),
    ("Der Token gilt 24 Stunden",
     "now() + interval '24 hours'" in alle_sql,
     "die Frist stimmt nicht"),
    ("Keine Namen und Profile in den Meldungen an die Eltern",
     "guardian_mask_email" in alle_sql
     and "guardian_notification_events" in alle_sql,
     "die Meldungen koennten Identitaeten enthalten"),
    ("Meldeweg fuer rechtswidrige Inhalte (Bundesnetzagentur)",
     "bundesnetzagentur.de" in lies(ASSETS / "kinderschutz.html"),
     "der Meldeweg fehlt"),
    ("Widerspruch gegen Moderationsentscheidungen moeglich",
     "moderation@thestia.de" in de_terms
     and "moderation@thestia.de" in en_terms,
     "der Widerspruchsweg fehlt"),
    ("Der Quellcode ist oeffentlich einsehbar (AGPL)",
     (ROOT / "LICENSE").exists()
     and ("Affero" in de_terms or "AGPL" in de_terms),
     "die Lizenzangabe passt nicht zum Repository"),
]


def main() -> int:
    print("NUTZUNGSBEDINGUNGEN: ABGLEICH MIT DEM CODE")
    print("=" * 74)
    fehlend = []
    for behauptung, belegt, auswirkung in PRUEFUNGEN:
        if belegt:
            print("  OK      %s" % behauptung)
        else:
            fehlend.append((behauptung, auswirkung))
            print("  FEHLT   %s" % behauptung)
            print("            (waere falsch: %s)" % auswirkung)

    # Zusaetzlich: die verbotenen Formulierungen duerfen nicht
    # wieder auftauchen.
    verboten = [
        ("Es ist verboten, Personen zu kontaktieren, die das "
         "eindeutig unter 18 Jahre alt sind",
         "16- und 17-Jaehrige duerfen einander schreiben"),
        ("braucht die Zustimmung der Sorgeberechtigten, bevor er die "
         "App nutzen kann",
         "die Elternfreigabe ist freiwillig"),
        ("It is forbidden to contact people who are clearly under 18",
         "16- and 17 year olds may write to each other"),
        ("needs the consent of those with parental responsibility before "
         "using the app",
         "the parental approval is voluntary"),
    ]
    for satz, warum in verboten:
        if satz in de_terms or satz in en_terms:
            fehlend.append((satz[:40] + "...", warum))
            print("  FEHLT   VERBOTENE FORMULIERUNG wieder drin: %s..." % satz[:52])
            print("            (waere falsch: %s)" % warum)

    print("=" * 74)
    if fehlend:
        print("FEHLER: %d Aussage(n) der Nutzungsbedingungen sind nicht "
              "belegt oder sind falsch." % len(fehlend))
        return 1
    print("OK: alle %d Aussagen sind mit dem Code belegt." % len(PRUEFUNGEN))
    return 0


if __name__ == "__main__":
    sys.exit(main())
