# WispDating v0.7.2-Beta – Release Notes

> **⚠️ End of Support (seit 24.09.2026):** Diese Version wird **nicht mehr unterstützt** (Bug- und Security-Fixes eingestellt). Bitte auf **v0.9.0 oder neuer** aktualisieren – siehe [SUPPORT.md](../../SUPPORT.md).


Das Dating-Hour-Update: Die Dating Hour startet jetzt zur richtigen Zeit,
ist fairer (keine Wiederholungen, Mindestteilnehmer) und der Admin-Bereich
ist aufgeräumt. Danke an alle Tester von v0.7.1!

## Hinzugefügt

**Dating Hour: Mindestteilnehmer** Die Dating Hour findet erst ab 20
angemeldeten Personen statt. Reicht es nicht aus, fällt das Event aus und
wird im Screen klar angezeigt - so gibt es keine sinnlosen Runden.

**Dating Hour: keine Wiederholungen** Das Matching bevorzugt Personen,
mit denen du noch NIE in einer Dating Hour warst. Erst wenn keine neue
Kombination mehr möglich ist, kann jemand erneut zugeteilt werden.

**Alters-Hinweis im Dating-Hour-Chat** Liegen zwischen dir und deinem
Chat-Partner mindestens 10 Jahre, erscheint ein respektvoller Hinweis
im Chat.

**Dating-Hour-Präferenzen bleiben erhalten** Deine zuletzt genutzten
Präferenzen (Alter, Geschlecht, besonderes Merkmal, Entfernung,
Gewohnheiten) werden gespeichert und beim nächsten Mal automatisch
vorausgefüllt - auch nach einer Neuinstallation.

**Mood of the Day für alle sichtbar** Deine heute gewählte Stimmung
kann jetzt von anderen gesehen werden.

## Behoben

**Dating Hour startet zur richtigen Zeit** Die Dating Hour startet jetzt
zuverlässig um 20:00 Uhr deutscher Zeit - mit automatischer Umstellung
zwischen Sommer- und Winterzeit. (Bisher startete sie je nach Jahreszeit
eine bis zwei Stunden später.)

**Admin-Bereich** Der Verlassen-Button verursachte einen schwarzen
Bildschirm - behoben. Die Listen sehen jetzt aus wie der Rest der App.

**Zurück-Geste** In der Dating Hour beendet die Zurück-Geste nicht mehr
die App, sondern navigiert ordentlich zurück.

**Passkey-Erstellen mit 2FA** Wer 2FA aktiviert hat, wird jetzt vor dem
Anlegen eines Passkeys nach dem 2FA-Code gefragt - vorher schlug die
Erstellung mit einer unverständlichen Meldung fehl.

## Deployment-Hinweis (Betreiber)

Vor dem Rollout: Migration **067** ausführen (Dating-Hour-Zeiten,
Mindestteilnehmer, Dopplungs-Schutz, Mood-Infrastruktur) sowie die
Migrationen 064-066, falls noch nicht geschehen.
