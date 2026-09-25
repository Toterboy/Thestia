# ADR-0007: Präsenz-frei (kein Online-Status, kein „schreibt…")

- Status: angenommen
- Datum: 2026-08-24

## Kontext

Messenger zeigen üblicherweise Online-Status, „schreibt gerade“-Indikatoren
und Lesebestätigungen. Für eine Dating-Zielgruppe erzeugt das
Verpflichtungsdruck („warum antwortest du, du warst doch online?“) und
belohnt ständige App-Nutzung – das Gegenteil des Thestia-Ziels,
Dating zurück ins echte Leben zu bringen.

## Entscheidung

Thestia ist bewusst **präsenz-frei**:

- Kein Online-/Offline-Status
- Kein „schreibt gerade…“
- Keine Lesebestätigungen
- Keine „zuletzt aktiv“-Angaben

Es gibt diese Daten schlicht nicht: Der Server kennt keine Sitzungs-
Zeitpunkte der Nutzer, und der Client zeigt nichts davon an. Ein späteres
Hinzufügen wäre ein Produktbruch (ADR bleibt bestehen).

## Konsequenzen

+ Weniger Druck und Kontrollmöglichkeit; Antworten erfolgen, wenn Zeit ist.
+ Datenschutzgewinn: keine Verhaltensmetadaten über Aktivitätszeiten.
− Manche Nutzer vermissen die Orientierung; Kompensation: ehrliche
  Vorstellungen statt Verfügbarkeitssignale.
