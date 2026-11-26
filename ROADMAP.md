# Roadmap

Öffentliche Planung ohne Termine. Was drin ist, steht drin; was nicht
drum herum steht, ist noch nicht entschieden. Die Hintergründe stehen im
[CHANGELOG](CHANGELOG.md), in den [ADRs](docs/adr/) und unter
`docs/betrieb/`.

## Die Versionsregel

- Neue Nutzerfunktion = **MINOR** (0.x.0). Fixes und Polish = **PATCH**
  (0.x.y).
- Auch eine Änderung der Datenverarbeitung **für Nutzende** ist eine neue
  Nutzerfunktion.
- **Eine noch nie veröffentlichte Fassung wird nicht neu nummeriert.**
  Ist die aktuelle Fassung (z. B. 0.10.2) noch nicht draußen, gehören
  ihre Fixes zu **ihr** – es gibt nur eine neue Build-Nummer. Erst wenn
  eine Fassung veröffentlicht wurde, zählt der Sprung auf die nächste
  Nummer. (Zwei Mal passiert: 22.11.2026 mit Build 57 und 24.11.2026 mit
  Build 58 – beide Male hätte die Nummer bleiben müssen.)
- Jede Fassung hat einen Build; der Build ist das, was im Store liegt.
  Der Admin-Build hat eine eigene Build-Nummer (Basis + 9000).
- Eine Abweichung von der Regel wird im [CHANGELOG](CHANGELOG.md)
  begründet – nicht stillschweigend.

## Umgesetzt

- **0.5.0** – Erste öffentliche Beta: Find your Match, Zufallschat,
  QR-Verbindung, Dating Hour, Quiz-Freischaltung, 2FA/Passkeys,
  E2E-Chats und -Anrufe, Video-Verifizierung, Entfernungsanzeige
- **0.6.x** – 6 Farbschemata, verschlüsseltes E2E-Key-Backup
  (PBKDF2 + AES-256-GCM), Safety Center, Bild-Blur im Chat mit
  Meldungs-Workflow, UnifiedPush, Build-Flavors `play`/`fdroid`,
  „Funke“-Umbenennung, Passkey-Diagnose, Accessibility-Durchlauf
  (ScreenReader-Labels, Text-Skalierung bis 3,2×)
- **0.7.0** – Sicherheitsaudit: serverseitig erzwungener Jugendschutz,
  Session im Keystore/Keychain, E2E-Reparatur (PreKey- und
  SignedPreKey-Rotation, persistenter Identity-Trust), vollständige
  Account-Löschung inkl. Storage-Wipe, Anti-Trilateration,
  EXIF-Stripping, Zertifikat-Pinning, offene Registrierung
- **0.7.1** – Doppelte E-Mail-Registrierung abgefangen, Ladekreis ab dem
  ersten Start, Stadt/Ort + Präferenzen serverseitig (überstehen
  Neuinstallationen), Standort-Erkennung ohne Einfrieren, 2FA-„Später
  erinnern“, abgerundete Dropdowns, englische Auth-Texte, Bild-Meldung mit
  NSFW-KI-Vorprüfung, Admin-Sperrwerkzeug mit Begründung
- **0.7.2** – Dating Hour: Startzeit 20:00 Europe/Berlin, Mindestteilnehmer
  20, keine Partner-Dopplungen, Admin-Blackscreen behoben, Zurück-Geste
  beendet die App nicht
- **0.7.3** – Altersspanne im Profil-Editor, Ladekreis nach dem
  Anmelden-Klick, Dating-Hour-Rückzug führt zur Seite davor,
  Teilnehmer-Fortschritt „X von 20“, 2FA-Anzeige mit frischem MFA-Status,
  Auto-Logout nach Stunden, Benachrichtigungs-Symbol, Reporter-Pseudonymisierung,
  Nachweis-Pflicht für Bild-Meldungen, 20er-Ziel nur mit Accounts ab 24 h
