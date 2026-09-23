# ProGuard/R8-Regeln (v0.9.0, Manipulationsschutz).
#
# PlayIntegrityHelper wird von MainActivity per REFLECTION geladen
# (Class.forName, damit F-Droid ohne die Klasse baut). R8 sieht
# Reflection nicht und würde die Klasse entfernen/umbenennen - danach
# fände forName("com.wisp.app.PlayIntegrityHelper") nichts mehr und
# Play Integrity wäre im Release still tot. Deshalb: Name + Member
# behalten. Alles andere bleibt obfuskiert/verkleinert wie bisher.
-keep class com.wisp.app.PlayIntegrityHelper { *; }
