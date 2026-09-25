# Thestia v0.9.1 – Release Notes

**Umbenennung:** Aus WispDating wird **Thestia** – neuer Name, neues
Logo, neue Domains und neue App-ID. Bitte unbedingt den Abschnitt
„Umstellung" unten lesen (Neuinstallation erforderlich).

## Umstellung WispDating → Thestia (wichtig!)

- **Neu installieren:** Die App-ID hat gewechselt (`com.thestia.app`).
  Die alte WispDating-App aktualisiert sich **nicht** von selbst – bitte
  `Thestia-v0.9.1-play.apk` (oder `-fdroid.apk`) neu installieren. Die
  alte App kann danach deinstalliert werden.
- **Konto & Daten bleiben:** Profil, Einstellungen, Funken und Chats
  liegen serverseitig und sind nach dem Login wieder da.
- **Passkeys neu anlegen:** Passkeys sind an die alte Domain gebunden
  und müssen einmal neu registriert werden (Login per E-Mail + ggf.
  TOTP funktioniert weiterhin).
- **Neue Adressen:** `thestia.de` (App-Links, Bestätigungs-Mails),
  Support & Co. laufen über `@thestia.de`-Adressen.

## Neu (das Wichtigste)

- **Chat-Hintergründe:** Muster (Punkte, Linien, Herzen, Sterne, Wellen)
  oder eigenes Bild aus der Galerie – einstellbar in den Einstellungen
  und direkt in der Einrichtung. Gilt für alle Chats.
- **Willkommen nach Registrierung:** Nach der E-Mail-Bestätigung kommt
  zuerst ein kurzer Willkommensscreen, danach startet die Einrichtung.
- **Pausiert-Hinweise:** Bei pausiertem Profil zeigt „Aktuelles" eine
  Hinweis-Bubble (Tap → Einstellungen zum Entpausieren). In
  „Entdecken" blockt ein Popup die Modus-Auswahl mit Direkt-Link in
  die Einstellungen.
- **Neues Branding überall:** Thestia-Logo (Herz aus zwei Figuren) in
  App, Splash, Launcher-Icons (alle Masken geprüft) und als
  **neu gezeichnetes Benachrichtigungs-Herz** in der Statusleiste.
- **Neue Kontaktwege:** Bug-Reports, Bild-Meldungen sowie
  Konto-Sperrungen/Entsperrungsanträge laufen über die
  `@thestia.de`-Adressen (Brevo-Sender verifiziert, SPF/DKIM/DMARC).
- **Technik darunter:** Repository heißt jetzt
  `github.com/Toterboy/Thestia`, Dart-Paket `thestia`, Display-Name
  und TOTP-Issuer `Thestia`.

## Sicherheit & Betrieb

- Unverändert: E2E-Verschlüsselung (Signal), P2P (WebRTC),
  Zertifikat-Pinning, Play Integrity (Play), On-Device-NSFW-Check.
- **Betreiber-Hinweis:** FCM läuft über ein neues Firebase-Projekt
  (`FIREBASE_SERVICE_ACCOUNT_JSON`-Secret ist rotiert). Das
  Mindestversions-Gate (`app_config.min_app_version_build`) sollte auf
  **Build 29** angehoben werden, damit Alt-Builds zum Neuinstall
  auffordern.

## Dateien

- `Thestia-v0.9.1-play.apk` – Standard (Firebase/FCM-Push)
- `Thestia-v0.9.1-fdroid.apk` – Google-frei (optional UnifiedPush)
- `Thestia-v0.9.1-play-arm64.apk`, `-armv7.apk`, `-x86_64.apk` –
  kleinere Downloads pro CPU-Architektur (Play)
- `Thestia-v0.9.1-fdroid-arm64.apk`, `-armv7.apk`, `-x86_64.apk` –
  dto. (F-Droid-Stil)
- `Thestia-v0.9.1-play.aab` – Play-Store-Bundle (Pflichtformat für
  den Play-Upload)

## Unterstützte Versionen

**v0.9.1 (Build 29) und höher** werden unterstützt. Alle älteren
Versionen (v0.9.0 und älter, inkl. aller WispDating-Builds) sind
**End of Support** – bitte neu installieren (siehe Umstellung oben).