- **0.8.0** – Musik-Geschmack (inkl. „Instrumental“), 60 echte
  Quiz-Fragen, eigene Kategorie „Erschlossene Funken“ (ohne Countdown und
  ohne Verlängern-Druck), Chatverwaltung (ausblenden, Re-Funke ohne Druck),
  Ideen-Rad im Meet-Intent, Dating Hour ausgebaut (Frage-Karten für
  Schüchterne), sichtbarer Verbindungs-Score, ehrliches Beenden
  (Absage-Texte), NSFW on-device (gebündeltes Modell, dauerhaft getestet),
  Profilbild-Prüfung beim Upload mit Einspruch-Dialog, i18n-Ausbau,
  serverseitige UI-Einstellungen (Blind Mode, Sichtbarkeit, Dark Mode,
  Benachrichtigungen, Blur)
- **0.9.0** – **Transit Spark** (BLE-Nahbereichs-Funke): Encounter-Cache
  (45 min), Advertising/Scanning, Matching per RPC `match_proximity_spark`
  mit Jugendschutz, Messe-Modus (RSSI-Schärfe), Merkmals-Tags,
  `public_profiles` als SECURITY-DEFINER-RPCs, Entdecken-Gruppierung
  („Unterwegs“), Onboarding als Interview (Frage-Bubbles, zweisprachig),
  Soft-Ping (einseitiges Anschreiben, genau ein Versuch je Begegnung)
- **0.10.0** – **Standort-Privatisierung**: Der Ort (Stadt) wird nicht mehr
  erhoben, gespeichert oder angezeigt; sichtbar ist nur das Bundesland.
  Die Koordinaten liegen auf einem serverseitig erzwungenen 5-km-Raster in
  einer nur für den Eigentümer lesbaren Tabelle. Die Entfernungsanzeige ist
  aus und zustimmungspflichtig. Dazu: **Transit Spark auf echten Geräten**
  (BLE-Gerätetest bestanden), BLE-Härtung im Funk (Token-Rotation mit
  Jitter, gepulstes Scanning, frisches Token nach jedem Neustart),
  **Find-your-Spark-Ausbau** (Zufall und Kategorien, serverseitige
  Altersgrenze), **Elternaufsicht für 16- und 17-Jährige**,
  Vorstellungs-Vorlagen (Text + Audio), Suchfilter mit drei echten Modi,
  Suchradius für Minderjährige begrenzt (25 km), Admin-Posteingang, kein
  Session-Fix über einen Deep-Link, `FLAG_SECURE` auf allen Bildschirmen,
  öffentliches Threat-Model
- **0.10.1** (Build 51/52/54/55) – **Die eigene Tastatur im Chat**
  (Build 54: die Systemtastatur sieht im Chat keinen einzigen Buchstaben),
  **Der Name bei Transit Spark ist abschaltbar** (der Nutzer entscheidet
  selbst – Dialog beim ersten Öffnen, Schalter jederzeit änderbar),
  „Nachricht für alle löschen“ (der Server speichert nur die Tatsache,
  keinen Inhalt), Transit Spark: mehrere mit derselben Beschreibung
  anschreiben, ungefährer Ort als Selbstauskunft statt als Standort,
  serverseitiger Nachrichtenzähler, Kategorie-Sicht ohne Sackgasse
- **0.11.0** (Build 60) – **Die Nachricht überdenken** und **die
  eigene Tastatur wird einstellbar**. Vor dem Senden fragt die App, wie
  der Nutzer die Nachricht selbst versteht – und ob sie wirklich so
  bleiben soll. Einstellbar im Drei-Punkte-Menü des Chats: bei jeder
  Nachricht, ab etwa 250 Zeichen oder nur über einen Extra-Knopf, global
  für alle Kontakte oder je Kontakt/Funke einzeln. Die App-Tastatur
  (Build 54) bekommt ihren eigenen Hintergrund (wie die App, in der
  Akzentfarbe der Farbwelt oder eine eigene Farbe) und ihre eigene
  Belegung (wie die App, immer QWERTZ, immer QWERTY) – App-Sprache und
  Werkzeug sind damit getrennt
