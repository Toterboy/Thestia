# ProGuard/R8-Regeln (v0.9.0, Manipulationsschutz).
#
# PlayIntegrityHelper wird von MainActivity per REFLECTION geladen
# (Class.forName, damit F-Droid ohne die Klasse baut). R8 sieht
# Reflection nicht und würde die Klasse entfernen/umbenennen - danach
# fände forName("com.thestia.app.PlayIntegrityHelper") nichts mehr und
# Play Integrity wäre im Release still tot. Deshalb: Name + Member
# behalten. Alles andere bleibt obfuskiert/verkleinert wie bisher.
-keep class com.thestia.app.PlayIntegrityHelper { *; }

# org.jni_zero (BEFUND 08.11.2026, Build 48): Das Paket `jni` erzeugt
# diese Java-Klassen zur BUILD-Zeit (in einem eigenen Gradle-Modul).
# R8 findet sie beim Shrinken des Release-Builds nicht im Klassenpfad
# und meldet sie als "missing class" - der Release-Build bricht dann ab
# ("Missing classes detected while running R8").
#
# WIE ES DAHER KOMMT: Mit dem SDK-Update (Flutter 3.47.9) hat sich
# `path_provider_android` auf 2.3.1 aufgeloest, das ueber
# `jni_flutter` an `jni` haengt. `jni` wird im Dart-Code nicht
# benutzt - es ist eine transitive Abhaengigkeit.
#
# Die Regel ist die vom Android-Gradle-Plugin selbst erzeugte
# (build/app/outputs/mapping/playRelease/missing_rules.txt). Die Klasse
# existiert zur Laufzeit (im jni_zero-Artefakt), sie ist nur fuer R8
# nicht sichtbar.
-dontwarn org.jni_zero.JniZeroJni
