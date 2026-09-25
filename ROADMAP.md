# Roadmap

Öffentliche Planung – ohne Fixierung auf Termine (Beta = Prioritäten können
sich durch Feedback verschieben). Konkrete Entscheidungshistorie:
[docs/adr/](docs/adr/).

## Versionierungslogik

- **0.7.x** – Fixes & Polish (keine neuen Kern-Features)
- **0.8.0** – Geschmack & Matching: Musik-Genres, Präferenz-/Matching-
  Features, Moderation on-device, i18n-Ausbau
- **0.9.0** – Nahbereichs-Funke („Transit Spark", BLE): das erste komplett
  neue Kern-Feature
- **0.10.0** – Emotionaler Rückzugsort (Sanctuary) & lokaler
  KI-Reflexions-Chat (rein on-device)
- **0.11.0** – Web-Bridge, Transit-Reachability & Zero-Install
  Gast-Verbindungen (Flutter Web, Codeberg Pages)
- Neue Nutzerfunktionen sind immer MINOR-Bumps; nur Fixes gehen in PATCH.

## Erledigt

- [x] **0.5.0** – Erste öffentliche Beta: Find your Match, Zufallschat,
      QR-Verbindung, Dating Hour, Quiz-Freischaltung, 2FA/Passkeys,
      E2E-Chats & -Anrufe, Video-Verifizierung (Beta), Entfernungsanzeige
- [x] Sicherheits-Audit-Runden 1–3 inkl. Server-Härtung (RLS, Rate-Limits,
      Feld-Whitelist, JWT-Pflicht für PreKeys)
- [x] **0.6.x** – 6 Farbschemata, verschlüsseltes E2E-Key-Backup (PBKDF2 +
      AES-256-GCM), Safety Center, Bild-Blur im Chat + Meldungs-Workflow
      (manuelle Moderation), UnifiedPush, Build-Flavors `play`/`fdroid`
      (+ Build-Doku, Fastlane-Metadaten), „Funke"-Umbenennung,
      Passkey-Diagnose, Accessibility-Durchlauf (ScreenReader-Labels,
      Text-Skalierung bis 3.2×)
- [x] **0.7.0** – Umsetzung des umfassenden Sicherheitsaudits: serverseitig
      erzwungener Jugendschutz, Session im Keystore/Keychain, E2E-Reparatur
      (PreKey-/SignedPreKey-Rotation, persistenter Identity-Trust),
      vollständige Account-Löschung inkl. Storage-Wipe, Anti-Trilateration,
      EXIF-Stripping, Zertifikat-Pinning, offene Registrierung
      (Migration 063)
- [x] **0.7.1** – Polish- & Fix-Release: Doppelte E-Mail-Registrierung
      abgefangen, Ladekreis ab dem ersten Start, Deutsch-Crash behoben,
      Stadt/Ort + Präferenzen (Entfernung, „Ich suche", Bundesland,
      Geschlechts-Filter, Altersspanne) werden serverseitig gespeichert und
      überleben Neuinstallationen (Migration 066), Standort-Erkennung ohne
      Einfrieren, 2FA-„Später erinnern", abgerundete Dropdowns, englische
      Auth-Texte, Bild-Meldung mit NSFW-KI-Vorprüfung (064), Admin-Sperr-
      Werkzeug mit Begründung (admin-ban), Statusleisten-Icon-Rundung,
      Einrichtungs-Garantie (onboarding_done, 065)
- [x] **0.7.2** – Dating-Hour-Release: Startzeit korrekt 20:00 Europe/
      Berlin (Sommer-/Winterzeit, Migration 067), Mindestteilnehmer 20
      (darunter fällt das Event aus), keine Partner-Dopplungen im
      Matching, Dating-Hour-Präferenzen bleiben über Events/Neuinstallationen
      erhalten, Mood of the Day öffentlich sichtbar (024 nachgezogen),
      Altersdifferenz-Hinweis (>= 10 Jahre) im Event-Chat, Admin-
      Blackscreen behoben + Card-Look, Zurück-Geste beendet die App nicht
      mehr, Formulierungs-Fix, Passkey-Erstellung mit 2FA-Step-up
- [x] **0.7.3** – Fix-Release: Altersspanne im Profil-Editor ergänzt,
      Ladekreis direkt nach dem Anmelde-Klick, Dating-Hour-Zurück führt zur
      Seite davor, Teilnehmer-Fortschritt „X von 20" im Event-Screen
      (Migration 068), 2FA-Anzeige/Passkey (frischer MFA-Status + Step-up
      vor der Passkey-Erstellung), Auto-Logout nach Stunden behoben
      (Session-Refresh mit Wiederholung beim Start), Benachrichtigungs-
      Symbol als klare Herz-Silhouette (vorher praktisch leer),
      Reporter-Pseudonymisierung (069), Nachweis-Pflicht für Bild-Meldungen
      (068), 20er-Ziel nur mit Accounts >= 24 h (070)
      - Nachtrag (+6): angemeldete Geräte einsehen + „Überall abmelden",
        Themefarbe/Entfernung/Altersspanne überleben Neuinstallationen
        (Migration 071), Dating-Hour-Regeln nur einmal pro Konto,
        Altersspannen-Regler-Fix (18-18), Profil-Editor-Speicherdialog,
        Notification-Icon-Alpha-Fix (weißes Viereck), Passkey-Registrierung
        robust (Pre-Cancel-Race + Doppel-Tap-Schutz)
- [x] **Dating-Hour-Zeit: Fallback gehärtet** – Live-Check bestätigte:
      `server-time` antwortet korrekt; die Regression war der transiente
      Fallback auf die lokale Gerätezeit bei fehlgeschlagenem Zeit-Abruf.
      Jetzt: Sync mit Retry + Backoff beim Start und bei App-Rückkehr
      (bis zu 3 Versuche), deutliches Warn-Banner solange keine
      Serverzeit, und die harte Prüfung (Beitritt) bleibt serverseitig
      (Event-Status aus der DB). Verbleibend: Bei einem erneuten Vorfall
      Ursache per App-Log bestätigen
- [x] **0.8.0 Nachtrag 1** (Build 12) – DH über 20 hinaus (echte
      Teilnehmer-Zahl), Chat-Export/-Import für Gerätewechsel,
      pro-CPU-APKs + AAB-Build
- [x] **0.8.0 Nachtrag 2** (2026-09-07) – verschlüsselte Profilbilder
      (AES-256-GCM, Migration 077), Profilbilder serverseitig persistent,
      NSFW on-device wirksam (Modell-Ladefix + Inferenz-Test),
      migrations-robuste Sync-Schicht (Fallback-Laden, selbstheilende
      Writes, Theme-Restore dreistufig), Pausenmodus in die
      Sichtbarkeits-Auswahl integriert (Dopplung aufgelöst), Chat-Verlauf
      in drei Modi (Aus/200/Alles), echtes Gerätemodell in „Angemeldete
      Geräte" (078), Zweisprachigkeit für Farbschemata/Moods/Entdecken-
      Modi/Sichtbarkeit, „Funke(n)"-Sprache konsequent, Sync-Fehler
      sichtbar (SnackBar + check_columns.sql), abgerundete Klick-Animation
- [x] **0.9.0-Beta** – Transit Spark (BLE-Nahbereichs-Funke: Encounter-
      Cache 45 min, Advertising/Scanning, asynchrones Matching per RPC
      `match_proximity_spark` mit Jugendschutz + Blockier-Prüfung;
      gegenseitige Likes erzeugen den Funke über die Bestandspipeline),
      Messe-Modus (RSSI-Schärfe) + Merkmal-Tags (1–3, whitelisted, 082),
      public_profiles-View → SECURITY-DEFINER-RPCs (080, Option A),
      Entdecken-Gruppierung („Unterwegs" = QR + Transit Spark), Onboarding
      als Interview (Thestia-Frage-Bubbles, zweisprachig); Soft-Ping folgt
      in 0.9.1, Gerätetest ausstehend

## In Arbeit

- [ ] Applogo & Branding-Feinschliff (Quelle konsolidiert auf
      `wispdating_icon_base.png`; Größen/Masken/Farbwelt-Abstimmung folgen)
- [ ] F-Droid-Veröffentlichung (Build-Seite fertig: google-freier Flavor,
      UnifiedPush, Fastlane-Metadaten – Einreichung steht noch aus)
- [ ] **Vorstellungs-Vorlagen (Text + Audio)**: Prompt-Karten (rotierend,
      z. B. „Erzähl von einem Moment, der dich zuletzt zum Lachen gebracht
      hat") als opt-in Gerüst für die Text-Vorstellung – ein Tipp fügt
      einen Einstiegssatz ein, Freitext bleibt erlaubt. Für die Audio-
      Vorstellung ein 3-Schritte-Leitfaden als Bildschirm-Begleitung beim
      Aufnehmen (Wer bist du? / Was macht dich aus? / Warum bist du hier?).
      Ziel: natürliche, persönliche Vorstellungen statt stumpfer Daten-
      Aufzählung – zahlt direkt auf das Audio-first-Matching von
      Find your Match ein

## 0.8.0 – Geschmack & Matching (umgesetzt, inkl. Nachträge 1–2)

> Status nach dem Bau (v0.8.0): Umgesetzt mit Migration 074 (Musik,
> Match-Status, Score, ui_prefs) + 075 (Quiz-Pool). Die NSFW-on-device-
> Punkte sind mit Nachtrag 2 (2026-09-07) vollständig wirksam: gebündeltes
> Modell (image-safety-classifier-xs, ONNX-IR auf 9 gepatcht, echtes
> Inferenz-Test), Avatar-Upload-Prüfung aktiv.

- [x] **Musik-Geschmack**: Genres auswählen, die man mag (Mehrfachauswahl,
      inkl. „Instrumental") und – freiwillig – Genres, die man gar nicht
      mag; fließt in den Matching-Score ein und ist im Profil sichtbar
- [x] **Quiz-Fragen vervollständigen**: 60 echte Fragen ersetzen die 5
      Platzhalter (Migration 075, idempotent)
- [x] **Inaktive Funken: eigene Kategorie ganz unten** im Feed
      („Erschlossene Funken"). KEIN Countdown, KEINE Ablauf-Benachrichtigung,
      KEINE „jetzt verlängern!"-Aktion – inaktive Verbindungen rutschen
      still in die Kategorie, es gibt schlicht kein Dingserlebnis
      (bewusst KEIN Streak-/TikTok-Druck)
- [x] **Chats verwalten**: Chats einzeln anwählbar (Mehrfachauswahl) und
      per Button ausblenden (nur für mich, Migration 074) – einzeln oder
      alle auf einmal
- [x] **Re-Funke ohne Druck**: Beide können eine gekühlte Verbindung
      jederzeit mit je einem Tap neu anzünden – ohne Frist (RPC
      respark_match, Migration 074)
- [x] **Ideen-Rad im Meet-Intent** (Test): „Dreh das Rad" wählt aus den
      bestehenden Date-Kategorien einen gemeinsamen Vorschlag; der
      Vorschlag wird als E2E-Nachricht geteilt und im Chat bestätigt
- [x] **Dating Hour ausbauen**: Frage-Karten für Schüchterne (3 sanfte
      thematische Vorschläge – Reise/Alltag/Träume –, 1 Tap übernimmt;
      rotieren pro Stunde)
- [x] **Verbindungs-Score sichtbar**: Der Matching-Score wird serverseitig
      berechnet (Distanz 40 % + gemeinsame Interessen 30 % + Musik 30 %,
      Migration 074) und als „Match: X %" im Find-your-Match angezeigt
      (Transparenz statt Dopamin; die App feiert weiterhin nur echte
      Momente – Funke-Overlay, Streak ohne Schreibzwang – und erzeugt
      keine Belohnungs-Loops)
- [x] **Langsame Enthüllung fein gestuft**: war bereits über die
      Quiz-Freischaltstufen umgesetzt (0 = unscharf/SW, 1 = scharf/SW,
      2 = scharf/farbig) – als v0.8.0-Grundlage bestätigt
- [x] **Ehrliches Beenden**: vorbereitete, freundliche Absage-Texte und
      „Funke ruhig enden lassen" – Ghosting aktiv erschweren (Dialog im
      Chat, Migration 074)
- [x] **NSFW on-device**: vollständig wirksam (Nachtrag 2) – gebündeltes
      Modell `image-safety-classifier-xs.onnx` via onnxruntime; Ladefehler
      behoben (ONNX-IR-Version, Batch-Dimension, 0-255-Pixelskalierung)
      und durch einen permanenten Inferenz-Test abgesichert. Der
      serverseitige Scan aus 0.7.1 bleibt als Fallback bestehen
- [x] **Profilbild-Prüfung beim Upload** (NSFW, melde-unabhängig): aktiv –
      Check vor dem Upload (Bild verlässt bei Nichtbestehen das Gerät
      nicht), Einspruch-Dialog mit Team-Review; offene Feinjustierung des
      Schwellwerts an echten Fällen
- [x] **i18n-Rest**: weitgehend geschlossen – Farbschemata, Stimmungs-Chips,
      Entdecken-Modi, Sichtbarkeits-Optionen und alle neuen Features sind
      zweisprachig; Rest: einzelne ältere harte Strings (Altersfilter,
      Einrichtung)
- [x] **UI-Einstellungen serverseitig synchronisieren**: Der Rest der
      lokalen Präferenzen (Blind Mode, Sichtbarkeit, Dark Mode,
      Benachrichtigungs-Schalter, Blur) folgt in profiles.ui_prefs
      (Migration 074) – nach Neuinstallation ist ALLES wieder da, ganz
      ohne Export/Import. Sensible Inhalte (Chats, E2E-Identität) bleiben
      davon ausgenommen

## Geplant für 0.9.0 – Nahbereichs-Funke („Transit Spark", BLE)

> Status nach dem Bau (v0.9.0-Beta, Endstand): Kern-Feature + Begleit-
> posten + Soft-Ping umgesetzt (Migrationen 080-085). ABWEICHUNG: Das
> Matching läuft als SECURITY-DEFINER-RPC `match_proximity_spark` statt
> als Edge Function - gleiche Aufgabe, einfachere Wartung/Deployment.
> Ergänzt im Bau: Tags v2 (15 Merkmale, generalisiert mit optionaler
> Farbwahl), tägliche Selbst-Angaben beim Radar-Start, Matching v2
> (bemerkte Tags treffen Selbstdarstellung des anderen), Modus-Wahl nach
> REICHWEITE (Normal vs. Nur-direkt-daneben, Fußgänger abgedeckt),
> Bluetooth-Prompt in der App, 2FA-Einfügen-Button, Suchradius-Modus
> serverseitig (085, "Suchradius-weg"-Bug endgültig), RPC-Fallback-Kette
> + Fehlerursache im Snackbar. Geraetetest auf zwei echten Geraeten
> steht aus (BLE-Reichweite, Advertise-Abdeckung, Match-Flow).

> Vision: Man lächelt sich im Zug, Café oder auf einer Messe (z. B.
> Gamescom) an – traut sich aber nicht anzusprechen. Kurz darauf ist die
> Person 50–500 m entfernt. Thestia macht aus diesem Moment trotzdem einen
> Funke: **Asynchrone Two-Tier-Spark-Architektur**.
>
> 1. **Phase 1 (Nahbereichs-Moment per BLE):** In der Nähe (3–10 m)
>    registrieren die Geräte im Hintergrund anonyme, ephemere
>    „Encounter-Tokens" und cachen sie lokal für 45 Minuten.
> 2. **Phase 2 (Asynchroner Funke über Distanz via Supabase):** Tippt
>    Person A (auch 10 Minuten später) auf „Blicke getauscht" und Person B
>    dasselbe, matcht Supabase die Encounter-Tokens + optischen Tags –
>    auch wenn beide inzwischen weit voneinander entfernt sind.
> 3. **Privacy:** Kein Fotokatalog im Raum. Ein Funke entsteht
>    ausschließlich bei **beidseitigem Signal (Double Blind Opt-In)**.
>
> Enthält strikten Jugendschutz (serverseitige Alter/Geschlecht-Prüfung
> wie überall) und Datensparsamkeit (Auto-Cleanup, keine dauerhaften
> Verläufe).

- [x] **Lokaler Encounter-Cache** (`lib/services/encounter_cache_service.dart`):
      Erkannte Thestia-BLE-Tokens mit Zeitstempel + stärkstem RSSI cachen,
      45 Minuten Vorhaltezeit, automatisches Aufräumen alter Einträge
- [x] **BLE Proximity Service** (`lib/services/transit_ble_service.dart`):
      Advertising rotierender ephemerer Tokens + Tag-Bitmask; Scanning auf
      Thestia-UUID; Messe-Modus mit engerem RSSI-Schwellwert (z. B. > -75 dBm
      = echter Sichtkontakt); Batterieschutz über gepulste Scans und
      einstellbaren Auto-Stop-Timer
- [x] **Matching als RPC `match_proximity_spark`** (Abweichung: SECURITY-DEFINER-RPC statt Edge Function - gleiche Aufgabe, kein Extra-Deployment): Nimmt `cachedEncounterTokens`,
      `targetTags`, `timestamp`; prüft, ob in den letzten 30 Minuten eine
      wechselseitige Begegnung zwischen zwei Nutzern mit passendem Alter/
      Geschlecht und übereinstimmenden Tags lag; bei Treffer Realtime-Event
      für beide Clients
- [x] **Datenmodelle** (`lib/models/transit_models.dart`): `TransitTag`
      (id, label, category: clothing/accessory/activity/event, icon),
      `EncounterRecord` (ephemeralPeerToken, detectedAt, strongestRssi),
      `SparkSignal` (senderSessionToken, recentEncounterTokens, targetTagIds,
      timestamp)
- [x] **State Management** (`lib/providers/transit_provider.dart`):
      AsyncNotifier mit `isActive`, `remainingDuration`, `myActiveTags`,
      `currentMode` (transit vs. convention), `encounterCache`,
      `sendSpark(targetTags)` + Realtime-Listener für eingehende Funken
- [x] **Radar-Screen + Messe-Modus + Merkmal-Tags** (`lib/screens/swipe/transit_radar_screen.dart`, Migration 082):
      animiertes Radar im Material-3-Style; Mode-Toggle „Bahn/Café" vs.
      „Messe/Gamescom"; Quick-Action „Gerade Blicke getauscht 👁️✨" öffnet
      Bottom Sheet zur Auswahl von 1–3 Merkmalen (z. B. schwarzer Hoodie +
      Gamescom-Lanyard); diskreter Status-Text („Signal aktiv. Auch wenn
      ihr euch aus den Augen verliert: Wenn die Person denselben Moment
      spürt, matcht ihr euch."); Match-Dialog „Funke übergesprungen! ✨"
      öffnet den Chat mit situativen Fragen („Bist du noch in der Nähe von
      Halle 7?") + optionaler gegenseitiger Foto-Freischaltung nur für
      diese Session
- [x] **Einseitiges Anschreiben („Soft-Ping")** – umgesetzt in v0.9.0 (Migration 083, aus 0.9.1 vorgezogen): Falls die andere Person
      nicht an die App denkt oder sich selbst nicht traut, kann NUR der
      Meldende nach der Begegnung EINMAL eine diskrete Anfrage senden
      (vorgefertigte, freundliche Sätze + optional eine kurze eigene Zeile
      – kein freier Text, kein Spam). Die Person erhält eine dezente
      Benachrichtigung und kann den Funke NACHTRÄGLICH aktivieren.
      Schutzregeln: genau 1 Versuch pro Begegnung (kein Wiederholen),
      die Anfrage verfällt still nach 48 h, der Absender erfährt NIEMALS
      eine Ablehnung (kein Lesestatus, kein „Nein" – Schweigen = Ende),
      Blockier-/Melde-Schutz greift wie überall, Jugendschutz-Filter
      serverseitig
- [x] **Native Berechtigungen**: Android (`AndroidManifest.xml`) und iOS
      (`Info.plist`) BLE-Konfiguration

### Begleitend in 0.9.0 (UX & Server)

- [x] **public_profiles-View durch SECURITY-DEFINER-Funktion ersetzen**
      (Option A – löst den wiederkehrenden Advisor-Befund
      „security_definer_view" auf): RPC `get_public_profile(user_id)` plus
      Batch-Variante `get_public_profiles(ids)` mit der bisherigen
      Spalten-Whitelist und dem `age_compatible`-Jugendschutzfilter;
      Client-Umstellung von `from('public_profiles')` auf die RPCs
      inkl. Umbau der Likes/Match-Embedded-Joins
      (`liker:public_profiles!inner(*)` → Batch-Fetch); Parsing der
      Interessen-/Match-Screens anpassen; die View erst entfernen, wenn
      ALLE Aufrufer migriert sind; Begründungs-Doku (072, ARCHITEKTUR)
      aktualisieren. Aufwand ~½–1 Tag, nicht als Pre-Release-Quickfix
- [x] **Entdecken-Seite: Modus-Gruppierung** (Vorbereitung auf mehr Modi):
      Die Karten nach Zweck gruppieren statt flacher Liste –
      „Menschen kennenlernen" (Find your Match, Dating Hour),
      „Direkt verbinden" (Zufallschat),
      „Unterwegs" (QR-Code teilen/scannen + Transit Spark – beides
      Out-and-About-Szenarien). Neue Modi rutschen damit ohne
      Unübersichtlichkeit ein; NEU-/Experimentell-Badges für frische Modi
- [x] **Onboarding als Interview**: Die Einrichtung vom stumpfen
      Daten-Eingeben zu einem spielerischen Frage-für-Frage-Flow
      umgestalten (eine Frage pro Screen, warme Mikrocopy, immer
      überspringbar) – KEINE neuen Datenpunkte, nur die bestehenden in
      Gesprächsform; bewusst KEIN Belohnungs-Mechanismus (App-Prinzip:
      spielerisch ≠ Dopamin-Loop)
- [x] **Build-15-Nachträge (Chat & Server)**: E2E-Nachrichten-Relay als
      P2P-Fallback (093, nur Ciphertext auf dem Server), geteilte
      Eisbrecher-Bubbles (60 Fragen, 10 Kategorien, DE/EN), Quiz und
      Date-Rad erst nach 50–70 Nachrichten je Chat, Kühl-Dialog auch in
      der Interessen-Liste, Push- statt Go-Navigation (Zurück landet
      immer auf der Seite davor), Routen-Restore nach Prozesstod,
      Lieblingssong/Band in der Einrichtung (092), Transit-Notizfeld
      (091), Funke-Kühl-RPCs als BIGINT (090), Dating-Hour-Mindestzahl
      konfigurierbar + Admin-Tab (094, Standard 20, Test-Minimum 2),
      KI-Kennzeichnung an Bildprüfungen, Video-Verifizierung mit lokaler
  KI-Alters-Triage (095, 2-Jahre-Regel, manuelle Queue für Abweichler)

## Geplant für 0.10.0 – Emotionaler Rückzugsort (Sanctuary) & Lokaler KI-Reflexions-Chat

> Vision: Ein vollständig offlinefähiger, geschützter Raum zur
> Selbstreflexion bei Frust, Zurückweisung oder emotionalen Tiefs –
> betrieben durch rein lokale On-Device-Sprachmodelle. Kein Server, kein
> Konto, keine Weitergabe: Was im Sanctuary geschrieben wird, bleibt im
> RAM (optional lokal AES-verschlüsselt).

### 1. Modell-Management & Download-Pipeline

- [ ] **Stufenbasierte Modellauswahl**:
      * Stufe 1 (Kompakt / Akkusparend): Gemma 4 E2B, Spark-X2.5-1.7B
        (Text-only)
      * Stufe 2 (Erweitert / Tiefgründig): Qwen 3.5-4B, Gemma 4 E4B,
        Spark-X2.5-4B
- [ ] **Quantisierungs-Varianten**: Jedes Modell ist wählbar in
      Q4_K_M (Standard, Balance), Q5_K_M / Q6_K (höhere Qualität) und
      Q3_K_S / IQ3 (wenig Speicher) – der Downloader zeigt Größe/RAM-
      Bedarf je Variante und warnt bei zu knappem Speicher
- [ ] **Multimodal-Kennzeichnung (Vision-Badge)**: Modelle mit
      Bilderkennung werden optisch gekennzeichnet, um Screenshots von
      Chats zwecks Interpretation und Formulierungshilfe analysieren zu
      können
- [ ] **Hugging-Face-Downloader**: Direkter Download der GGUF-Dateien mit
      Fortschrittsanzeige, Hash-Prüfung, Abbruch-/Fortsetzungslogik und
      Speicherwarnung
- [ ] **Eigener Modell-Import**: Manuelle Eingabe beliebiger
      Hugging-Face-Repo-URLs oder lokaler Import von GGUF-Dateien aus dem
      Smartphone-Speicher
- [ ] **Eigene-Modell-Erkennung**: Wird ein importiertes Modell erkannt,
      das einem der kuratierten Vorschlagsmodelle entspricht (Datei-Hash
      bzw. Repo-/Dateiname-Muster), übernimmt die App automatisch dessen
      geprüfte System-Prompt-Vorlage – der Nutzer muss nichts konfigurieren

### 2. Inferenz-Engine & Prompt-Steuerung

- [ ] **Lokale Ausführung** via llama.cpp (FFI) oder MediaPipe / LiteRT –
      ohne jede externe Serververbindung
- [ ] **Fest integrierte, modellspezifisch optimierte System-Prompts** für
      alle kuratierten Standardmodelle (Fokus auf Empathie, kognitive
      Umstrukturierung, offene Fragen, keine falschen Diagnosen)
- [ ] **Editierbarer Standard-System-Prompt** für benutzerdefinierte
      Fremdmodelle

### 3. Sicherheits- und Qualitätssystem

- [ ] **Prominente Hinweise**: Pflichtbanner („KIs machen Fehler, dienen
      rein als Reflexionshilfe und ersetzen keine Therapie")
- [ ] **Modell-Meldung**: Meldefunktion („Modellqualität beanstanden"),
      um unbrauchbare, halluzinierende oder toxische Antworten strukturiert
      zur Prüfung an das Team zu senden
- [ ] **Krisen-Erkennung**: Regex-basierte On-Device-Erkennung suizidaler
      Begriffe mit sofortiger, unaufdringlicher Einblendung von
      Notfallkontakten (Telefonseelsorge, Nummer gegen Kummer)
- [ ] **Datenintegrität**: Chatverläufe verbleiben flüchtig im RAM oder
      werden optional rein lokal AES-verschlüsselt in Hive abgelegt


### Begleitend in 0.10.0 – Begegnung statt Bildschirm

- [ ] **Sync-Dates** (Distanz-taugliche Mini-Dates im Ideen-Rad): Katalog
      von gemeinsamen Aktivitäten für denselben Zeitpunkt trotz Distanz –
      „Spaziergang + Anruf", „Den selben Film schauen", „Koch-Duell",
      „Sterne gucken und dabei telefonieren". Beim Annehmen: gemeinsamer
      Timer + Anruf-Button - während des Dates läuft NUR der Anruf, kein
      Bildschirm. Nutzt bestehendes Ideen-Rad + Audio-Calls.
- [ ] **Offline-Knopf nach dem echten Treffen**: Nach einem Treffen, das
      BEIDE Personen bestätigt haben, erscheint der sanfte Vorschlag
      „Genießt die Zeit - Thestia schweigt bis morgen": Benachrichtigungen
      stumm für den Abend, ruhiger Bildschirm. Die App feiert Abwesenheit
      statt Bindung zu erzeugen (konkrete Form der „Digitalen Entgiftung").
- [ ] **Antizipation statt Streak**: Bei Distanz-Funken den Chat sanft
      Richtung Anruf/Sprachnachricht nudge („Stimmen verbinden mehr als
      Texte"); sobald der Meet-Intent terminiert ist, zeigt der
      Chat-Header die Vorfreude („Treffen am Samstag!") statt
      Chat-Metriken.


## Geplant für 0.11.0 – Web-Bridge, Transit-Reachability & Zero-Install Gast-Verbindungen

> Vision: Nutzer können Menschen im Alltag und im Nahverkehr (z. B. im
> Zug, Bus oder Café) direkt erreichen – unabhängig davon, ob die andere
> Person Thestia installiert hat, sich im selben WLAN befindet oder
> mehrere Waggons entfernt sitzt.

### 1. OS-Level „System-Ping“ (Überbrückung ohne App & ohne Netzwerk)

- [ ] **One-Tap Quick-Share- & AirDrop-Trigger**: Generiert in der App
      eine grafische Einladungskarte mit Blind-Profil, Vornamen, optischen
      Merkmalen und verschlüsseltem Web-Link
- [ ] **Systemweiter Freigabedialog**: Öffnet direkt Android Quick Share /
      iOS AirDrop zur Übertragung via Wi-Fi Direct und BLE
- [ ] **Vollbild-Pop-up beim Gegenüber** (sofern für die Umgebung
      sichtbar): spürbare Vibration + Bildvorschau ohne vorherige
      App-Installation
- [ ] **EU-Hosting & Bereitstellung**: Statische Bereitstellung der
      Flutter-Web-Artefakte über Codeberg Pages (Codeberg e.V., Berlin) –
      vollkommen trackerfrei, ohne US-Cloud-Abhängigkeit (CLOUD Act) und
      mit automatischer SSL-Zertifizierung für die eigene Domain

### 2. Passiver Funk-Leuchtturm (Hotspot-SSID-Beacon)

- [ ] **Temporärer Hotspot-Schalter** mit konfigurierbarem Netzwerknamen
      (SSID), z. B. `thestia.app/RE9-Wagen3` oder `Laecheln_im_Wagen_4`
- [ ] **Sichtbarer Link in der WLAN-Suche** fremder Smartphones bei
      Reichweiten von bis zu 30 Metern
- [ ] **Offline-Captive-Portal**: Verbindet sich die Person mit dem
      Hotspot, öffnet sich automatisch das Web-Profil direkt vom
      Smartphone gehostet; alternativ ist die kurze Web-Adresse über
      mobile Daten im Browser öffnbar

### 3. Fahrplan-Synchronisation & Live-Strecken-Board (`thestia.app/live`)

- [ ] **Exakte Fahrt-Identifikation**: Check-in mit Linie (z. B. RE9),
      offizieller Zugnummer (z. B. RE 4412), Startbahnhof und
      fahrplanmäßiger Abfahrtszeit zur eindeutigen Unterscheidung
      paralleler Fahrten
- [ ] **Waggon-Ruf**: Optionale Angabe des Sitzbereichs (z. B. „Wagen 3,
      oberes Deck") und dezenter visueller Merkmale (z. B. „Schwarze
      Jacke, liest Buch")
- [ ] **Asynchrones Web-Board**: Fahrgäste können während oder nach der
      Fahrt auf `thestia.app/live` nach ihrer Zugverbindung suchen und einen
      anonymen Gast-Chat mit der Person starten

### 4. Same-Train-Matching (für Nutzer mit installierter App)

- [ ] **BSSID- & Gateway-Erkennung**: Erkennt automatisch, wenn zwei
      Geräte im selben Zug-WLAN (z. B. WIFIonICE) angemeldet sind, und
      schaltet eine gemeinsame Waggon-Lobby frei
- [ ] **Vektor- & Geschwindigkeitsabgleich**: Erkennt über grobe
      GPS-Vektoren und übereinstimmende Fahrgeschwindigkeiten auf
      Schienensträngen (>80 km/h), dass sich Nutzer im selben Zug
      befinden – selbst wenn BLE durch Waggontrennwände blockiert ist

### 5. Zero-Install Web-Gastzugang (Flutter Web & Supabase)

- [ ] **Einmalige Einladungslinks** (`thestia.app/spark/<token>`) mit
      kryptografisch gesicherten Session-Tokens
- [ ] **Kein Download, keine Registrierung, keine Telefonnummer und keine
      E-Mail-Abfrage** für den Gast erforderlich
- [ ] **E2E-verschlüsselter P2P-Chat** direkt im mobilen Browser (WebRTC
      via WebAssembly) zur nativen App des Thestia-Nutzers
- [ ] **Flüchtige Sitzungen**: Chatrooms zerstören sich serverseitig nach
      24 oder 48 Stunden rückstandslos selbst

### 6. Interaktive Web-Visitenkarte & Vor-Ort-Schnittstellen

- [ ] **Geschützte Profilansicht für Gäste**: Audio-Vorstellung anhören,
      Hobbys und Mood sehen; Profilfotos bleiben standardmäßig unscharf
- [ ] **Dynamischer Vollbild-QR-Code** mit automatischer Display-Aufhellung
      für schnelles Scannen im Nahbereich
- [ ] **NFC-Unterstützung** für physische Kontaktkarten und Sticker

### 7. Konvertierung & Missbrauchsschutz

- [ ] **Nahtloses Onboarding**: Möglichkeit, den flüchtigen Web-Chat bei
      nachträglicher App-Installation in ein reguläres Konto zu überführen
- [ ] **Rate-Limits** für das Erzeugen von Einladungs-Tokens gegen
      Link-Spam
- [ ] **Eingehende Gast-Nachrichten** unterliegen denselben
      Sicherheitsregeln (Bild-Blur, Meldung mit manueller Admin-Prüfung)

### 8. Begleitend in 0.11.0 – „Mittendrin": Treffpunkt-Orchestrator

- [ ] **Fairer Treffpunkt für Distanz-Funken**: Aus den gerundeten
      Standorten beider Personen Städte-Vorschläge als real erreichbare
      Treffpunkte (beidseitig faire Fahrzeit, Bahn-Anbindung über die
      Fahrplan-Synchronisation) - direkt im Meet-Intent als
      „Wo? -> Mittendrin"-Kapitel statt endlosem „wohin denn?"-Chatten.
      Datenschutz: nur gerundete Koordinaten, Vorschläge auf Stadt-Ebene;
      beide Standorte werden nie genauer behandelt als die ohnehin
      bestehende 5-km-Rundung.

## Irgendwann / Idee

- [ ] Admin-Screen-Überarbeitung (internes Werkzeug): Pillen-förmiger
      Tab-Indikator, Kennzahlen-Zeile oben (offene Meldungen, neue Bugs),
      Suche im Sperren-Tab, einheitliche Karten- und Empty-States
- [ ] Gruppen-Micro-Events (themenbasierte Treffen mit 2-6 Teilnehmern) –
      von der Diskussion bewusst zurückgestellt, um 1:1 nicht zu verwässern
- [ ] Gesichtsfeld-Check (Profilbild vs. Verifizierungs-Video) via
      selbstgehostetem Open-Source-Modell
- [ ] Digitale Entgiftung: sanfte Nutzungs-Erinnerungen (Anti-
      Aufmerksamkeitsökonomie) – Balance finden, damit die App nicht
      „langweilig" wird
- [ ] Öffentliches Threat-Model & Transparenzberichte

## Versionierungsprinzip

Semantic Versioning (`MAJOR.MINOR.PATCH`), Start in der `0.x`-
Entwicklungsphase. Details: [CHANGELOG.md](CHANGELOG.md).