- **0.10.2** (Build 56/57/58/59) – **Das Impressum steht als Text in der App**
  (der verifizierte App-Link öffnete die App selbst statt des Browsers),
  **die Funkenliste lädt wieder** (drei `STABLE`-Funktionen schrieben in
  die Datenbank → HTTP 405), Schalter je Punkt für das öffentliche Profil
  (Musik, Lieblingssong, Lieblingskünstler, Gewohnheiten), eigene Screens
  für blockierte Nutzer und Meldungen im Safety Center, echter
  Geburtstags-Hintergrund, runde Chat-Bilder ohne Rahmen, der Zufallschat
  fragt beim Verlassen nach, die Auswahl im Auswahl-Modus der
  Funken-Liste schneidet den Knopf nicht mehr ab, deutlicher Testausbau
  (Build 58: der Sicherheitscheck bleibt bei großer Schrift bedienbar,
  die Bildauswertung der Altersprüfung ist getestet, gemeldete Bilder
  lassen sich speichern; Build 59: das Funk-Radio meldet nach dem
  Pausieren das richtige Token, das Bundesland-Feld der Ersteinrichtung
  läuft nicht mehr aus dem Rahmen, eine zweite Instanz des
  Verschlüsselungs-Dienstes lässt keinen Fehler ungehandelt laufen, die
  Restzeit der Dating Hour passt bei großer Schrift)

## In Arbeit

- [x] **Website-Umzug auf Infomaniak** (Netlify bleibt als Fallback;
  `thestia.de` und `auth.thestia.de` werden dort getrennt - eigene
  Verzeichnisse, eigene Zertifikate; DNS und Zertifikate stehen, der
  Upload ist am 23.11.2026 erfolgt. Der Sicherheitscheck bekommt das
  Design der Website. Details: docs/betrieb/WEBSITE-HOSTING.md)
- [ ] **F-Droid-Einreichung** (google-freier Flavor, UnifiedPush,
  Fastlane-Metadaten liegen vor; die Einreichung steht aus)
- [~] **Branding-Feinschliff** (Store-Icon 512×512, Feature Graphic
  1024×500 und Favicon sind erzeugt; offen sind die Masken und die
  Farbwirkung)
- [x] Store-Listing auch auf Englisch (eigene Screenshots und eigenes
  Feature Graphic je Sprache)
- [x] Vorstellungs-Vorlagen (Text + Audio)

## Geplant

### 0.11.0 – Emotionaler Rückzugsort (Sanctuary) & lokaler KI-Reflexions-Chat

- Ein **vollständig offline** geschützter Raum zur Selbstreflexion bei
  Frust, Zurückweisung oder emotionalen Tiefs – betrieben von rein lokalen
  Sprachmodellen. Kein Server, kein Konto, keine Weitergabe: Was im
  Sanctuary geschrieben wird, bleibt im RAM (optional lokal
  AES-verschlüsselt)
- **Die eigene Tastatur wird einstellbar**: der Hintergrund (wie die App /
  in der Farbe der App / eigene Farbe) und die Belegung unabhängig von der
  App-Sprache (QWERTZ oder QWERTY). Beides kommt in `ui_prefs` – ohne
  Migration und ohne neue Daten
