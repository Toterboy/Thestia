# WispDating

![CI](https://github.com/Thoralf/blind_date_app/actions/workflows/ci.yml/badge.svg)
[![Lizenz: AGPL v3](https://img.shields.io/badge/Lizenz-AGPL_v3-blue.svg)](LICENSE)

Eine moderne, datenschutzfreundliche Dating-App mit Fokus auf **Persönlichkeit statt Aussehen**. WispDating setzt auf Blind-Matching („Persönlichkeit zuerst"), Ende-zu-Ende-Verschlüsselung und Peer-to-Peer-Kommunikation, um authentischere Verbindungen zu ermöglichen. Entsteht eine Verbindung, heißt das bei uns **„Funke"**.

Das Projekt ist vollständig kostenlos nutzbar und soll eine echte Alternative zu Tinder & Co. darstellen. Es befindet sich in aktiver Entwicklung und ist noch nicht vollständig funktional. Beiträge und Feedback sind willkommen:
[Beitragen](CONTRIBUTING.md) · [Verhaltenskodex](CODE_OF_CONDUCT.md) · [Sicherheitslücken melden](SECURITY.md) · [Roadmap](ROADMAP.md) · [Changelog](CHANGELOG.md) · [Entscheidungen (ADR)](docs/adr/) · [Build & F-Droid](docs/BUILD.md) · [Architektur](docs/ARCHITEKTUR.md) · [Datenschutz](docs/DATENSCHUTZ.md) · [Passkey-Server-Setup](docs/PASSKEYS_SERVER_SETUP.md)


## Warum WispDating – und nicht Tinder, Bumble & Co.?

Weil moderne Dating-Apps genau die Probleme haben, die WispDating gezielt
löst – ohne Abo-Falle, ohne Aufmerksamkeits-Casino, ohne Daten-Hammer:

- **Persönlichkeit vor Aussehen.** Bei uns heißt der erste Schritt
  „Find your Match": Du hörst (oder liest) eine Vorstellung, bevor du ein
  Foto siehst – **Blind Mode ist Standard**, nicht Premium. Tinder zeigt
  dir zuerst das Bild; bei uns lernst du zuerst die Person kennen.
- **Ein Funke statt endlosem Swiping.** Verbindungen heißen bei uns
  **„Funken"** – und sie entstehen nur, wenn beide etwas investieren:
  Quiz-Fragen statt oberflächlicher Matches, ein Verbindungs-Score aus
  Entfernung, Interessen und **Musik-Geschmack** statt Dopamin-Feed.
- **Echt verschlüsselt – Ende-zu-Ende.** Signal-Protokoll und
  Peer-to-Peer (WebRTC) sind bei uns der Kern, kein Marketing-Versprechen.
  Selbst **Profilbilder liegen verschlüsselt** (AES-256-GCM) auf dem
  Server. Klassische Anbieter können Nachrichteninhalte grundsätzlich
  mitlesen.
- **On-Device-KI statt Auslagern.** Die NSFW-Prüfung deines Profilbilds
  läuft **komplett auf deinem Handy** – das Bild verlässt bei
  Nichtbestehen das Gerät nicht. Kein anderer Anbieter macht das.
- **Präsenz-frei.** Kein „online"-Badge, kein „schreibt gerade…", keine
  Lesebestätigungen (siehe [ADR-0007](docs/adr/0007-praesenzfrei.md)).
  Dating soll zurück ins echte Leben führen – der App-Status ist kein
  Beziehungs-Tracker.
- **Inaktivität ist okay.** Abgekühlte Funken verfallen nicht nach 24
  Stunden in den Ordnner des Vergessens: Inaktive Funken ruhen unter
  „Erschlossene Funken" und sind per Re-Funke jederzeit ohne Frist wieder
  belebbar. Keine Verlängerungs-Abos, kein Druck.
- **Dating Hour: das echte Speed-Dating-Ereignis.** Samstags 20–21 Uhr:
  5-Minuten-Chats mit Entscheidungsphase, serverzeitsynchron und
  Anti-Cheat-gesichert – als Event, nicht als zusätzliches Abo-Feature.
- **Einstellungen, die bleiben.** Profil, Suchradius, Farbwelt,
  UI-Schalter und selbst der Chat-Verlauf überstehen Neuinstallationen –
  vollständig serverseitig gespiegelt und migrations-robust.
- **Kostenlos. Für immer.** Keine Abos, keine Premium-Stufen, keine
  In-App-Käufe, keine Werbetracker. Open Source (AGPLv3) und
  selbst hostbar – inklusive Google-freier F-Droid-Variante.
- **Und bald:** Nahbereichs-Funke „Transit Spark" – anonyme
  Begegnungs-Tokens für Menschen, denen man im Zug/Café begegnet
  (v0.9.0); ein vollständig offlinefähiger Reflexions-Chat mit lokaler
  KI „Sanctuary" (v0.10.0); E2E-Chats im Browser ohne Install für
  Gäste (v0.11.0).

## Unsere Zusagen

- **Kostenlos. Für immer.** Keine Abos, keine Premium-Funktionen, keine In-App-Käufe.
- **Deine Daten werden niemals verkauft** oder für Werbung weitergegeben – es gibt schlicht kein Geschäftsmodell, das das bräuchte.
- **Präsenz-frei:** kein Online-Status, kein „schreibt gerade…“, keine Lesebestätigungen (siehe [ADR-0007](docs/adr/0007-praesenzfrei.md)). Dating soll zurück ins echte Leben.
- **Ehrliche Transparenz:** Der einzige externe Dienst, der theoretisch Verbindungs-Metadaten sehen könnte, ist Google Firebase (nur als Push-Transport, ohne Nachrichteninhalte – und nur in der Play-Variante; die F-Droid-Variante läuft komplett ohne Google via UnifiedPush). Alle Inhalte sind Ende-zu-Ende-verschlüsselt.

---

## Über die App

WispDating ist für Android konzipiert (iOS/Web/Desktop folgen) und basiert auf Flutter, Riverpod (State Management) und go_router (Navigation) im Material-3-Design. Backend ist Supabase (Auth, Postgres, Storage, Edge Functions, Realtime); Chat-Nachrichten laufen Ende-zu-Ende-verschlüsselt über das Signal Protocol, die Verbindung direkt Peer-to-Peer per WebRTC.

## Downloads

| Variante | Datei | Push |
| --- | --- | --- |
| Standard (empfohlen) | `WispDating-v0.9.0-play.apk` | Firebase/FCM |
| Google-frei (F-Droid-Stil) | `WispDating-v0.9.0-fdroid.apk` | optional via UnifiedPush |

Beide finden sich unter [Releases](https://github.com/Toterboy/Wisp-Datingapp/releases) (Build-Artefakte liegen lokal unter `releases/v0.9.0/`; dort zusätzlich pro-CPU-APKs (`-play-arm64`/`-play-armv7`, ~55 MB) und Admin-Builds im Unterordner `admin/`, die nicht für die Verteilung bestimmt sind). Hinweis: Beide Varianten nutzen dieselbe App-ID und können nicht parallel installiert werden.

## Unterstützte Versionen

| Version | Status |
| --- | --- |
| v0.9.0 und höher (Build 28+) | **Unterstützt** – Bug-Reports willkommen, Security-Fixes |
| unter v0.9.0 (Build < 28) | **End of Support** (seit 24.09.2026) – keine Fixes mehr, bitte aktualisieren |

Ältere Builds werden über das serverseitige Mindest-Build-Gate
(`app_config.min_app_version_build`, Migration 034/076) markiert: Liegt der
installierte Build darunter, zeigt die App beim Start einen Update-Hinweis.
Details: [SUPPORT.md](SUPPORT.md).

---

## Kernfunktionen

### Registrierung & Einrichtung

- **Registrierung** mit Name, E-Mail (Domain-Validierung), Passwort, Geburtsdatum (Tag/Monat/Jahr), Geschlecht
- **Email-Bestätigung** mit automatischem Auto-Login nach Bestätigung; Hinweis-Kasten, falls DNS-Filter/VPNs den Bestätigungslink blockieren
- **Passwort-Reset** per Recovery-Link (Deep Link zurück in die App)
- **Einmalige Standort-Abfrage** zum Finden anderer Nutzer in der Umgebung – die darauf basierende Fake-Account-Erkennung ist **teilweise umgesetzt** (siehe „Hinweis zum Entwicklungsstand")
- **Passkey einrichten** (überspringbarer Schritt; WebAuthn, Anmeldung ohne E-Mail/Passwort möglich)
- **Persönlichkeitstest** (MBTI-Style, z. B. ENTP, INFJ)
- **Gewohnheiten** (Rauchen, Alkohol, Drogen) als eigener Einrichtungsschritt
- **Settings-/Privacy-Auswahl** nach der Registrierung – inklusive **Erscheinungsbild**: 6 Farbwelten (Classic WispDating, Ozean, Wald, Sonnenuntergang, Lavendel, Schiefer), jederzeit änderbar
- **Willkommens-Screen** beim allerersten App-Start

### Entdecken

- **Find your Match** – Blind-Matching „Persönlichkeit zuerst": Fotos sind erst nach einem Funke sichtbar (Blind Mode ist standardmäßig aktiv). Beim ersten Öffnen verlangt die App eine eigene Vorstellung (Text UND Audio sind Pflicht). Der gewichtete Matching-Score berücksichtigt Entfernung (40 %), gemeinsame Interessen (30 %) und Musik-Geschmack (30 %) und wird transparent als „Match: X %" angezeigt; strikte Geschlechts- und Altersfilter, optionaler Habit-Dealbreaker (Konsum maximal auf eigenem Niveau).
- **Zufallschat** – automatische Zuordnung zu einem Peer-to-Peer-Textchat basierend auf Alter-/Distanz-Einstellungen
- **QR Code** – eigenes Profil als QR-Code teilen, fremde Codes scannen oder manuell eingeben; der angezeigte 8-stellige Code ist serverseitig auflösbar (manuelle Eingabe findet den echten Nutzer)
- **Dating Hour (Event-Modus)** – jeden Samstag 20:00–21:00 Uhr deutscher Zeit (Sommer-/Winterzeit automatisch berücksichtigt):
  - Beitritt jederzeit möglich (serverzeitsynchron, Manipulation der Geräteuhr wird erkannt); Aktualisieren ist rein lesend, Beitritt NUR über „Ich bin dabei" mit Bestätigungsdialog
  - Erst ab 20 angemeldeten Personen – darunter fällt das Event aus (Schutz vor Fake-Account-Runden); der Fortschritt („X von 20") wird live im Event-Screen angezeigt; nur Konten ab 24 Stunden Alter zählen
  - Keine Wiederholungen: Das Matching bevorzugt Personen, mit denen es noch nie eine Session gab
  - Zwei zufällig zugeordnete Personen chatten direkt E2E-verschlüsselt (ohne Profilansicht); Hinweis-Banner bei >= 10 Jahren Altersdifferenz
  - Nach 5 Minuten: beide können einen Funke „Annehmen" oder „Ablehnen"
  - Funke nur, wenn BEIDE annehmen; freundlich formulierte Ablehnungs-Nachricht bei Absage
  - Individuelle Präferenzen (Alter, Geschlecht, besondere Eigenschaft) vor Event-Start einstellbar (serverseitig gespeichert, bleiben über Events und Neuinstallationen erhalten)

### Quiz „Wie gut kennst du dein Gegenüber?"

- Bei über Find your Match entstandenen Funken sind Chat, Bilder, Sprachnachrichten und Anrufe erst nach bestandenem Quiz freigeschaltet (serverseitig erzwungen)
- Drei Stufen: unscharf/schwarzweiß → scharf/schwarzweiß → farbig (final); Foto-Freischaltung wird serverseitig geprüft
- Beide Partner müssen dieselbe Frage richtig beantworten; Cooldown nach Fehlversuch (standardmäßig 5 Minuten)

### Chat & Kommunikation

- **Ende-zu-Ende-Verschlüsselung** aller Chat-Nachrichten via Signal Protocol (PreKeys, Sessions)
- **Peer-to-Peer-Verbindung** (WebRTC) mit Peer-Pinning im Signaling-Routing; ICE-Server werden dynamisch über die Supabase-Edge-Function `ice-config` geladen (EU-Fallback ohne Google)
- **Zustell-Reserve**: Kommt kein direkter Kanal zustande (Mobilfunk/CGNAT), läuft der Chat E2E-verschlüsselt über den Supabase-Relay weiter (Wake-up-Ping + Polling); P2P im selben WLAN nutzt klartext Host-Kandidaten
- **TURN aktivieren** (optional, Betreiber-Entscheidung wegen Kosten): Direktverbindungen über Netzgrenzen/CGNAT hinweg brauchen einen TURN-Relay. Der Code ist VORBEREITET - die `ice-config` Edge Function generiert kurzlebige TURN-REST-Credentials, sobald zwei Function-Secrets gesetzt sind (kein Code-Ändern nötig):
  1. Eigener coturn-Server (z. B. 1-vCPU-VPS, `use-auth-secret`) oder TURN-Hoster.
  2. Secrets setzen: `TURN_URL` = `turn:<host>:3478?transport=udp` (+ optional `TURN_SECRET`, `TURN_TTL`).
      - Supabase Dashboard → Functions → Secrets, oder lokal: `supabase secrets set TURN_URL=... TURN_SECRET=...`
  3. Fertig: Clients ziehen die Config automatisch beim nächsten Verbindungsaufbau (Cache-TTL beachten).
- **Spice Questions (Eisbrecher-Fragen)** – im Chat: Fragen beantworten (max. 200 Zeichen); die Antwort des Gegenübers wird erst sichtbar, wenn beide geantwortet haben
- Text-, Bild- und Sprachnachrichten
- Audio-Anrufe innerhalb der App
- Navigation zum Profil durch Klick auf Name/Profilbild
- „Nutzer melden"-Funktion (die letzten 3 Nachrichten inkl. Medien werden – explizit kenntlich gemacht – zur Prüfung übermittelt) und „Funke beenden"-Button (mit Sicherheitsabfrage)

### Aktuelles & Interessen

- Übersicht über neue Nachrichten, neue Likes und neue Funken
- **Interessen-Tab** mit getrennten Bereichen: vergebene Likes (zurückziehbar), erhaltene Likes (mit Vorstellung anhören; Funke bestätigen oder ablehnen) und Funken (mit Quiz-Hinweis)
- Zugriff auf Einstellungen über Zahnrad-Icon; zentraler „Entdecken"-Button

### Mood

- Stimmung wählen und teilen – erscheint im eigenen Profil und in Profilansichten anderer Nutzer

### Profil

- Profilbild mit **lokalem NSFW-Check vor dem Upload**: Das Bild wird
  on-device geprüft und verlässt bei Nichtbestehen das Gerät nicht
  (wahlweise „Anderes Bild wählen" oder „Einspruch einlegen" für das
  Team-Review); der Upload erfolgt erst mit dem Speichern, Abbrechen
  verwirft
- **Verschlüsselte Profilbilder**: Avatare werden clientseitig per
  AES-256-GCM verschlüsselt und erst beim Download lokal entschlüsselt –
  der Server sieht nie das Klartextbild
- **Musik-Geschmack**: Genres, die man mag – und freiwillig solche, die
  man explizit nicht mag; fließt in den Verbindungs-Score ein und ist in
  Profilen sichtbar (gemeinsame Genres werden hervorgehoben)
- Profil-Vorschau-Funktion (Ansicht wie andere Nutzer das Profil sehen)
- Vorstellung-Vorschau (eigene Text-/Audio-Vorstellung abspielbar)
- Gewohnheiten (Rauchen, Alkohol, Drogen) – ausschließlich in „Profil bearbeiten" änderbar
- Land als Pflichtfeld (Bundesland nur für Deutschland)
- Persönlichkeitstest hier wiederholbar
- Eigenes Geschlecht im Profil bearbeiten

### Einstellungen & Datenschutz

- Blind Mode (Fotos erst nach Funke), Foto-Freigabe nach Funke, Dark Mode, Altersbereich, Entfernung (km/Bundesland/ganz Deutschland), Benachrichtigungen (Master- plus Einzel-Schalter)
- **Profil-Sichtbarkeit als eine Steuerung**: Jeder / Nur Funken / Unsichtbar (Pausiert) – „Unsichtbar" ist der Pausenmodus (mit Bestätigungsdialog): unsichtbar in Entdecken und Find your Match, bestehende Funken und Chats bleiben
- **Verschlüsselter Chat-Verlauf**: drei Modi – Aus / 200 Nachrichten / kompletter Verlauf (Standard) – AES-256-verschlüsselt lokal (SecureHive, Key im Keystore)
- **Konto-Datenhalt**: Name, Bio, Profilbild, Suchradius, Altersspanne, „Ich suche", Bundesland, Ort, Farbwelt, UI-Schalter und die Dating-Hour-Einleitung werden serverseitig gespeichert und nach Neuinstallation/Login automatisch wiederhergestellt – die Sync-Schicht ist migrations-robust (eine fehlende Spalte kann niemals den ganzen Restore auslöschen)
- **Bild-Blur im Chat**: eingehende Bilder standardmäßig verpixelt, Freischalten nur nach Bestätigung; Bilder direkt meldbar
- **E2E-Identität sichern/wiederherstellen**: passwortverschlüsseltes Backup der Signal-Identität für den Gerätewechsel
- **Push ohne Google (UnifiedPush)**: optionale Alternative zu Firebase (benötigt eine Distributor-App wie ntfy)
- **Safety Center**: Hilfe bei Belästigung/Stalking, In-App-Maßnahmen erklärt, eigene Meldungen mit Status, Blockierliste mit Entblocken
- **Zwei-Faktor-Authentisierung (TOTP)** – QR-Code scannen oder Schlüssel manuell eintragen, einmalige Bestätigung per Code
- **Passkeys**: erstellen für passwortlose Anmeldung (mit 2FA-Step-up bei aktiver 2FA) **und verwalten** – alle registrierten Passkeys einsehen (Name, erstellt, zuletzt genutzt), umbenennen und löschen (z. B. Alt-Einträge nach Gerätewechsel)
- **Angemeldete Geräte**: Übersicht aller Geräte, auf denen das Konto eingeloggt ist (echtes Gerätemodell wie „Samsung SM-S921B", App-Version, letzte Aktivität) – mit „Überall abmelden (außer diesem Gerät)" per Tastendruck
- **Account löschen** – löscht den Account serverseitig UND alle lokalen Daten vollständig (DSGVO)
- **Privacy-Screen**: echte JSON-Exportfunktion (Profil, Einstellungen, Präferenzen, Mood) zum Teilen/Speichern, Daten-Import (JSON wieder einspielbar) sowie Auflistung der Auftragsverarbeiter (Supabase, Google/Firebase, Hugging Face, Apple)
- **Zweisprachig (DE/EN)**: Die App ist komplett zweisprachig – inklusive Farbschemata, Stimmungs-Chips und Entdecken-Modi; auf Deutsch heißt es konsequent „Funke(n)", auf Englisch „Spark(s)"
- **Mindestversions-Gate**: Clients unterhalb der serverseitigen Mindestversion zeigen beim Start einen Update-Screen (mit Rückfallebene „Trotzdem fortfahren")
- **Crash-Journal**: Der letzte Absturz wird lokal gespeichert; beim nächsten Start fragt die App, ob ein Report über den Bug-Report-Kanal gesendet werden soll (nichts verlässt das Gerät ohne Bestätigung)
- **Bug Report**: Beschreibung (max. 5000 Zeichen) plus bis zu 5 Screenshots/Bilder, Versand per Email
- Anzeige der App-Version unten (Login/Registrierung und Einstellungen)

---

## Sicherheitskonzept

- **Ende-zu-Ende-Verschlüsselung** (Signal Protocol) + **Peer-to-Peer** (WebRTC) – Nachrichten liegen nicht im Klartext auf Servern
- **Peer-Pinning** im Signaling-Routing: Nachrichten fremder Absender werden verworfen
- **Cert Pinning** für Supabase- und Hugging-Face-Endpunkte (per-Host-Map, unbekannte Hosts fail-open mit Warnung); auch Signaling-/ICE-Aufrufe nutzen den gepinnten Client
- **PreKey-Bundles** sind nur mit gültigem Nutzer-JWT abrufbar (keine User-Enumeration per Anon-Key)
- **Push-Benachrichtigungen** transportieren nur Metadaten (nie Inhalte), werden serverseitig gegen Benachrichtigungs-Schalter geprüft und nur an Nutzer mit realer Beziehung zugestellt (Funke oder eigener Like)
- **Serverseitige Freigabe-Prüfungen**: Foto-Freischaltung erst bei Quiz-Stufe 2, Partner-Profil-Freischaltung mit expliziter Feld-Whitelist (exakte Koordinaten und FCM-Tokens verlassen den Server nie)
- **Datenschutz bei Standortdaten**: Distanzangaben sind auf 5-km-Schritte gerundet, Suchradius maximal 200 km; exakte Koordinaten werden nie an andere Nutzer übertragen
- **Rate-Limits** serverseitig u. a. für Likes, Push-Versand, QR-Code-Abfragen, Invite-Code-Tests und Entsperrungsanträge (persistente DB-Buckets)
- **Bot-Schutz**: Cloudflare Turnstile Captcha vor sensiblen Aktionen
- **Account-Sperrung**: gebannte E-Mail-Adressen können sich weder registrieren noch einloggen; Entsperrungsantrag mit Begründung möglich
- **Lokale Speicherung**: Tokens und profilbezogene PII ausschließlich im Keystore/Keychain (`flutter_secure_storage`), Hive-Daten AES-verschlüsselt, Cloud-Backups deaktiviert (`allowBackup=false`)
- **Härtete SQL-Schicht**: RLS auf allen Tabellen, SECURITY DEFINER-Funktionen mit gehärtetem `search_path`, Blockier-Prüfung bei Likes, Rate-limited Existenzabfragen
- **Release-Signierung**: Build bricht fehl, wenn kein Keystore konfiguriert ist (kein stiller Debug-Fallback)
- **Bild-Schutz**: eingehende Chat-Bilder standardmäßig verpixelt, Freischaltung nur nach Bestätigung. **Meldung mit KI-Vorprüfung:** Chat-Bilder werden nie automatisch gescannt - erst eine Meldung des Empfängers prüft exakt dieses eine Bild per NSFW-KI (Edge Function `report-image`). Der Meldende sieht das KI-Ergebnis sofort; bei Bestätigung (oder nach Eskalation durch den Meldenden) erhalten Bild, Report und KI-Ergebnis das Team automatisch per E-Mail
- **NSFW on-device für Profilbilder**: Der Upload-Check läuft komplett lokal (gebündeltes ONNX-Modell via onnxruntime, ~12 MB) – das Bild verlässt bei Nichtbestehen das Gerät nicht; bestandene Bilder werden serverseitig nie gescannt. Verifiziert durch einen permanenten Test mit echter Modell-Inferenz
- **Verschlüsselte Profilbilder**: Avatare werden clientseitig per AES-256-GCM verschlüsselt (Zufalls-Schlüssel pro Bild, im photos-Eintrag mitgeführt) – bei einem Bucket-Leak sind die Bilder unlesbar; Anzeige nur lokal entschlüsselt
- **Verschlüsseltes Key-Backup**: die Signal-Identität wird passwortbasiert gesichert (PBKDF2 + AES-256-GCM, frische IVs) – der Server sieht das Backup nie unverschlüsselt
- **Pseudonymisierung**: Reporter-IDs werden gehasht (SHA-256), kein PII in lokalen Hive-Keys
- **Serverzeit** als Single Source of Truth für die Dating Hour (Anti-Cheat gegen Manipulation der Geräteuhr); Warn-Banner im Event-Screen bei unverifizierter Serverzeit
- **Altersschutz-System:**
  - Ab 20 Jahren keine Sichtbarkeit von 16-/17-Jährigen mehr
  - Minderjährige (16–17) können ihren Filter nur bis max. 20 Jahre einstellen
  - Profilfotos von 16–17-Jährigen nur für Gleichaltrige sichtbar
  - Profilfotos von 18–19-Jährigen nur nach Funke sichtbar (nicht deaktivierbar)
  - Automatische Freischaltung aller Funktionen mit Erreichen des 20. Lebensjahres
- **Foto-Moderation**: NSFW-Prüfung über ein Hugging-Face-Inference-Modell (EU-Router, cert-gepinnt) – aktuell **standardmäßig deaktiviert** (Aktivierung per Build-Flag, siehe „Hinweis zum Entwicklungsstand"); Moderationsergebnisse landen in einer Admin-Warteschlange
- **Session-Restore** synchron (kein Netzwerk beim App-Start), serverseitige Validierung im Hintergrund
- **Passkey-/WebAuthn-Konfiguration**: Die GoTrue-Ursprungs-Liste (`Relying Party Origins`) muss den **SHA-256**-Signatur-Hash der installierten APK enthalten (`android:apk-key-hash:…`, 43 Base64URL-Zeichen) – SHA-1-Fingerprints matchen nie. Exakte Werte, Diagnose und Symptom-Tabelle: [docs/PASSKEYS_SERVER_SETUP.md](docs/PASSKEYS_SERVER_SETUP.md)
- **Geräte-Liste** (`auth_devices`, Migration 071): Jede Zeile wurde vom Gerät selbst angelegt; RLS erlaubt ausschließlich Zugriff auf die eigenen Zeilen – nobody kann fremde Geräte sehen; seit 078 mit echtem Gerätemodell (Hersteller + Kennung, client-gesetzt)
- **Migrations-robuste Sync-Schicht**: Ladevorgänge fallen stufenweise auf ältere Spaltensätze zurück, Schreibvorgänge entfernen bei PostgREST-„missing column"-Fehlern automatisch die fehlende Spalte und schreiben den Rest – eine nicht eingespielte Migration kann niemals Name, Bio, Theme oder Suchradius gemeinsam auslöschen

---

## Tech-Stack

| Bereich              | Technologie                                        |
| -------------------- | -------------------------------------------------- |
| Framework            | Flutter (Android, iOS, Web)                        |
| State Management     | Riverpod                                           |
| Navigation           | go_router                                          |
| Design               | Material 3                                         |
| Backend              | Supabase (Auth, Postgres, Storage, Edge Functions, Realtime) |
| Verschlüsselung      | Signal Protocol (`libsignal_protocol_dart`)        |
| Peer-to-Peer         | WebRTC (`flutter_webrtc`)                          |
| Authentisierung      | Passkeys (`passkeys`), TOTP-Zweitfaktor (Supabase MFA), Firebase Cloud Messaging (nur `play`-Variante) |
| Push (Google-frei)   | UnifiedPush (`unifiedpush`, F-Droid-Variante)      |
| Moderation           | NSFW-Klassifikator via Hugging-Face-Inference (nur melde-basiert, Edge Function) + **on-device ONNX-Modell** (`onnxruntime`) für Profilbilder |
| Medien               | `image_picker`, `image_cropper`, `camera`, `video_player`, `record`, `just_audio` |
| Scannen/QR           | `mobile_scanner`, `qr_flutter`                     |
| Teilen               | `share_plus`                                       |
| Geräteinfos          | `device_info_plus` (Gerätemodell für „Angemeldete Geräte") |
| Krypto               | `pointycastle` (AES-256-GCM für Avatare/Backups), `libsignal_protocol_dart` |
| Lokale Speicherung   | Hive (verschlüsselt), flutter_secure_storage       |
| Standort             | `geolocator`, `geocoding`                          |
| Benachrichtigungen   | `flutter_local_notifications`                      |

---

## Server-Setup (Supabase)

Nach einem Update müssen vor dem Rollout die Datenbank-Migrationen
(`supabase/migrations/`, per SQL-Editor oder `supabase db push`) und die
Edge Functions (`supabase/functions/`) auf den Server. Stand v0.8.0:

- **Migrationen 064–073** (v0.7.x): Bild-Reports, `onboarding_done`,
  Präferenz-Sync (066), Dating-Hour-Zeiten/-Zähler (067/068/070),
  Reporter-Pseudonymisierung (069), Geräte-Liste + Theme-Sync (071),
  `public_profiles`-Konsolidierung (072), Geräte-Härtung (073)
- **Migrationen für v0.8.0:**
  - **074** – Musik-Geschmack, Match-Status, Verbindungs-Score, `ui_prefs`-Sync
  - **075** – Quiz-Fragen-Pool (60 Fragen)
  - **076** – Pausenmodus (`paused`), Habit-Dealbreaker,
    Mindestversions-Gate (`app_config`), Meldungs-Feedback, Blockierliste
  - **077** – `profiles.photos` + öffentlicher View (Profilbilder;
    *photos steht bewusst am Ende der View-Spaltenliste – Postgres
    erlaubt bei `CREATE OR REPLACE VIEW` nur anhängende Spalten*)
  - **078** – `auth_devices.device_model` (echtes Gerätemodell)
- **Migrationen für v0.9.0:**
  - **079–080** – Foto-Einsprüche, `public_profiles` als RPCs
    (`get_public_profile(s)`)
  - **081–084** – Transit Spark (Signale, Tags v2, Soft-Ping)
  - **085** – Suchradius-Modus (`distance_filter_mode`)
  - **086–087, 089** – Personalisiertes Kennenlern-Quiz ohne LLM,
    Trivia-Pool als deprecated markiert
  - **088** – Mehrere Profilbilder, Freunde-Filter
  - **090** – Funke-Kühlen/Re-Funke/Beenden/Ausblenden als BIGINT
    (UUID-Varianten droppen)
  - **091** – Transit-Selbstbeschreibung (`self_note`)
  - **092** – Lieblingssong/Band (`favorite_song`)
  - **093** – Nachrichten-Relay (E2E-Ciphertext-Fallback bei
    fehlendem P2P-Kanal)
  - **094** – Dating-Hour-Mindestzahl konfigurierbar
    (`app_config`, Standard 20, Admin-RPCs)
- **Lokale Geheimnisse (nicht im Repo):** `android/key.properties`
  (Signierung), `.env` (Supabase), `android/app/google-services.json`
  (Firebase, nur Play-Variante) – je `.example`-Datei als Vorlage
  (`google-services.json.example`).
- **Diagnose:** `supabase/check_columns.sql` im SQL Editor ausführen –
  zeigt pro Spalte TRUE/FALSE, welche Migrationen fehlen (wichtig bei
  Symptomen wie „Suchradius/Profilbild wird nicht gespeichert")
- **Edge Functions:** `report-image` (Bild-Meldung + KI + Nachweis-Pflicht),
  `admin-ban` (Nutzer sperren/entsperren, paginierte Suche),
  `notify-user` (rundes Statusleisten-Icon), `server-time`
- **Function-Secrets** (Dashboard → Edge Functions → Secrets):
  - `BREVO_API_KEY` – Mails (Bild-Meldungen, Bug-Reports, Konto-Sperren)
  - `MODERATION_EMAIL` – Empfänger der Bild-Meldungs-Mails
  - `ADMIN_UUID` – Admin-ID für `admin-ban` (identisch zum Build-Flag)
  - `HF_API_TOKEN` – optional, aktiviert die NSFW-KI-Vorprüfung
  - `FIREBASE_SERVICE_ACCOUNT_JSON` – FCM-Versand (bereits vorhanden)
- **Passkeys/WebAuthn** (Dashboard → Authentication → Passkeys): RP-ID
  `auth.wispdating.de`; Origins MÜSSEN den **SHA-256**-Signatur-Hash der
  installierten APK enthalten. Falsche (SHA-1-)Einträge sind die häufigste
  Ursache für „Der Server konnte den Passkey nicht bestätigen" – exakte
  Werte: [docs/PASSKEYS_SERVER_SETUP.md](docs/PASSKEYS_SERVER_SETUP.md)

---

## Kommende Funktionen

Geplant und teilweise bereits in Entwicklung (Details:
[ROADMAP.md](ROADMAP.md)):

**Ab v0.8.0 – Geschmack & Matching:**
- Musik-Geschmack: Genres (inkl. „Instrumental"), die man mag – und
  freiwillig solche, die man gar nicht mag; fließt ins Matching ein
- Quiz-Fragen-Pool vervollständigt; Verbindungs-Score transparent im Profil
- Inaktive Funken als eigene Rubrik (ohne Streak-Druck), Chats mehrfach
  auswählbar und löschbar, „Re-Funke" ohne Frist
- Dating Hour mit thematischen Runden und Frage-Karten für Schüchterne
- NSFW-Prüfung on-device (Bild verlässt das Gerät nicht) und beim
  Profilbild-Upload; App komplett zweisprachig (DE/EN)

**Ab v0.9.0 – Nahbereichs-Funke („Transit Spark"):**
- Wie es funktioniert: Man lächelt sich im Zug, Café oder auf einer Messe
  an, traut sich aber nicht anzusprechen. Die Geräte registrieren in der
  Nähe (3–10 m) anonyme, ephemere Begegnungs-Tokens (BLE, 45 Min. Cache).
  Tippen später beide auf „Blicke getauscht" und wählen 1–3 Merkmale
  (z. B. schwarzer Hoodie + Messe-Lanyard), matcht Supabase die Tokens –
  auch wenn die Personen inzwischen weit voneinander entfernt sind.
  Ein Funke entsteht nur bei beidseitigem Signal. Privat: keine Bilder im
  Umlauf, Tokens rotieren und verfallen automatisch.

**Ab v0.10.0 – Sanctuary & lokaler KI-Reflexions-Chat:**
- Ein vollständig offlinefähiger, geschützter Raum zur Selbstreflexion –
  betrieben durch rein lokale On-Device-Sprachmodelle (llama.cpp/LiteRT,
  quantisierte GGUF-Downloads von Hugging Face mit Fortschritt/Resume)
- Stufenweise Modellauswahl (kompakt/akkusparend bis tiefgründig),
  Vision-Badge für multimodale Modelle, eigener Modell-Import mit
  automatischer Erkennung kuratierter Modelle (System-Prompt wird dann
  automatisch angepasst)
- Sicherheit: Pflicht-Disclaimer, „Modellqualität beanstanden",
  lokale Krisen-Erkennung mit Notfallkontakten, Chats nur im RAM oder
  AES-verschlüsselt lokal

**Ab v0.11.0 – Web-Bridge, Transit-Reachability & Zero-Install Gäste:**
- Menschen OHNE App erreichen: OS-Share (Quick Share/AirDrop),
  Hotspot-SSID-Beacon mit Offline-Captive-Portal, NFC, QR in Vollbild
- Flutter-Web-Gäste (trackerfrei auf Codeberg Pages, Berlin) chatten E2E
  im Browser – ohne Download, Registrierung, Telefon oder E-Mail;
  Sitzungen zerstören sich nach 24–48 h selbst
- Same-Train-Matching über Zug-WLAN-Erkennung (BSSID) und
  Geschwindigkeits-/Vektor-Abgleich; Live-Strecken-Board auf
  `wisp.app/live` mit Waggon-Angabe und Merkmalen

---

## Hinweis zum Entwicklungsstand

Diese App befindet sich in aktiver Entwicklung (aktuelle Version 0.8.0). Folgende Bereiche sind noch nicht final:

- **Automatischer Gesichtsabgleich** (Profilbild vs. Verifizierungs-Video) → z. B. selbstgehostete Open-Source-Modelle wie DeepStack oder Face Recognition (selbst gehostet, datenschutzfreundlich, EU-fähig)
- **NSFW-Bild-Moderation** – Profilbilder werden seit 0.8.0 **on-device** geprüft (gebündeltes ONNX-Modell; das Bild verlässt bei Nichtbestehen das Gerät nicht, Einspruch mit Team-Review möglich; die Schwellwert-Praxis braucht noch Abgleich mit echten Fällen). Chat-Bilder werden weiterhin nie beim Senden gescannt (E2E), sondern erst bei einer Meldung durch den Empfänger per NSFW-KI geprüft (Edge Function `report-image`). **Noch offen:** automatische Account-Sperren bei Wiederholungsverstößen (derzeit manuell).
- **i18n-Rest**: Die App ist zweisprachig; einzelne ältere/harte UI-Strings (u. a. einige Altersfilter- und Einrichtungstexte) stehen noch nicht im L10n-Katalog
- **Applogo & Branding** – *in Arbeit*: Alle Assets stammen aus einer einzigen Quelldatei (`wispdating_icon_base.png`); Feinschliff (Größen, Masken, Farbwelt-Abstimmung) folgt.
- **Fake-Account-Erkennung per Standort** – *teilweise umgesetzt*: Vorhanden sind Datenmodell und Manipulationsschutz (Verifizierungs-Felder sind clientseitig nicht schreibbar), Edge Functions mit Plausibilitätsprüfung (unrealistische Positionswechsel >15 km bzw. >300 km/h werden als verdächtig markiert) und eine lokale verschlüsselte Speicherung. **Noch offen:** der serverseitige Abgleich, ob an derselben Position bereits andere Accounts existieren, die Validierung von GPS gegen das angegebene Bundesland/Land, eine Admin-Ansicht zur Prüfung markierter Accounts sowie Konsequenzen (z. B. Einschränkungen bei Verdacht).

---

## Lizenz

Dieses Projekt steht unter der **GNU Affero General Public License v3.0 (AGPLv3)**.

Das bedeutet insbesondere:

- Der Code darf verwendet, verändert und weiterverbreitet werden.
- Wird die Software (auch als Server-/Cloud-Dienst) genutzt oder verändert, muss der Quellcode ebenfalls unter der AGPLv3 offengelegt werden.
- Eine kommerzielle Nutzung als geschlossenes, proprietäres Produkt ist damit ausgeschlossen.

---

## Kontakt

Bei Fragen oder Vorschlägen gerne ein Issue im Repository erstellen.
