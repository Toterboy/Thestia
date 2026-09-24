# WispDating v0.8.0 – Release Notes

> **⚠️ End of Support (seit 24.09.2026):** Diese Version wird **nicht mehr unterstützt** (Bug- und Security-Fixes eingestellt). Bitte auf **v0.9.0 oder neuer** aktualisieren – siehe [SUPPORT.md](../../SUPPORT.md).


**Geschmack & Matching** – der große Feature-Meilenstein.

## Neu

- **Musik-Geschmack**: Im Profil-Editor Genres wählen, die man mag (inkl.
  „Instrumental") – und freiwillig solche, die man explizit nicht mag.
  Fließt mit 30 % in den Verbindungs-Score ein, ist im eigenen Profil und
  bei anderen (mit „Gleicher Geschmack"-Hervorhebung) sichtbar.
- **Verbindungs-Score sichtbar**: Find-your-Match zeigt „Match: X %" –
  serverseitig berechnet (Distanz 40 %, gemeinsame Interessen 30 %,
  Musik 30 %), Kandidaten sind danach sortiert.
- **Verschlüsselte Profilbilder**: Avatare werden clientseitig per
  AES-256-GCM verschlüsselt – der Server sieht nie das Klartextbild.
  Bilder überstehen Neuinstallationen und sind im öffentlichen Profil
  sichtbar.
- **NSFW-Prüfung on-device**: Profilbilder werden vor dem Upload komplett
  auf dem Gerät geprüft (gebündeltes ONNX-Modell, ~12 MB). Bei
  Nichtbestehen verlässt das Bild das Gerät nicht – wahlweise „Anderes
  Bild wählen" oder „Einspruch einlegen" (Team-Review). Auch die
  Meldungs-Vorprüfung läuft on-device.
- **Profilbild-Änderung mit Speichern-Dialog**: Bildauswahl zeigt sofort
  eine lokale Vorschau; hochgeladen wird erst beim Speichern, Abbrechen
  verwirft (das Bild war nie auf dem Server).
- **Pausenmodus in die Profil-Sichtbarkeit integriert**: EINE Steuerung –
  Jeder / Nur Funken / Unsichtbar (Pausiert) mit Bestätigungsdialog.
- **Chat-Verlauf: drei Modi**: Aus / 200 Nachrichten / kompletter Verlauf
  (Standard) – AES-256-verschlüsselt lokal (SecureHive).
- **Angemeldete Geräte mit echtem Modell**: z. B. „Samsung SM-S921B"
  statt „Android (SDK 34)".
- **Mindestversions-Gate**: Clients unter der serverseitigen Mindest-
  version zeigen einen Update-Screen.
- **Crash-Journal**: Der letzte Absturz wird lokal gespeichert; beim
  nächsten Start kann er optional gemeldet werden.
- **E-Mail-/Passwort-Wechsel in-app**, **Daten-Import** (JSON),
  **Meldungs-Feedback** und **Blockierliste** im Safety Center.
- **Erschlossene Funken** (kein Ablaufdruck) + **Re-Funke** ohne Frist.
- **Chats verwalten**: Mehrfachauswahl im Funken-Feed + „Ausblenden".
- **Ehrliches Beenden** + **Ideen-Rad** im Chat + **Dating-Hour-Frage-
  karten** für Schüchterne.
- **Quiz-Fragen-Pool**: 60 echte Fragen ersetzen die 5 Platzhalter.
- **Komplett zweisprachig (DE/EN)**: inkl. Farbschemata, Stimmungs-Chips,
  Entdecken-Modi, Sichtbarkeits-Optionen und Safety Center; konsequent
  „Funke(n)"/„Spark(s)".
- **Dating Hour**: Teilnehmer-Zähler zeigt die echte Gesamtzahl (20 ist
  nur das Mindestziel); klare Formulierung „samstags".
- **Design**: abgerundete Klick-Animation überall (auch TabBars).

## Behoben

- **„App merkt sich nichts mehr"**: Lade- und Schreibvorgänge sind
  migrations-robust – Profil-Laden zweistufig, Schreibvorgänge entfernen
  fehlende Spalten automatisch, Präferenz-/Theme-Restore dreistufig.
  Eine fehlende Migration kann nie mehr Name, Bio, Theme oder Suchradius
  gemeinsam auslöschen.
- **Sync-Fehler sichtbar**: Profil-Speichern zeigt die genaue Server-
  Fehlerursache; Diagnose-Skript `supabase/check_columns.sql` beiliegend.
- **Profilbild-Speicherung**: Die photos-Spalte existierte serverseitig
  nicht – Bilder waren bisher rein lokal. Jetzt persistent (Migration
  077) und im öffentlichen Profil sichtbar.
- **NSFW-Check still außer Kraft**: Das Modell lud nie (ONNX-IR-Version,
  Batch-Dimension, Pixelskalierung) – behoben und durch einen permanenten
  Inferenz-Test abgesichert.
- **Profilbild-Vorschau sofort**: Im Editor erscheint das gewählte Bild
  direkt; Profil, Vorschau und QR-Teilen laden Bilder ohne Wartezeit
  (Speicher-Cache), der QR-Screen zeigt jetzt das echte Profilbild.
- **Sichtbarkeits-Meldung**: Beim Wechsel Jeder ↔ Nur Funken erscheint
  keine „Pause beendet"-Meldung mehr.
- **Dating Hour**: „Täglich" korrigiert zu „samstags".

## Verteilung

| Datei | Zweck |
|---|---|
| WispDating-v0.8.0-play.apk | Google Play / direkte Verteilung (Firebase-Push) |
| WispDating-v0.8.0-fdroid.apk | F-Droid (ohne Google, UnifiedPush) |
| WispDating-v0.8.0-play-arm64.apk | Play, nur arm64 (klein) |
| WispDating-v0.8.0-play-armv7.apk | Play, nur armv7 (klein) |
| WispDating-v0.8.0-fdroid-arm64.apk | F-Droid, nur arm64 (klein) |
| admin/WispDating-v0.8.0-play-ADMIN.apk | Admin-Build (NICHT verteilen) |
| admin/WispDating-v0.8.0-fdroid-ADMIN.apk | Admin-Build F-Droid (NICHT verteilen) |

## Vor dem Rollout

1. Migrationen einspielen (der Reihe nach): **074** (Musik, Score,
   ui_prefs), **075** (Quiz-Pool), **076** (Pausenmodus, Dealbreaker,
   Mindestversion, Meldungs-Feedback), **077** (photos + View –
   Reihenfolge der View-Spalten beachten), **078** (Gerätemodell).
   Falls noch nicht geschehen: **066–073** nachziehen.
2. Gegenprobe: `supabase/check_columns.sql` im SQL Editor – alle Spalten
   müssen `true` zeigen.
3. Passkey-Origins im Dashboard prüfen (SHA-256!):
   docs/PASSKEYS_SERVER_SETUP.md.