- **Nachricht überdenken**: vor dem Senden fragt die App, wie der
  Nutzer die Nachricht selbst versteht und ob sie wirklich so bleiben
  soll. Einstellbar im Drei-Punkte-Menü des Chats – für alle Kontakte
  oder je Kontakt/Funke einzeln
  - wann gefragt wird: bei jeder Nachricht, ab etwa 250 Zeichen oder
    nur über einen Extra-Knopf im Eingabefeld
  - die eigene Deutung bleibt auf dem Gerät: sie wird nicht gesendet
    und nirgends gespeichert
  - **umgesetzt in Build 60** (siehe oben unter „Umgesetzt")
- **Die eigene Tastatur wird einstellbar** (die App-Tastatur aus
  Build 54): der **Hintergrund** (wie die App, in der Akzentfarbe der
  Farbwelt oder eine eigene Farbe) und die **Belegung** (wie die App,
  immer QWERTZ, immer QWERTY). Die Tastatur folgt damit nicht mehr
  blind dem Sprachumschalter – App-Sprache und Werkzeug sind getrennt.
  Beide Schalter stehen in `ui_prefs` und überstehen damit eine
  Neuinstallation
  - **umgesetzt in Build 60** (siehe oben unter „Umgesetzt")
- Details: [docs/technik/lokale-ki-reflexion.md](docs/technik/lokale-ki-reflexion.md)

### 0.12.0 – Web-Bridge, Transit-Reachability & Zero-Install-Gast-Verbindungen

- **Flutter Web für Gäste ohne Konto** unter eigener Domain
  (`web.thestia.de`, ein CNAME bei Spaceship – kein Nameserver-Wechsel)
- **OS-Level „System-Ping“**, passiver Funk-Leuchtturm,
  Fahrplan-Synchronisation mit Live-Strecken-Board, Same-Train-Matching,
  interaktive Web-Visitenkarte, Treffpunkt-Orchestrator („Mittendrin“)
- **Gruppen und Foren** kommen danach
- Details: [docs/technik/web-bridge.md](docs/technik/web-bridge.md)

## Ideen (nicht eingeplant)

- Eigene Chat-Hintergründe zeichnen (eigene Farbverläufe, Muster-Zeichner
  als Vektor, fremde Muster der Gegenseite als Vorlage)
- Spenden-Button mit echter Zieladresse (Abwicklung, steuerliche
  Behandlung, Beleg, Rückerstattung)
- Eigene Komponenten statt Standard-Widgets (eine Optik statt drei)
- Admin-Screen-Überarbeitung (internes Werkzeug: Kennzahlen, Suche im
  Sperren-Tab, einheitliche Karten- und Empty-States)
- Gruppen-Micro-Events (2–6 Teilnehmer)
- Gesichtsfeld-Check (Profilbild vs. Verifizierungs-Video) über ein
  selbstgehostetes Open-Source-Modell
- Digitale Entgiftung: sanfte Nutzungs-Erinnerungen
- Drittanbieter als eigenes Betriebsrisiko führen (je Anbieter
  Auftragsverarbeitungsvertrag, Drittlandtransfer, Notfallplan)
- Aufbewahrungskatalog konsolidieren (einschließlich Backups,
  Pre-Key-Speicher und Push-Payloads)
- Date-Safety-Check-in nach einem echten Treffen (dezent, rein lokal –
  steht im Konflikt mit dem Standortabgleich aus 0.12.0)
- Privacy-Dashboard im Profil (welche Daten liegen nur lokal, welche
  serverseitig)
- „Abschied in die Realität“: nach einem bestätigten Treffen ein
  sanfter, einmaliger Vorschlag zum direkten Kontaktaustausch

## Wo die Details stehen

Öffentlich (im Repository):

- [CHANGELOG.md](CHANGELOG.md) – was in welcher Fassung drin war, mit den
  Hintergründen der Fehler, die zu den Änderungen führten
- [docs/technik/elternaufsicht.md](docs/technik/elternaufsicht.md) – die
  Aufsicht für 16- und 17-Jährige
- [docs/technik/lokale-ki-reflexion.md](docs/technik/lokale-ki-reflexion.md)
  – der Plan für 0.11.0
- [docs/technik/web-bridge.md](docs/technik/web-bridge.md) – der Plan für
  0.12.0
- [passkey-assets/threat-model.md](passkey-assets/threat-model.md) – das
  öffentliche Threat-Model (auf der Website)
- [docs/betrieb/WEBSITE-HOSTING.md](docs/betrieb/WEBSITE-HOSTING.md) – das
  Webhosting

Lokal (nicht im Repository, beim Betreiber):

- `docs/adr/` – die Entscheidungen, die gelten
- `docs/betrieb/BETRIEBSAUFGABEN.md` – der Betrieb, die Abnahme und die
  offenen Punkte
- `docs/recht/` – Datenschutz, DSFA, die Entwürfe
- `docs/technik/offene-entscheidungen.md` – was noch offen ist (Recht,
  Produkt, Technik – jeweils mit dem Ort, an dem es entschieden wird)
