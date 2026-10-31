# Thestia

![CI](https://github.com/Toterboy/Thestia/actions/workflows/ci.yml/badge.svg)
[![Lizenz: AGPL v3](https://img.shields.io/badge/Lizenz-AGPL_v3-blue.svg)](LICENSE)

Eine moderne, datenschutzfreundliche Dating-App mit Fokus auf **Persönlichkeit
statt Aussehen**. Thestia setzt auf Blind-Matching („Persönlichkeit zuerst"),
Ende-zu-Ende-Verschlüsselung und Peer-to-Peer-Kommunikation, um
authentischere Verbindungen zu ermöglichen. Entsteht eine Verbindung, heißt das
bei uns **„Funke"**.

Das Projekt ist vollständig kostenlos nutzbar und soll eine echte Alternative zu
Tinder & Co. darstellen. Es befindet sich in aktiver Entwicklung und ist noch
nicht vollständig funktional. Beiträge und Feedback sind willkommen.

> **Umbenannt:** Aus **WispDating** wurde **Thestia** (ab v0.9.1, Build 29).
> Neuer Name, neues Logo, neue App-ID (`com.thestia.app`) – **bitte neu
> installieren**, die alte App aktualisiert sich nicht von selbst. Konto und
> Daten bleiben erhalten (Login genügt), nur Passkeys müssen einmal neu
> registriert werden.
>
> **Aktuelle Version: v0.10.0** (Build 31). Die Download-Version v0.10.0 ist
> **noch nicht veröffentlicht** – sie geht in den Store, sobald die offenen
> Punkte geschlossen sind. Bis dahin gilt v0.9.2 als die unterstützte Fassung.

**Dokumentation:** [Beitragen](CONTRIBUTING.md) · [Verhaltenskodex](CODE_OF_CONDUCT.md) ·
[Sicherheitslücken melden](SECURITY.md) · [Support](SUPPORT.md) ·
[Roadmap](ROADMAP.md) · [Changelog](CHANGELOG.md) ·
[Datenschutzerklärung](docs/DATENSCHUTZ.md) ·
[Angriffsbild (Threat Model)](passkey-assets/threat-model.md)

---

## Warum Thestia – und nicht Tinder, Bumble & Co.?

Weil moderne Dating-Apps genau die Probleme haben, die Thestia gezielt löst –
ohne Abo-Falle, ohne Aufmerksamkeits-Casino, ohne Daten-Hammer:

- **Persönlichkeit vor Aussehen.** Bei uns heißt der erste Schritt „Find your
  Match": Du hörst (oder liest) eine Vorstellung, bevor du ein Foto siehst –
  **Blind Mode ist Standard**, nicht Premium.
- **Ein Funke statt endlosem Swiping.** Verbindungen heißen bei uns **„Funken"**
  – und sie entstehen nur, wenn beide etwas investieren: Quiz-Fragen statt
  oberflächlicher Matches, ein Verbindungs-Score aus Entfernung, Interessen und
  **Musik-Geschmack** statt Dopamin-Feed.
- **Echt verschlüsselt – Ende-zu-Ende.** Signal-Protokoll und Peer-to-Peer
  (WebRTC) sind bei uns der Kern, kein Marketing-Versprechen. Selbst
  **Profilbilder liegen verschlüsselt** (AES-256-GCM) auf dem Server.
- **On-Device-KI statt Auslagern.** Die NSFW-Prüfung deines Profilbilds läuft
  **komplett auf deinem Handy** – das Bild verlässt bei Nichtbestehen das
  Gerät nicht.
- **Präsenz-frei.** Kein „online"-Badge, kein „schreibt gerade…", keine
  Lesebestätigungen. Dating soll zurück ins echte Leben führen – der
  App-Status ist kein Beziehungs-Tracker.
- **Inaktivität ist okay.** Abgekühlte Funken verfallen nicht nach 24 Stunden
  in den Ordnner des Vergessens: Inaktive Funken ruhen unter „Erschlossene
  Funken" und sind per Re-Funke jederzeit ohne Frist wieder belebbar.
- **Dating Hour: das echte Speed-Dating-Ereignis.** Samstags 20–21 Uhr:
  5-Minuten-Chats mit Entscheidungsphase, serverzeitsynchron und
  Anti-Cheat-gesichert – als Event, nicht als zusätzliches Abo-Feature.
- **Transit Spark: Begegnungen, ohne anzusprechen.** Im Zug, im Café oder auf
  einer Messe registrieren sich Geräte in der Nähe mit anonymen, flüchtigen
  Tokens. Erst wenn beide „Blicke getauscht" antippen und Merkmale wählen
  (schwarzer Hoodie, Messe-Lanyard), entsteht ein Funke. Keine Bilder im
  Umlauf, die Tokens verfallen von selbst.
- **Kostenlos. Für immer.** Keine Abos, keine Premium-Stufen, keine
  In-App-Käufe, keine Werbetracker. Open Source (AGPLv3) und selbst hostbar –
  inklusive Google-freier F-Droid-Variante.

## Unsere Zusagen

- **Kostenlos. Für immer.** Keine Abos, keine Premium-Funktionen, keine
  In-App-Käufe.
- **Deine Daten werden niemals verkauft** oder für Werbung weitergegeben – es
  gibt schlicht kein Geschäftsmodell, das das bräuchte.
- **Präsenz-frei:** kein Online-Status, kein „schreibt gerade…", keine
  Lesebestätigungen. Dating soll zurück ins echte Leben.
- **Ehrliche Transparenz:** Der einzige externe Dienst, der theoretisch
  Verbindungs-Metadaten sehen könnte, ist Google Firebase (nur als
  Push-Transport, ohne Nachrichteninhalte – und nur in der Play-Variante; die
  F-Droid-Variante läuft komplett ohne Google via UnifiedPush). Alle Inhalte
  sind Ende-zu-Ende-verschlüsselt.

---

## Über die App

Thestia ist für Android konzipiert (iOS/Web/Desktop folgen) und basiert auf
Flutter, Riverpod (State Management) und go_router (Navigation) im
Material-3-Design. Backend ist Supabase (Auth, Postgres, Storage, Edge
Functions, Realtime); Chat-Nachrichten laufen Ende-zu-Ende-verschlüsselt über
das Signal Protocol, die Verbindung direkt Peer-to-Peer per WebRTC.

## Downloads

| Variante | Datei | Push |
| --- | --- | --- |
| Standard (empfohlen) | `Thestia-v0.9.2-play.apk` | Firebase/FCM |
| Google-frei (F-Droid-Stil) | `Thestia-v0.9.2-fdroid.apk` | optional via UnifiedPush |

Beide finden sich unter [Releases](https://github.com/Toterboy/Thestia/releases).
Hinweis: Beide Varianten nutzen dieselbe App-ID und können nicht parallel
installiert werden. Ältere Dateien (`WispDating-v0.9.0-*.apk`) gehören zur
Vorgänger-Version – bitte **Thestia neu installieren** (kein Update-Pfad, neue
App-ID).

**v0.10.0 (Build 31) ist in Vorbereitung.** Die veröffentlichte Fassung ist
weiterhin **v0.9.2** – v0.10.0 geht in den Store, sobald die offenen Punkte
geschlossen sind.

## Unterstützte Versionen

| Version | Status |
| --- | --- |
| unter v0.9.2 (Build < 30, inkl. aller WispDating-Builds) | **End of Support** – keine Fixes mehr, bitte Thestia neu installieren |
| v0.9.2 (Build 30) | **Unterstützt**, bis v0.10.0 veröffentlicht ist – Bug-Reports willkommen, Security-Fixes |
| v0.10.0 (Build 31) | **In Vorbereitung** |

Ältere Builds werden über das serverseitige Mindest-Build-Gate
(`app_config.min_app_version_build = 30`, Migration 132) markiert: Liegt der
installierte Build darunter, zeigt die App beim Start einen Update-Hinweis. Der
Support erst ab v0.9.2 ist eine Folge der Alterssperre für Transit Spark
(Migration 131) – ältere Builds können diese umgehen. Details: [SUPPORT.md](SUPPORT.md).

---

## Kernfunktionen

### Registrierung & Einrichtung

- **Registrierung** mit Name, E-Mail (Domain-Validierung), Passwort,
  Geburtsdatum (Tag/Monat/Jahr), Geschlecht
- **E-Mail-Bestätigung** mit automatischem Auto-Login nach Bestätigung;
  Hinweis-Kasten, falls DNS-Filter/VPNs den Bestätigungslink blockieren
- **Passwort-Reset** per Recovery-Link (Deep Link zurück in die App)
- **Sicherheits-Aufklärung vor dem Setup** – nach der E-Mail-Bestätigung: kurze
  Fragen zu Dating-Erfahrung und Gefahrenbewusstsein, bei Bedarf fünf wischbare
  Lernseiten (max. 5 Minuten, lokal fortsetzbar). Ausführlich:
  [Sicher daten](https://auth.thestia.de/dating-sicherheit)
- **Passkey einrichten** (überspringbarer Schritt; WebAuthn, Anmeldung ohne
  E-Mail/Passwort möglich)
- **Persönlichkeitstest** (MBTI-Style, z. B. ENTP, INFJ)
- **Gewohnheiten** (Rauchen, Alkohol, Drogen) als eigener Einrichtungsschritt
- **Settings-/Privacy-Auswahl** nach der Registrierung – inklusive
  **Erscheinungsbild**: 6 Farbwelten (Classic Thestia, Ozean, Wald,
  Sonnenuntergang, Lavendel, Schiefer), jederzeit änderbar
- **Willkommens-Screen** beim allerersten App-Start

### Entdecken

- **Find your Match** – Blind-Matching „Persönlichkeit zuerst": Fotos sind
  erst nach einem Funke sichtbar (Blind Mode ist standardmäßig aktiv). Beim
  ersten Öffnen verlangt die App eine eigene Vorstellung (Text UND Audio sind
  Pflicht). Der gewichtete Matching-Score berücksichtigt Entfernung (40 %),
  gemeinsame Interessen (30 %) und Musik-Geschmack (30 %) und wird transparent
  als „Match: X %" angezeigt; strikte Geschlechts- und Altersfilter,
  optionaler Habit-Dealbreaker (Konsum maximal auf eigenem Niveau).
- **Zufallschat** – automatische Zuordnung zu einem Peer-to-Peer-Textchat
  basierend auf Alter-/Distanz-Einstellungen
- **Connect to others** – eigenes Profil als QR-Code teilen, fremde Codes
  scannen oder manuell eingeben. Zusätzlich lassen sich Telefonnummer und
  Handles (Signal, Threema; Instagram, Snapchat und Discord als „nicht
  empfohlen" gekennzeichnet, eigene Apps ergänzbar) freiwillig hinterlegen und
  per Share-Sheet oder Zwischenablage weitergeben. Diese Kontaktdaten bleiben
  verschlüsselt auf dem Gerät und werden **nie an den Server gesendet**.
- **Dating Hour (Event-Modus)** – jeden Samstag 20:00–21:00 Uhr deutscher Zeit
  (Sommer-/Winterzeit automatisch berücksichtigt):
  - Beitritt jederzeit möglich (serverzeitsynchron, Manipulation der
    Geräteuhr wird erkannt); Aktualisieren ist rein lesend, Beitritt NUR über
    „Ich bin dabei" mit Bestätigungsdialog
  - Erst ab 20 angemeldeten Personen – darunter fällt das Event aus (Schutz
    vor Fake-Account-Runden); nur Konten ab 24 Stunden Alter zählen
  - Keine Wiederholungen: Das Matching bevorzugt Personen, mit denen es noch
    nie eine Session gab
  - Zwei zufällig zugeordnete Personen chatten direkt E2E-verschlüsselt (ohne
    Profilansicht); Hinweis-Banner bei >= 10 Jahren Altersdifferenz
  - Nach 5 Minuten: beide können einen Funke „Annehmen" oder „Ablehnen"
  - Funke nur, wenn BEIDE annehmen; freundlich formulierte
    Ablehnungs-Nachricht bei Absage
  - Individuelle Präferenzen (Alter, Geschlecht, besondere Eigenschaft) vor
    Event-Start einstellbar (serverseitig gespeichert, bleiben über Events und
    Neuinstallationen erhalten)

### Quiz „Wie gut kennst du dein Gegenüber?"

- Bei über Find your Match entstandenen Funken sind Chat, Bilder,
  Sprachnachrichten und Anrufe erst nach bestandenem Quiz freigeschaltet
  (serverseitig erzwungen)
- Drei Stufen: unscharf/schwarzweiß → scharf/schwarzweiß → farbig (final);
  Foto-Freischaltung wird serverseitig geprüft
- Beide Partner müssen dieselbe Frage richtig beantworten; Cooldown nach
  Fehlversuch (standardmäßig 5 Minuten)

### Chat & Kommunikation

- **Ende-zu-Ende-Verschlüsselung** aller Chat-Nachrichten via Signal Protocol
  (PreKeys, Sessions)
- **Peer-to-Peer-Verbindung** (WebRTC) mit Peer-Pinning im Signaling-Routing;
  ICE-Server werden dynamisch über die Supabase-Edge-Function `ice-config`
  geladen (EU-Fallback ohne Google)
- **Zustell-Reserve**: Kommt kein direkter Kanal zustande (Mobilfunk/CGNAT),
  läuft der Chat E2E-verschlüsselt über das Supabase-Relay weiter (Wake-up-Ping
  + Polling); P2P im selben WLAN nutzt Klartext-Host-Kandidaten
- **Spice Questions (Eisbrecher-Fragen)** – im Chat: Fragen beantworten (max. 200
  Zeichen); die Antwort des Gegenübers wird erst sichtbar, wenn beide geantwortet
  haben
- Text-, Bild- und Sprachnachrichten
- Audio-Anrufe innerhalb der App
- Navigation zum Profil durch Klick auf Name/Profilbild
- „Nutzer melden"-Funktion (die letzten 3 Nachrichten inkl. Medien werden –
  explizit kenntlich gemacht – zur Prüfung übermittelt) und „Funke
  beenden"-Button (mit Sicherheitsabfrage)

### Aktuelles & Interessen

- Übersicht über neue Nachrichten, neue Likes und neue Funken
- **Interessen-Tab**: „Gesendet" und „Erhalten" sind zugeklappte Blasen, die
  nach unten aufklappen; darunter stehen immer die Funken (mit Quiz-Hinweis).
  Vergebene Likes sind zurückziehbar, erhaltene Likes lassen sich anhören und
  bestätigen oder ablehnen
- Zugriff auf Einstellungen über Zahnrad-Icon; zentraler „Entdecken"-Button

### Mood

- Stimmung wählen und teilen – erscheint im eigenen Profil und in Profilansichten
  anderer Nutzer

### Profil

- Profilbild mit **lokalem NSFW-Check vor dem Upload**: Das Bild wird
  on-device geprüft und verlässt bei Nichtbestehen das Gerät nicht (wahlweise
  „Anderes Bild wählen" oder „Einspruch einlegen" für das Team-Review); der
  Upload erfolgt erst mit dem Speichern, Abbrechen verwirft
- **Verschlüsselte Profilbilder**: Avatare werden clientseitig per AES-256-GCM
  verschlüsselt und erst beim Download lokal entschlüsselt – der Server sieht
  nie das Klartextbild
- **Musik-Geschmack**: Genres, die man mag – und freiwillig solche, die man
  explizit nicht mag; fließt in den Verbindungs-Score ein und ist in Profilen
  sichtbar (gemeinsame Genres werden hervorgehoben)
- **Geburtstags-Stil**: an deinem Geburtstag tönt die ganze Profilfläche in
  deinem gewählten Stil (sechs Stile, jederzeit änderbar) – Bild und alle
  Angaben bleiben mittig
- Profil-Vorschau-Funktion (Ansicht wie andere Nutzer das Profil sehen)
- Vorstellung-Vorschau (eigene Text-/Audio-Vorstellung abspielbar)
- Gewohnheiten (Rauchen, Alkohol, Drogen) – ausschließlich in „Profil
  bearbeiten" änderbar
- Land als Pflichtfeld (Bundesland nur für Deutschland)
- Persönlichkeitstest hier wiederholbar
- Eigenes Geschlecht im Profil bearbeiten

### Einstellungen & Datenschutz

- Blind Mode (Fotos erst nach Funke), Foto-Freigabe nach Funke, Dark Mode,
  Altersbereich, Entfernung (km/Bundesland/ganz Deutschland),
  Benachrichtigungen (Master- plus Einzel-Schalter)
- **Profil-Sichtbarkeit als eine Steuerung**: Jeder / Nur Funken /
  Unsichtbar (Pausiert) – „Unsichtbar" ist der Pausenmodus (mit
  Bestätigungsdialog): unsichtbar in Entdecken und Find your Match, bestehende
  Funken und Chats bleiben
- **Verschlüsselter Chat-Verlauf**: drei Modi – Aus / 200 Nachrichten /
  kompletter Verlauf (Standard) – AES-256-verschlüsselt lokal (SecureHive, Key
  im Keystore)
- **Konto-Datenhalt**: Name, Bio, Profilbild, Suchradius, Altersspanne, „Ich
  suche", Bundesland, Farbwelt, UI-Schalter und die Dating-Hour-Einleitung
  werden serverseitig gespeichert und nach Neuinstallation/Login automatisch
  wiederhergestellt – die Sync-Schicht ist migrations-robust (eine fehlende
  Spalte kann niemals den ganzen Restore auslösen)
- **Bild-Blur im Chat**: eingehende Bilder standardmäßig verpixelt, Freischalten
  nur nach Bestätigung; Bilder direkt meldbar
- **E2E-Identität sichern/wiederherstellen**: passwortverschlüsseltes Backup der
  Signal-Identität für den Gerätewechsel
- **Push ohne Google (UnifiedPush)**: optionale Alternative zu Firebase
  (benötigt eine Distributor-App wie ntfy)
- **Safety Center**: Hilfe bei Belästigung/Stalking, In-App-Maßnahmen erklärt,
  eigene Meldungen mit Status, Blockierliste mit Entblocken
- **Zwei-Faktor-Authentifizierung (TOTP)** – QR-Code scannen oder Schlüssel
  manuell eintragen, einmalige Bestätigung per Code
- **Passkeys**: erstellen für passwortlose Anmeldung (mit 2FA-Step-up bei
  aktiver 2FA) **und verwalten** – alle registrierten Passkeys einsehen (Name,
  erstellt, zuletzt genutzt), umbenennen und löschen (z. B. Alt-Einträge nach
  Gerätewechsel)
- **Angemeldete Geräte**: Übersicht aller Geräte, auf denen das Konto
  eingeloggt ist (echtes Gerätemodell wie „Samsung SM-S921B", App-Version,
  letzte Aktivität) – mit „Überall abmelden (außer diesem Gerät)" per Tastendruck
- **Account löschen** – löscht den Account serverseitig UND alle lokalen Daten
  vollständig (DSGVO)
- **Privacy-Screen**: echte JSON-Exportfunktion (Profil, Einstellungen,
  Präferenzen, Mood) zum Teilen/Speichern, Daten-Import (JSON wieder
  einspielbar) sowie Auflistung der Auftragsverarbeiter (Supabase,
  Google/Firebase, Hugging Face, Apple)
- **Zweisprachig (DE/EN)**: Die App ist komplett zweisprachig – inklusive
  Farbschemata, Stimmungs-Chips und Entdecken-Modi; auf Deutsch heißt es
  konsequent „Funke(n)", auf Englisch „Spark(s)"
- **Mindestversions-Gate**: Clients unterhalb der serverseitigen Mindestversion
  zeigen beim Start einen Update-Screen (mit Rückfallebene „Trotzdem
  fortfahren")
- **Crash-Journal**: Der letzte Absturz wird lokal gespeichert; beim nächsten
  Start fragt die App, ob ein Report über den Bug-Report-Kanal gesendet werden
  soll (nichts verlässt das Gerät ohne Bestätigung)
- **Bug Report**: Beschreibung (max. 5000 Zeichen) plus bis zu 5
  Screenshots/Bilder, Versand per Email
- Anzeige der App-Version unten (Login/Registrierung und Einstellungen)

---

## Sicherheitskonzept

### Verschlüsselung

- **Ende-zu-Ende-Verschlüsselung** (Signal Protocol) + **Peer-to-Peer** (WebRTC):
  Nachrichten liegen nicht im Klartext auf Servern. **Peer-Pinning** im
  Signaling-Routing: Nachrichten fremder Absender werden verworfen.
- **Verschlüsselte Profilbilder**: Avatare werden clientseitig per AES-256-GCM
  verschlüsselt (Zufalls-Schlüssel pro Bild, im photos-Eintrag mitgeführt) – bei
  einem Bucket-Leak sind die Bilder unlesbar; Anzeige nur lokal entschlüsselt.
- **Verschlüsseltes Key-Backup**: die Signal-Identität wird passwortbasiert
  gesichert (PBKDF2 + AES-256-GCM, frische IVs) – der Server sieht das Backup
  nie unverschlüsselt.
- **Lokale Speicherung**: Tokens und profilbezogene PII ausschließlich im
  Keystore/Keychain (`flutter_secure_storage`), Hive-Daten AES-verschlüsselt,
  Cloud-Backups deaktiviert (`allowBackup=false`).

### Datenschutz

- **Standortdaten**: Distanzangaben sind auf 5-km-Schritte gerundet, Suchradius
  maximal 200 km; exakte Koordinaten werden nie an andere Nutzer übertragen.
  Gespeichert ist nur das Bundesland.
- **Pseudonymisierung**: Reporter-IDs werden gehasht (SHA-256), kein PII in
  lokalen Hive-Keys.
- **Push-Benachrichtigungen** transportieren nur Metadaten (nie Inhalte), werden
  serverseitig gegen Benachrichtigungs-Schalter geprüft und nur an Nutzer mit
  realer Beziehung zugestellt (Funke oder eigener Like).
- **Serverseitige Freigabe-Prüfungen**: Foto-Freischaltung erst bei
  Quiz-Stufe 2, Partner-Profil-Freischaltung mit expliziter Feld-Whitelist
  (exakte Koordinaten und FCM-Tokens verlassen den Server nie).
- **Keine Kontaktdaten auf dem Server**: Telefonnummer und Handles aus
  „Connect to others" liegen ausschließlich verschlüsselt auf dem Gerät.

### Zugang & Missbrauch

- **Altersschutz (Migration 154/155)**: Der Filter ist **beidseitig** – 16- und
  17-Jährige sehen ausschließlich Gleichaltrige, nie einen Erwachsenen, und
  umgekehrt. Maßgeblich ist das **verifizierte** Alter, nicht die Angabe im
  Profil; Konten ohne Verifizierung erscheinen in keiner Begegnungsliste. Die
  Altersspanne ist nach unten auf 10 Jahre unter dem eigenen Alter begrenzt.
  Erzwingen tut das der Server (`age_compatible_bidirectional`,
  `max_age_range_min`), nicht die App – die App ist nur die Anzeige.
- **Verifikation**: Minderjährige werden bei der Video-Verifizierung **immer von
  Hand geprüft**, nie automatisch freigegeben. Das Video wird clientseitig
  verschlüsselt gespeichert (nur Chiffrat im Bucket).
- **Bot-Schutz**: Cloudflare Turnstile Captcha vor sensiblen Aktionen.
- **Rate-Limits** serverseitig u. a. für Likes, Push-Versand, QR-Code-Abfragen,
  Invite-Code-Tests und Entsperrungsanträge (persistente DB-Buckets).
- **Account-Sperrung**: gebannte E-Mail-Adressen können sich weder registrieren
  noch einloggen; Entsperrungsantrag mit Begründung möglich.
- **Bild-Schutz**: eingehende Chat-Bilder standardmäßig verpixelt, Freischaltung
  nur nach Bestätigung. **Meldung mit KI-Vorprüfung:** Chat-Bilder werden nie
  automatisch gescannt – erst eine Meldung des Empfängers prüft exakt dieses
  eine Bild per NSFW-KI (Edge Function `report-image`). Der Meldende sieht
  das KI-Ergebnis sofort; bei Bestätigung erhalten Bild, Report und
  KI-Ergebnis das Team automatisch per E-Mail.
- **NSFW on-device für Profilbilder**: Der Upload-Check läuft komplett lokal
  (gebündeltes ONNX-Modell via onnxruntime, ~12 MB) – das Bild verlässt bei
  Nichtbestehen das Gerät nicht; bestandene Bilder werden serverseitig nie
  gescannt.
- **Serverzeit** als Single Source of Truth für die Dating Hour (Anti-Cheat
  gegen Manipulation der Geräteuhr); Warn-Banner im Event-Screen bei
  unverifizierter Serverzeit.

### Betrieb

- **Cert Pinning** für Supabase- und Hugging-Face-Endpunkte (per-Host-Map,
  unbekannte Hosts fail-open mit Warnung); auch Signaling-/ICE-Aufrufe nutzen
  den gepinnten Client.
- **PreKey-Bundles** sind nur mit gültigem Nutzer-JWT abrufbar (keine
  User-Enumeration per Anon-Key).
- **Härtete SQL-Schicht**: RLS auf allen Tabellen, SECURITY DEFINER-Funktionen
  mit gehärtetem `search_path`, Blockier-Prüfung bei Likes, Rate-limited
  Existenzabfragen.
- **Migrations-robuste Sync-Schicht**: Ladevorgänge fallen stufenweise auf
  ältere Spaltensätze zurück, Schreibvorgänge entfernen bei PostgREST-„missing
  column"-Fehlern automatisch die fehlende Spalte und schreiben den Rest – eine
  nicht eingespielte Migration kann niemals Name, Bio, Theme oder Suchradius
  gemeinsam auslöschen.
- **Session-Restore** synchron (kein Netzwerk beim App-Start), serverseitige
  Validierung im Hintergrund.
- **Release-Signierung**: Build bricht fehl, wenn kein Keystore konfiguriert
  ist (kein stiller Debug-Fallback).
- **Passkey/WebAuthn**: Die GoTrue-Ursprungs-Liste muss den **SHA-256**-Hash der
  installierten APK enthalten (`android:apk-key-hash:…`, 43 Base64URL-Zeichen) –
  SHA-1-Fingerprints matchen nie. Das vollständige Angriffsbild steht im
  [Threat Model](passkey-assets/threat-model.md).

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

## Ausblick

Die nächsten Schritte stehen im [Roadmap](ROADMAP.md). Kernig sind gerade:

- **Sanctuary (v0.11.0)** – ein vollständig offlinefähiger, geschützter Raum
  zur Selbstreflexion, betrieben durch rein lokale On-Device-Sprachmodelle.
- **Web-Bridge und Zero-Install-Gäste (v0.12.0)** – Menschen ohne App
  erreichen (OS-Share, NFC, QR), und Gäste chatten E2E im Browser, ohne
  Download und ohne Konto.

---

## Hinweis zum Entwicklungsstand

Diese App befindet sich in aktiver Entwicklung (aktuelle Version 0.10.0).
Folgende Bereiche sind noch nicht final:

- **Automatischer Gesichtsabgleich** (Profilbild vs. Verifizierungs-Video) →
  z. B. selbstgehostete Open-Source-Modelle wie DeepStack oder Face
  Recognition (selbst gehostet, datenschutzfreundlich, EU-fähig)
- **Chat-Bild-Moderation** – Profilbilder werden on-device geprüft (das Bild
  verlässt bei Nichtbestehen das Gerät nicht, Einspruch mit Team-Review
  möglich). Chat-Bilder werden nie beim Senden gescannt (E2E), sondern erst
  bei einer Meldung durch den Empfänger per NSFW-KI. **Noch offen:**
  automatische Account-Sperren bei Wiederholungsverstößen (derzeit manuell)
- **Foto-Moderation über die KI** (Hugging Face) ist standardmäßig deaktiviert
  (Aktivierung per Build-Flag)
- **Fake-Account-Erkennung per Standort** – *teilweise umgesetzt*: Datenmodell
  und Manipulationschutz (die Verifizierungs-Felder sind clientseitig nicht
  schreibbar), Edge Functions mit Plausibilitätsprüfung und verschlüsselte
  lokale Speicherung sind da. **Noch offen:** der serverseitige Abgleich, ob
  an derselben Position bereits andere Accounts existieren, die Validierung
  von GPS gegen Bundesland/Land, eine Admin-Ansicht zur Prüfung markierter
  Accounts sowie Konsequenzen (z. B. Einschränkungen bei Verdacht)
- **i18n-Rest**: Die App ist zweisprachig; einzelne ältere/hart codierte
  UI-Strings stehen noch nicht im L10n-Katalog

---

## Lizenz

Dieses Projekt steht unter der **GNU Affero General Public License v3.0
(AGPLv3)**.

Das bedeutet insbesondere:

- Der Code darf verwendet, verändert und weiterverbreitet werden.
- Wird die Software (auch als Server-/Cloud-Dienst) genutzt oder verändert,
  muss der Quellcode ebenfalls unter der AGPLv3 offengelegt werden.
- Eine kommerzielle Nutzung als geschlossenes, proprietäres Produkt ist damit
  ausgeschlossen.

---

## Kontakt

Bei Fragen oder Vorschlägen gerne ein Issue im Repository erstellen.
