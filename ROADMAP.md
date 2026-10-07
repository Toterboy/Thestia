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
- **0.9.1** – veröffentlicht: E-Mail-Bestätigungspflicht, Safety Number,
  Nähfunk-Jitter, Standort-TTL, rotierende Vorstellungs-Prompts
- **0.10.0** – **in Arbeit:** Standort-Privatisierung (Ort entfällt,
  5-km-Raster serverseitig erzwungen, Entfernung nur zustimmungspflichtig
  und in Stufen), Transit Spark auf echten Geräten, Auslieferungs-
  Hygiene. MINOR-Bump **nach Regel** – eine Änderung der
  Datenverarbeitung für Nutzende ist eine Kern-Funktion
- **0.11.0** – Emotionaler Rückzugsort (Sanctuary) & lokaler
  KI-Reflexions-Chat (rein on-device)
- **0.12.0** – Web-Bridge, Transit-Reachability & Zero-Install
  Gast-Verbindungen (Flutter Web, Codeberg Pages)
- Neue Nutzerfunktionen sind immer MINOR-Bumps; nur Fixes gehen in PATCH.
- **Regel „neue Nutzerfunktion = MINOR" ist zweimal gebrochen worden**,
  nachträglich gekennzeichnet: 0.7.2 (Mood öffentlich, Altersdifferenz-
  Hinweis, Passkey-Step-up) und 0.7.3 (angemeldete Geräte ansehen,
  „Überall abmelden"). Beide Male waren die Funktionen an ein
  Sicherheitsaudit desselben Releases gekoppelt. Das ist ein vertretbarer
  Grund, aber es bleibt eine Ausnahme – künftige Abweichungen brauchen
  denselben dokumentierten Anlass.
- „Kern-Funktion" im Sinne dieser Regel: eine Änderung des
  Funktionsumfangs **oder** der Datenverarbeitung für Nutzende. Vorlagen,
  Polish und Sprachausbau sind es nicht. Diese Abgrenzung war vorher
  nirgends festgelegt – und hat dazu geführt, dass die
  Standort-Privatisierung unter der Nummer 0.9.2 als PATCH geführt
  wurde, obwohl sie genau in diese Definition fällt. Mit dem Bump auf
  **0.10.0** ist der Widerspruch aufgelöst, statt ihn ein drittes Mal
  stehenzulassen. Die Abgrenzung ist damit erstmals angewendet worden.

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
      erhalten, Admin-Blackscreen behoben + Card-Look, Zurück-Geste beendet
      die App nicht mehr, Formulierungs-Fix
      - **Anlage 0.7.2 – Funktionen trotz PATCH-Version:** „Mood of the
        Day öffentlich sichtbar" (024 nachgezogen), Altersdifferenz-Hinweis
        (>= 10 Jahre) im Event-Chat, Passkey-Erstellung mit 2FA-Step-up.
        Bewusst gebündelt, weil alle drei aus demselben Sicherheitsaudit
        stammten; nachträglich als dokumentierte Ausnahme von der Regel
        „neue Nutzerfunktion = MINOR" gekennzeichnet, statt stillschweigend
- [x] **0.7.3** – Fix-Release: Altersspanne im Profil-Editor ergänzt,
      Ladekreis direkt nach dem Anmelden-Klick, Dating-Hour-Rückzug führt zur
      Seite davor, Teilnehmer-Fortschritt „X von 20" im Event-Screen
      (Migration 068), 2FA-Anzeige/Passkey (frischer MFA-Status + Step-up
      vor der Passkey-Erstellung), Auto-Logout nach Stunden behoben
      (Session-Refresh mit Wiederholung beim Start), Benachrichtigungs-
      Symbol als klare Herz-Silhouette (vorher praktisch leer),
      Reporter-Pseudonymisierung (069), Nachweis-Pflicht für Bild-Meldungen
      (068), 20er-Ziel nur mit Accounts >= 24 h (070)
      - Nachtrag (+6): **angemeldete Geräte ansehen + „Überall abmelden"**
        (Anlage 0.7.3 – erweitert den Funktionsumfang; die nach 0.7.0
        geltende Regel "neue Nutzerfunktion = MINOR" ist hier bewusst
        überschritten worden, weil das Feature mit dem Sicherheitsaudit
        dieses Releases gekoppelt war. Als Ausnahme dokumentiert, nicht
        stillschweigend), Themefarbe/Entfernung/Altersspanne überleben
        Neuinstallationen (Migration 071), Dating-Hour-Regeln nur einmal pro
        Konto, Altersspannen-Regler-Fix (18-18), Profil-Editor-Speicherdialog,
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

> Kein eigener Meilenstein – dieser Abschnitt sammelt Arbeiten, die noch
> keinem Release zugeordnet sind. Jeder Eintrag nennt unten sein Ziel.

- [ ] Applogo & Branding-Feinschliff – Quelle ist
      `assets/images/thestia_icon_base.png` (941×941, im Repo vorhanden);
      Größen/Masken/Farbwelt-Abstimmung folgen. **Ziel: 0.10.0.**
      Store-Icon (512×512) und Feature Graphic (1024×500) sind bereits
      erzeugt, siehe `tool/make_play_icon.py` und
      `tool/make_feature_graphic.py`
- [ ] F-Droid-Einreichung (google-freier Flavor, UnifiedPush, Fastlane-
      Metadaten liegen vor; Einreichung steht aus). **Ziel: 0.10.0**,
      unabhängig vom Play-Upload
- [ ] **Vorstellungs-Vorlagen (Text + Audio)**: Prompt-Karten (rotierend,
      z. B. „Erzähl von einem Moment, der dich zuletzt zum Lachen gebracht
      hat") als opt-in Gerüst für die Text-Vorstellung – ein Tipp fügt
      einen Einstiegssatz ein, Freitext bleibt erlaubt. Für die Audio-
      Vorstellung ein 3-Schritte-Leitfaden als Bildschirm-Begleitung beim
      Aufnehmen (Wer bist du? / Was macht dich aus? / Warum bist du hier?).
      Ziel: natürliche, persönliche Vorstellungen statt stumpfer Daten-
      Aufzählung – zahlt direkt auf das Audio-first-Matching von
      Find your Match ein. **Ziel: 0.10.0**, ausformuliert unter
      „Geplant für 0.10.0".

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

## Umgesetzt: 0.9.0 – Nahbereichs-Funke („Transit Spark", BLE)

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
> 3. **Privacy – präzise gefasst:** Im Nahbereich werden **keine Bilder
>    übertragen und kein Fotokatalog aufgebaut**. Funk-Signale bleiben
>    technisch beobachtbar: ein passiver Sniffer kann Advertising-Pakete
>    sehen. Deshalb rotieren die Encounter-Tokens, und die gejitterten
>    Sendintervalle verhindern, dass aus den Abständen ein
>    wiedererkennbares Muster über die Sitzung entsteht. Vollständige
>    Funk-Unsichtbarkeit ist mit BLE nicht erreichbar und wird hier nicht
>    behauptet. Ein Funke entsteht ausschließlich bei **beidseitigem
>    Signal (Double Blind Opt-In)**.
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

## Geplant für 0.10.0 – Standort-Privatisierung, Transit Spark auf echten Geräten & Qualitätssicherung

> Status: 0.9.1 ist veröffentlicht.
>
> **Dieses Release ist ein MINOR-Bump, und zwar nach der eigenen Regel
> dieser Roadmap.** Die Regel sagt: „Neue Nutzerfunktionen sind immer
> MINOR-Bumps; nur Fixes gehen in PATCH" – und definiert Kern-Funktion
> als eine Änderung des Funktionsumfangs **oder der Datenverarbeitung für
> Nutzende**. Die Standort-Umstellung ist genau das: der Ort wird nicht
> mehr erhoben, die Entfernungsanzeige ist zustimmungspflichtig und
> gestuft. Das war bis 0.9.2 als PATCH geführt – ein Widerspruch, der mit
> der Umbenennung auf 0.10.0 aufgelöst ist. Die frühere Begründung „kein
> neues Kern-Feature und keine neue Datenerhebung" galt für den
> ursprünglichen Zuschnitt und ist seit der Standort-Arbeit überholt.
>
> Transit Spark wird in diesem Release ebenfalls erst belastbar gemacht
> und die Auslieferungs-Hygiene nachgezogen.
>
> **Bedingung für den Release von 0.10.0:** Der BLE-Gerätetest ist der
> einzige Punkt, der den Release blockiert. Ist er bis dahin nicht
> bestanden, wird Transit Spark serverseitig für Neuregistrierungen
> gesperrt (Flag in `app_config`, wirkt über die bestehende RPC) – und
> **nicht** so getan, als wäre der Release durch das offene Kriterium
> erlaubt. Die Entscheidung wird vor dem Upload getroffen, nicht danach.

- [x] **Standort-Privatisierung (expand → client → contract)** – der
      eigentliche Grund für den MINOR-Bump. Umgesetzt in Migrationen
      135 bis 143:
      - Der Ort (Stadt) wird **nicht mehr erhoben**, gespeichert oder
        angezeigt. Sichtbar ist ausschließlich das Bundesland.
      - Koordinaten liegen auf einem **5-km-Raster** in
        `profile_locations`, einer per RLS nur für den Eigentümer
        lesbaren Tabelle. Das Raster wird **serverseitig erzwungen**
        (BEFORE-Trigger, Migration 137) – nicht nur in der App.
      - Die Spalten `city`, `location_lat` und `location_lng` sind aus
        `profiles` **entfernt** (Migration 138). Das war nötig, weil die
        RLS über Zeilen und nicht über Spalten entscheidet.
      - Die Entfernungsanzeige ist **aus und zustimmungspflichtig**
        (`show_distance`, serverseitig geprüft). Eingeschaltet zeigt sie
        Stufen von 10 km, unter 5 km gar nichts.
      - Die Löschung nach 30 Tagen läuft wieder (Migration 143 – siehe
        Statusblock unten).
      - Datenschutzerklärung auf Version 6 aktualisiert.
      > **Offen:** nichts davon ist je auf einem Gerät durchlaufen
      > worden. Der Serverzustand ist durch Migration 142 verifiziert,
      > der Client-Pfad nicht. Prüfpunkte 4.12 bis 4.15 in
      > `docs/RELEASE-ABNAHME.md`.
- [ ] **Folge des Contract-Schritts prüfen** – Migration 138 macht
      **jede** bereits gebaute App unbrauchbar, die `city` oder
      `location_*` aus `profiles` liest. Das ist kein Absturz, sondern
      ein stillschweigend fehlgeschlagener Profilabgleich – die schlimmste
      Fehlerform, weil niemand etwas meldet. Vor einem Upload ist zu
      entscheiden, ob eine Mindestversion durchgesetzt wird (z. B. über
      `auth.jwt()->>'ver'` im RPC) oder ob der Play-Zwang genügt.
- [ ] **BLE-Gerätetest als HARTER Release-Blocker** – Transit Spark gilt
      erst als stabil, wenn Reichweite, Advertise-Abdeckung und der
      komplette Match-Flow auf MINDESTENS 2 echten Geräten verschiedener
      Android-Hersteller erfolgreich durchlaufen. Simulator und Emulator
      zählen nicht (kein echtes Advertising, keine realistische
      Reichweite, kein Funkrauschen). Der in 0.9.0 als „Gerätetest
      ausstehend" vermerkte Punkt bleibt bis dahin offen – er ist kein
      Nice-to-have, sondern Abnahmekriterium. **Durchsetzung: siehe
      Statusblock oben.** Protokoll: `docs/BLE-GERAETETEST.md`
- [ ] **BLE-Tracking-Härtung (Privacy im Funk)** – *vorgezogen, steht
      vor den kosmetischen Punkten, weil die Exposition bereits
      gegenwärtig für jeden Nutzer mit aktivem Transit Spark besteht.*
      Umgesetzt in 0.10.0: rotierende Encounter-Tokens mit Jitter,
      Herstellerfilter, gepulstes Scanning. **Offen und zuerst zu
      klären:** die Plattform-Frage. Resolvable Private Addresses
      rotieren auf Android als **Plattformverhalten**; eine App kann sie
      für eigenes Advertising nicht erzwingen, und `flutter_blue_plus`
      bietet dafür keine API. Zu prüfen ist deshalb, was sich tatsächlich
      steuern lässt: frische Token pro Advertising-Neustart, Jitter der
      Intervalle, Verkürzung der Fenster. Der Eintrag wird nicht als
      „RPA umgesetzt" verbucht, solange das nicht belegt ist.
- [x] **Dependency-Hygiene in CI** – erledigt: `flutter pub outdated`- und
      CVE-Prüfung je Pipeline-Lauf, exakte Pins für alle 16
      sicherheitsrelevanten direkten Abhängigkeiten (kein `^` für
      Anything mit Sicherheitsverhalten), SBOM (CycloneDX) für die
      F-Droid-Einreichung, zentral gepinnte Tool-Versionen in
      `tool/requirements.txt`. CI-Jobs: `dependency-audit` und
      `static-checks`
- [x] **Öffentliches Threat-Model** – fertig: [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md).
      Benennt Vertrauensgrenzen, Angriffsflächen (RLS/`SECURITY DEFINER`,
      Jugendschutz, BLE-Metadaten, Standort, E2E-Irrtum, Lieferkette,
      Moderation/Drittland, Authentifizierung), die Maßnahmen und – ohne
      Beschönigung – die Restrisiken. `SECURITY.md` und die
      Datenschutzerklärung verweisen darauf. `SECURITY.md` selbst war
      bereits öffentlich und nennt `security@thestia.de`
- [x] **Incident-Response mit 72-Stunden-Uhr (Art. 33 DSGVO)** –
      fertig: [docs/INCIDENT-RESPONSE.md](docs/INCIDENT-RESPONSE.md).
      Rollen, Triage in 4 h, Schweregrade mit Fristen, konkreter
      Reaktionsablauf (Eindämmen vor Ursachenanalyse, Sitzungswiderruf),
      Umgang mit kompromittiertem Signing-Key und Firebase-Key, Nachbereitung
      mit Pflicht zur Konsequenz
- [~] **Datenschutzfolgeabschätzung (Art. 35 DSGVO)** – fachlich
      erstellt: [docs/DSFA.md](docs/DSFA.md), **als Entwurf markiert**.
      Nicht rechtsgeprüft. Enthält Rechtsgrundlagen je Verarbeitung,
      Risikobewertung und – für Minderjährige – fünf zusätzliche
      Vorkehrungen. **Offen und nicht wegformuliert:** neun Punkte in
      Abschnitt 7, darunter Mindestalter, Auftragsverarbeitungsverträge
      je Anbieter, Art. 22 für den Matching-Score, Widerspruchsverfahren
      bei Altersablehnung, Bewertung der Krisen-Erkennung als
      Nicht-Medizinprodukt. Vor dem Launch rechtlich zu prüfen
- [ ] **Bleibt Betreiberentscheidung:** Mindestalter verbindlich
      festlegen, Live-Board und Same-Train-Matching für Minderjährige
      sperren, BLE-Nahbereich für unter 18-Jährige abschaltbar machen.
      Vorschläge stehen in Abschnitt 5 der DSFA, sie sind fachlich
      begründet und rechtlich nicht geprüft
- [ ] **Vorstellungs-Vorlagen (Text + Audio)** – hier verbindlich für
      0.10.0 eingeplant; Ausformulierung siehe „In Arbeit". Kleines
      Feature, aber es hebt die Profilqualität der frühen Nutzerschaft
      direkt, solange das Match-Erlebnis noch ohne Stimmen auskommt

## Geplant für 0.11.0 – Emotionaler Rückzugsort (Sanctuary) & Lokaler KI-Reflexions-Chat

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

- [ ] **Inferenz-Engine**: **llama.cpp über FFI ist der tragfähige
      Pfad** – Gemma 4 und Spark-X2.5 liefern GGUF-Checkpoints, und
      Spark-X2.5 wird von llama.cpp nativ unterstützt. **NICHT** MediaPipe
      oder LiteRT: das sind Frameworks für Vision- bzw. klassische
      On-Device-ML, nicht für autoregressive Textgenerierung. Für
      Gemma 4 existiert mit **ML Kit GenAI Prompt API / Google AI Edge**
      zusätzlich ein erstklassiger Android-Pfad, der ohne eigenen
      llama.cpp-Build auskommt – der gehört als Alternative geprüft,
      weil er RAM und Akku deutlich schont. Beides ohne jede externe
      Serververbindung
- [ ] **Hugging-Face-Downloader: Drittlandproblem lösen.** Modelle über
      Hugging Face zu beziehen ist die einfachste Variante und die
      bequemste, aber der Anbieter ist US-gestützt, während 0.12.0
      US-Cloud-Abhängigkeit ausdrücklich als Ausschlusskriterium führt
      (CLOUD Act). Zusätzlich übermittelt jeder Metadatenabruf die
      IP-Adresse des Nutzers an einen US-Dienst. Zu entscheiden:
      eigener EU-Spiegel, oder die Aussage in 0.12.0 relativieren.
      Spark-X2.5 stammt von iFlytek (CN) – die Governance-Frage ist
      damit nicht auf US-Anbieter begrenzt
- [ ] **Modellgrößen gegen den Speicher dokumentieren** (Gemma 4 E2B
      mobil ca. 1,1 GB, E4B mobil ca. 2,5 GB; Q4_0 2,9 bzw. 4,5 GB):
      der Downloader warnt bisher nur vor RAM-Mangel, nicht vor
      fehlendem Speicher. Die App selbst ist bereits 1,6 GB groß, ein
      2,5-GB-Modell verdoppelt das
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
- [ ] **Import-Sicherheitsnetz für benutzerdefinierte Modelle**: jeder
      manuell importierte GGUF-Download bekommt einen sichtbaren
      Warnhinweis (ungeprüfte Qualität und Sicherheit, keine
      Haftungsübernahme) und wird intern als „Fremdmodell" markiert
- [ ] **Schutzschicht unterhalb des System-Prompts (nicht abschaltbar)**:
      Für Fremdmodelle bleiben Krisen-Erkennung und Therapie-Hinweis-
      Banner technisch erzwungen. Sie liegen UNTERHALB der Prompt-Ebene,
      damit weder ein selbst geladener GGUF noch ein manipuliertes Modell
      sie aushebeln kann. Der editierbare System-Prompt gilt
      ausschließlich oberhalb dieser Schicht – die fest verdrahtete
      Reihenfolge lautet Schutzschicht → editierbarer Prompt → Modell.
      Wer den Schutz entfernen will, kann das nicht per Konfiguration,
      nur durch Entfernen der App
- [ ] **Notruf 112 neben den Beratungsstellen** (Telefonseelsorge, Nummer
      gegen Kummer). Fehlt bisher und ist die naheliegendste Reaktion
- [ ] **Verhalten bei Wegtippen des Krisen-Banners**: Was passiert, wenn
      jemand die Einblendung schließt? Ohne definierte Antwort bleibt die
      Maßnahme eine Anzeige ohne Handlungskette
- [ ] **Rechtsberatung zur Haftungsformulierung** (Krisen-Erkennung,
      Pflichtbanner, „ersetzt keine Therapie"). Das Banner ist ein
      Haftungshinweis, kein Sicherheitsnachweis
- [ ] **Einordnung als Nicht-Medizinprodukt** in der App und in den
      Store-Metadaten. Medizinprodukteregulierung (MDR/IVDR) und
      Jugendschutz bei Minderjährigen sind bisher nicht bewertet –
      Sanctuary wird voraussichtlich auch von Nutzenden unter 18 genutzt
- [ ] **Evaluation der Krisen-Erkennung, nicht nur Regex**: Eine
      Regex auf suizidale Begriffe trifft keine Umschreibungen, keine
      metaphorischen Formulierungen und keine mehrsprachigen Eingaben.
      Ohne Testmenge ist nicht belegbar, wie hoch die Erkennungsrate
      ist – das ist gegenüber Nutzenden eine Zusage, die derzeit nicht
      gedeckt ist. Mindestanforderung: dokumentierte Testmenge mit
      Positiv- und Negativfällen, Recall-Wert, und die Erkennung läuft
      **zusätzlich** zum Modell, nicht nur bei einer Modellantwort
- [ ] **Restrisiko benennen**: Der Schutz entfällt, wenn die App
      deinstalliert wird. Das ist als Eigenschaft der Architektur korrekt
      und nicht zu beheben – es gehört aber offen kommuniziert, statt als
      Stärke dargestellt zu werden


### Begleitend in 0.11.0 – Begegnung statt Bildschirm

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

### Vorschläge zu 0.11.0 (nicht terminiert, nicht eingeplant)

> Die folgenden drei Punkte sind **Ideen, keine Zusagen**. Sie standen
> bisher in derselben Liste wie die fest eingeplanten Einträge und waren
> daran nur durch das Präfix „VORSCHLAG" erkennbar. Sie sind jetzt
> getrennt, damit der Status auf einen Blick stimmt. Jeder bekommt vor
> einer Aufnahme in 0.11.0 eine Entscheidung: angenommen, abgelehnt oder
> vertagt – mit Begründung, nicht nur mit Häkchen.

- [ ] **VORSCHLAG: Date-Safety-Check-in** (Anschluss ans Safety Center):
      optionaler Begleit-Modus für ein von BEIDEN bestätigtes echtes
      Treffen. Nach ~2 Stunden eine dezente Nachfrage („Alles okay?") und
      ein Schnellzugriff auf den Notfallkontakt – bewusst zurückhaltend,
      ohne Push-Druck und ohne sichtbaren Countdown. Rein lokal (Timer +
      lokaler State), KEINE Standort-Übertragung: Thestia erfährt weder,
      wo das Treffen stattfindet, noch ob ein Check-in unterblieben ist.
      Damit kann aus dem Safety-Feature kein Überwachungs- oder
      Ortungsdruck entstehen
      - **Offener Konflikt:** siehe 0.12.0 §4 (BSSID- und
        Geschwindigkeitsabgleich). Solange dort kontinuierliche
        präzise Standortdaten erhoben werden, ist die Zusage dieses
        Vorschlags nicht haltbar. Beides muss entschieden werden
- [ ] **VORSCHLAG: Privacy-Dashboard im Profil** (aus den Vorschlägen
      herausgenommen – die Aufschlüsselungspflicht ist keine Option):
      Übersichtsseite, die sichtbar macht, welche Daten ausschließlich
      lokal liegen (Chats, E2E-Identität und Pre-Keys, Sanctuary-Modelle)
      und welche serverseitig gespeichert sind (Präferenzen und
      Sync-Spalten aus 066/074, verschlüsselte Profilbilder aus 077).
      Keine neuen Daten, nur eine Aufschlüsselung der bereits bestehenden
      Trennung – Datenschutzparsamkeit wird für die Nutzenden überprüfbar
      statt behauptet
      - **Umgehängt auf 0.9.x:** Die Information über die Verarbeitung
        nach Art. 13/15 DSGVO besteht unabhängig vom Nice-to-have-Status.
        Als Teil des Datenschutz-Bereichs, nicht als Produktidee
- [ ] **VORSCHLAG: „Abschied in die Realität"**: Nach beidseitig
      bestätigtem echten Treffen macht die App einen sanften, einmaligen
      Vorschlag zum direkten Kontaktaustausch (z. B. Telefonnummer oder
      Signal-Account) und tritt danach zurück. Bewusste Produktentscheidung:
      Thestia „entlässt" erfolgreiche Paare, statt sie an den Bildschirm zu
      binden – das Gegenteil von Streak, Read-Receipt und
      Reaktivierungskampagnen. Ablehnung ist selbstverständlich und ohne
      jede Konsequenz; es gibt ausdrücklich keinen „Ablehnungen"-Zähler
- [ ] **Öffentliches Threat-Model & SECURITY.md**: **nach 0.10.0
      vorgezogen** (dort als eigener Eintrag geführt). `SECURITY.md` ist
      bereits öffentlich und nennt `security@thestia.de` mit
      72-Stunden-Eingangsbestätigung – der Meldeweg steht also, das
      **Angriffsbild** fehlt noch: RLS-Modell, PUBLIC-EXECUTE-Falle bei
      Functions, BLE-Metadaten, Zero-Install-Web-Gastzugang ohne Account,
      Drittlandtransfers bei der Moderation. Aus „Irgendwann" gestrichen,
      weil die Roadmap an zwei Stellen sonst verschiedene Zeiten für
      dasselbe Vorhaben nennt


## Geplant für 0.12.0 – Web-Bridge, Transit-Reachability & Zero-Install Gast-Verbindungen

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

> **MACHBARKEIT VOR BAU KLÄREN – die Fähigkeit steht so nicht mehr
> zur Verfügung.** Ein App-gesteuerter Hotspot mit eigenem SSID ist auf
> aktuellen Systemen nicht mehr zuverlässig umsetzbar:
> `WifiManager.setWifiApEnabled` ist seit Android 10 stark
> eingeschränkt, benötigt Standortberechtigung und aktive Ortungsdienste
> und wird von mehreren Herstellern blockiert. Unter iOS kann eine App
> grundsätzlich **keinen** Hotspot erzeugen – „Persönlicher Hotspot" ist
> eine Systemfunktion. Vor der Umsetzung ist zu entscheiden: auf
> Android-only und experimentell zurückstufen, oder streichen. Als
> plattformneutraler Baustein geplant wäre die Funktion irreführend.

- [ ] **Temporärer Hotspot-Schalter** mit konfigurierbarem Netzwerknamen
      (SSID), z. B. `thestia.app/RE9-Wagen3` oder `Laecheln_im_Wagen_4`
      – **nur Android, experimentell** (Bedingung siehe oben)
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
      oberes Deck") und dezente optische Merkmale (z. B. „Schwarze
      Jacke, liest Buch")
- [ ] **Asynchrones Web-Board**: Fahrgäste können während oder nach der
      Fahrt auf `thestia.app/live` nach ihrer Zugverbindung suchen und einen
      anonymen Gast-Chat mit der Person starten
- [ ] **Stalking-Schutz für Waggon-Ruf & Live-Board – VORAUSSETZUNG,
      nicht Folgepunkt.** Die drei vorstehenden Einträge (exakte
      Fahrt-Identifikation, Waggon-Ruf, asynchrones Web-Board) erzeugen
      genau die Daten, die dieser Punkt begrenzt. Wird er erst danach
      umgesetzt, ist die Frist bereits abgelaufen. Reihenfolge im
      Arbeitsablauf: Schutzschicht zuerst, Feature danach freischalten.
      - Präzise Angaben (Linie + Wagen + optische Merkmale) werden erst
        nach beidseitigem Funke sichtbar – vorher bleibt der Eintrag auf
        Linien-Ebene
      - Board-Einträge löschen sich automatisch nach Fahrtende bzw.
        spätestens nach 24 h, serverseitig und unabhängig davon, ob ein
        Client noch läuft (dasselbe Auto-Cleanup-Prinzip wie beim
        Encounter-Cache: wer nichts mehr anzeigt, hat nichts mehr
        gespeichert)
      - Kein dauerhaft mitlesbarer Standort-Feed, der über die Zeit ein
        Bewegungsprofil ergibt
      - **Noch offen: Aufbewahrung der Check-in-Rohdaten selbst.** Der
        Punkt regelt die Sichtbarkeit von Board-Einträgen, nicht die
        Lebensdauer der zugrunde liegenden Datensätze (Linie, Zugnummer,
        Abfahrtszeit, Sitzbereich). Ohne eigene Frist entsteht genau das
        Bewegungsprofil, das der letzte Spiegel verhindern soll.
        Festzulegen: Frist, Zugriff (nur die betroffenen Nutzenden),
        Löschung unabhängig vom Client, und ob die Daten überhaupt
        persistiert werden müssen

### 4. Same-Train-Matching (für Nutzer mit installierter App)

> **ZWEIFELHAFT – steht in Konflikt zur eigenen Datenschutzposition.
> Vor Umsetzung entscheiden, nicht während.** Die beiden folgenden
> Verfahren erzeugen präzise Standort- und Bewegungsdaten. Der
> Date-Safety-Check-in in 0.11.0 sagt ausdrücklich zu: „KEINE
> Standort-Übertragung: Thestia erfährt weder, wo das Treffen
> stattfindet". Beides kann nicht gleichzeitig gelten.
>
> Hinzu kommt die technische Seite: Die BSSID des aktuellen WLANs ist
> ab Android 8 nur mit Standortfreigabe *und* aktiven Ortungsdiensten
> lesbar und wird ab API 29 von Google häufig maskiert. Ein
> BSSID-Abgleich ist also unzuverlässig **und** datenschutzfeindlich
> zugleich. Der Geschwindigkeitsabgleich >80 km/h bedeutet zudem
> kontinuierliche GPS-Erfassung während der gesamten Fahrt.

- [ ] **Entscheidung vor der Umsetzung**: Verzicht auf BSSID-Abgleich,
      Verzicht auf kontinuierlichen Geschwindigkeitsabgleich, oder
      ausdrückliche Einwilligung mit eigener Speicherfrist. Der
      Eintrag bleibt offen, bis das entschieden ist
- [ ] **BSSID- & Gateway-Erkennung**: Erkennt automatisch, wenn zwei
      Geräte im selben Zug-WLAN (z. B. WIFIonICE) angemeldet sind, und
      schaltet eine gemeinsame Waggon-Lobby frei – **nur nach
      Einwilligung und nur als Vorschlag, nicht automatisch**
- [ ] **Vektor- & Geschwindigkeitsabgleich**: Erkennt über grobe
      GPS-Vektoren und übereinstimmende Fahrgeschwindigkeiten auf
      Schienensträngen (>80 km/h), dass sich Nutzer im selben Zug
      befinden – selbst wenn BLE durch Waggontrennwände blockiert ist.
      **Nur mit Einwilligung, mit eigener Speicherfrist für die
      Bewegungsdaten und mit Abschaltung in den Einstellungen**

### 5. Zero-Install Web-Gastzugang (Flutter Web & Supabase)

- [ ] **Einmalige Einladungslinks** (`thestia.app/spark/<token>`) mit
      kryptografisch gesicherten Session-Tokens
- [ ] **Kein Download, keine Registrierung, keine Telefonnummer und
      keine E-Mail-Abfrage** für den Gast erforderlich
      - **Rechtlich zu klären, bevor gebaut wird:** Die Gäste-Sitzung
        ist zwar anonymer als ein Konto, aber sie ist nicht
        datenfrei – Serverseit entstehen Raum, Zeitstempel und
        Chiffrat. Das ist personenbezogene Verarbeitung und braucht eine
        benannte Rechtsgrundlage (berechtigtes Interesse o. ä.) sowie
        eine Löschfrist. Die Zusage ist deshalb auf **keine
        Kontaktdaten** zuspitzen, nicht auf „keine personenbezogenen
        Daten" – sonst weckt sie einen Eindruck, den die Einrichtung
        nicht erfüllt
- [ ] **E2E-verschlüsselter P2P-Chat** direkt im mobilen Browser (WebRTC
      via WebAssembly) zur nativen App des Thestia-Nutzers
      - **ABHÄNGIGKEIT, bisher nirgends geführt:** Das Signal-Protokoll
        muss für Web verfügbar sein. Die native App bringt eine
        Dart-Implementierung mit; im Browser ist das ein eigenes Projekt
        (WASM-Build, WebCrypto für die Schlüsselableitung, sichere
        Zufallsquellen, Schlüsselspeicher). Ohne diese Grundlage ist der
        Zero-Install-Gastzugang nicht umsetzbar, egal wie sauber der
        Rest aussieht. Als eigener Arbeitspaket-Eintrag zu führen
- [ ] **Serverseitige Chat-Räume mit Auto-Zerstörung** als Voraussetzung
      für die Zusage „zerstören sich nach 24/48 h". Es existiert bisher
      keine Raum-Infrastruktur; sie braucht einen serverseitigen
      Aufräum-Mechanismus (Cron/jobs), der unabhängig davon läuft, ob
      noch ein Client verbunden ist
- [ ] **Flüchtige Sitzungen**: Chaträume werden serverseitig nach 24
      oder 48 Stunden gelöscht. Formulierung bewusst ohne
      „rückstandslos" – Daten in Backups, Logs und Schlüsselmaterial
      können eine kürzere Frist nicht versprechen; die zugesagte Frist
      gilt für die produktiven Datensätze

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

### 8. Begleitend in 0.12.0 – „Mittendrin": Treffpunkt-Orchestrator

- [ ] **Fairer Treffpunkt für Distanz-Funken**: Aus den gerundeten
      Standorten beider Personen Städte-Vorschläge als real erreichbare
      Treffpunkte (beidseitig faire Fahrzeit, Bahn-Anbindung über die
      Fahrplan-Synchronisation) - direkt im Meet-Intent als
      „Wo? -> Mittendrin"-Kapitel statt endlosem „wohin denn?"-Chatten.
      Datenschutz: nur gerundete Koordinaten, Vorschläge auf Stadt-Ebene;
      beide Standorte werden nie genauer behandelt als die ohnehin
      bestehende 5-km-Rundung.

## Irgendwann / Idee

- [ ] **Eigene Hintergründe im Chat zeichnen**: die sechs
      mitgelieferten Muster (`lib/data/chat_backgrounds.dart`) sind
      fester Bestandteil. Nutzer sollen eigene Hintergründe bauen
      können – eigene Farbverläufe, Muster-Zeichner (Vektor statt
      gerastert, damit es auf jedem Display scharf bleibt) und
      ausgewählte Chat-Hintergründe der anderen Seite als Vorlage
      übernehmen. Offen sind vor allem: was mit fremden Mustern passiert
      (Urheberrecht, Moderation), wie groß ein Hintergrund maximal sein
      darf, und wie das mit dem Vergrößern der Bilder in
      `profile_widgets.dart` zusammenpasst. Ohne diese Antworten
      verschiebt man nur die Probleme
- [ ] **Spenden-Button mit echter Zieladresse**: Der Button ist wieder
      da (`lib/widgets/donate_button.dart`), `kDonateUrl` ist aber leer.
      Offen ist die Abwicklung – Zahlungsanbieter, steuerliche
      Behandlung, Beleg, Rückerstattung – und ob daraus das frühere
      „Spender"-Badge zurückkommt (damals entfernt, weil die Zahlung
      eine Attrappe war). Ohne Zieladrede bleibt der Button eine
      höfliche Enttäuschung
- [ ] **Eigene Komponenten statt Standard-Widgets**: die App setzt
      an vielen Stellen rohe Material-Widgets ein – 137 `FilledButton`,
      102 `TextButton`, 83 `IconButton`, 69 `AlertDialog`, 78 `Card`,
      69 `ListTile`. Die auffälligsten Stellen: `chat_detail_screen.dart`,
      `settings_screen.dart`, `transit_radar_screen.dart`,
      `privacy_screen.dart`, `interessen_screen.dart`. Bisher ad hoc
      gelöst (zwei Auswahl-Widgets mit eigener Optik, `SelectableTile`,
      `ThemePicker`), aber ohne gemeinsame Bibliothek. Ziel ist ein
      Satz eigener Bausteine – Knopf, Dialog, Karte, Zeile, Segment –
      mit einer statt drei Optiken und eigener Drück-Physik, damit sich
      die App nicht wie eine Standard-Flutter-App liest
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
- [ ] **Drittanbieter als eigenes Betriebsrisiko führen**: Brevo
      (E-Mail), Cloudflare (Turnstile), Netlify (Passkey-Assets),
      Firebase (FCM) und für 0.12.0 Codeberg. Offen sind je Anbieter
      Auftragsverarbeitungsvertrag, Drittlandtransfer und
      Fähigkeit des Anbieters, die US-EU-Data-Privacy-Framework-
      Zertifizierung zu tragen. Dazu ein Notfallplan: Was passiert,
      wenn ein Anbieter seine Bedingungen ändert, sein Quota erhöht
      oder ausfällt? Für eine App, die US-Cloud-Abhängigkeit als
      Wertverlust verkauft, ist das die zentrale betriebliche
      Schwachstelle – sie stand bisher nirgends
- [ ] **Aufbewahrungskatalog konsolidieren**: Einzelzusagen existieren
      (Standort 30 Tage, Live-Board 24 h, Encounter-Cache 45 min,
      Soft-Ping 48 h, Chat-Verlauf wählbar). Fehlt ist die
      zusammengeführte Übersicht **einschließlich Backups**: was
      passiert mit Supabase-Backups, dem Pre-Key-Speicher und
      Push-Payloads. Die Information nach Art. 13 DSGVO besteht
      unabhängig davon, ob die Umsetzung steht
- [ ] **Belastbare Durchsetzung des Mindestalters**: Die Roadmap nennt
      „serverseitig erzwungenen Jugendschutz" und eine KI-Alters-Triage
      mit manueller Queue, aber kein konkretes Mindestalter, keine
      Rechtsgrundlage, kein Widerspruchsverfahren, keine Regel für
      Altersband-Unschärfe und keine Aufbewahrung der
      Verifizierungsmedien. Für eine App mit Jugendschutz ist das die
      zentrale rechtliche Voraussetzung, kein Feature
- Öffentliches Threat-Model: **nach 0.10.0 vorgezogen**, dort geführt

## Versionierungsprinzip

Semantic Versioning (`MAJOR.MINOR.PATCH`), Start in der `0.x`-
Entwicklungsphase. Details: [CHANGELOG.md](CHANGELOG.md).
