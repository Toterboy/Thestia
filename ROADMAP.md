# Roadmap

Öffentliche Planung – ohne Fixierung auf Termine (Beta = Prioritäten können
sich durch Feedback verschieben). Die konkrete Entscheidungshistorie liegt in
den ADRs des Projekts (betrieblich, nicht im öffentlichen Repository).

## Versionierungslogik

- **0.7.x** – Fixes & Polish (keine neuen Kern-Features)
- **0.8.0** – Geschmack & Matching: Musik-Genres, Präferenz-/Matching-
  Features, Moderation on-device, i18n-Ausbau
- **0.9.0** – Nahbereichs-Funke („Transit Spark", BLE): das erste komplett
  neue Kern-Feature
- **0.9.1** – veröffentlicht: E-Mail-Bestätigungspflicht, Safety Number,
  Nähfunk-Jitter, Standort-TTL, rotierende Vorstellungs-Prompts
- **0.10.0** – **gebaut** (Build 50, Prerelease auf GitHub; der Store-Upload steht noch aus – das Play-Console-Projekt fehlt): Standort-Privatisierung (Ort entfällt,
  5-km-Raster serverseitig erzwungen, Entfernung nur zustimmungspflichtig
  und in Stufen), Transit Spark auf echten Geräten, Auslieferungs-
  Hygiene, dazu der Ausbau von „Find your Spark“ (Zufallsvorstellung
  **oder** Vorstellungen nach Interessens-Kategorien, mit serverseitig
  erzwungener Altersgrenze und text-only-Vorstellung). MINOR-Bump
  **nach Regel** – eine Änderung der Datenverarbeitung für Nutzende ist
  eine Kern-Funktion
- **0.10.1** – **umgesetzt** (Build 51/52): Die Namens-Entscheidung beim
  Transit Spark (der Dialog fragt beim ersten Öffnen, danach bleibt der
  Schalter änderbar), der serverseitige Nachrichtenzähler, „Nachricht für
  alle löschen“ (der Server speichert nur die Tatsache, keinen Inhalt), die
  Transit-Kandidatenliste (mehrere mit derselben Beschreibung, mehrere
  anschreiben) und die ungefaehre Ortsangabe (Selbstauskunft, kein Standort).
- **0.11.0** – Emotionaler Rückzugsort (Sanctuary) & lokaler
  KI-Reflexions-Chat (rein on-device)
- **0.12.0** – Web-Bridge, Transit-Reachability & Zero-Install
  Gast-Verbindungen (Flutter Web, Codeberg Pages). Gruppen und Foren
  kommen **danach** (eigener Abschnitt unten)
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
- [x] **UX-/Sicherheits-Update (2026-10-30)** – Dock-Beschriftung für alle
      vier Tabs, ruhigeres Tab-Wischen mit gebremstem Finger-Follow und
      Feder-Rücklauf, Transit-Spark-Funke im gleichen Motiv wie „Find your
      Spark" (Zug bleibt stehen), Interessen-Screen mit eingeklappten
      Gesendet-/Erhalten-Panels und animierter Funken-Blase,
      Profil-Vorschau und echtes Profil vollflächig im Geburtstags-Stil,
      QR-Schnellzugriff auf „Aktuelles"; Sicherheits-Aufklärung vor dem
      Setup (Ja/Nein-Fragen, fünf Lernseiten, max. 5 Minuten, lokaler
      Fortschritt, Wiederherstellungs-Fallback) inklusive öffentlicher
      Seite `/dating-sicherheit`; „QR Code scannen Modi" zu „Connect to
      others" erweitert (Telefon und Social Media, verschlüsselt nur
      lokal, Signal/Threema empfohlen, Instagram/Snapchat/Discord
      gekennzeichnet); Datenschutzerklärung Version 17 und README ergänzt
- [x] **Passkey-Reparatur (2026-10-31)** – der Passkey-Plugin war im
      Release-Build **gar nicht vorhanden** (`supabase_flutter` hängt nur am
      Platform-Interface, nicht am app-seitigen `passkeys`-Paket; Flutter
      baut ein Endorsed-Plugin nur ein, wenn die App selbst davon abhängt).
      Im APK fehlten die Plugin-Klassen und die Berechtigung
      `CREDENTIAL_MANAGER_SET_ORIGIN` – jeder Versuch endete mit
      „MissingPluginException". `passkeys` ist jetzt eine direkte, exakt
      gepinnte Abhängigkeit; ein Regressionstest verhindert die
      Wiederholung. Dazu: der Sicherheitscheck wird erst abgefragt, wenn
      der Server ihn wirklich verlangt, und Passkey-Fehler werden
      konkret benannt statt „fehlgeschlagen" zu melden
- [x] **UI-Nachschliff (2026-10-31)** – Transit-Spark-Kachel verschiebt den
      Text beim Moduswechsel nicht mehr (der Rand zählte zum Innenabstand),
      Profil-Menü mit Rand nach oben, Ladekreise mit runden Enden
      (zentral in der Theme), Name im Profil bleibt trotz Abzeichen
      mittig, Verifiziert-Abzeichen auch in den Interessen-Listen sichtbar

## In Arbeit

> Kein eigener Meilenstein – dieser Abschnitt sammelt Arbeiten, die noch
> keinem Release zugeordnet sind. Jeder Eintrag nennt unten sein Ziel.

- [~] Applogo & Branding-Feinschliff – Quelle ist
      `assets/images/thestia_icon_base.png` (941×941, im Repo vorhanden).
      **Im Kern erledigt:** Store-Icon (512×512) und Feature Graphic
      (1024×500) sind erzeugt (`tool/make_play_icon.py`,
      `tool/make_feature_graphic.py`), alle Icon-Masken sind geprüft, und
      die Website führt jetzt ein Favicon (`tool/make_favicon.py`).
      **Offen:** Feinschliff an Masken und Farbwirkung – kein
      Blocker für den Upload.
- [x] **Store-Listing auch auf Englisch** (03.11.2026) – die englische
      Liste war unvollständig: Sie hatte **keine** Phone-Screenshots, und
      die Tablet-Bilder waren Kopien der deutschen. Wer die englische
      Liste öffnete, sah ein englisches Feature-Graphic über deutschen
      Screenshots mit deutschen Headlines – ein Bild, das in zwei
      Sprachen spricht. Jetzt ist beides getrennt:
      * Der Renderer läuft je Sprache: `store_v091_shots_test.dart` mit
        `STORE_SHOTS_LANG=en` schreibt nach `test/screenshots/store_v091_en/`.
        Entscheidend war der `L10nScope`: `MaterialApp.locale` allein
        ändert nur Datum und Zahlen, die App-Texte kommen aus
        `L10n.t` – ohne den Scope bleibt der Screen deutsch.
      * Der Compositor hat je Sprache eigene Quelle, eigene Texte und
        eigene Ausgabe (`tool/make_store_screenshots.py`, `PROFILE`).
      * Die Textprüfung gilt für beide Sprachen (`_check_claims_en`):
        „ready in a minute" wäre sonst durchgerutscht.
      * Das Tablet-Skript baut je Sprache aus der eigenen Quelle –
        die englischen Bilder sind englisch, nicht übersetzt.
      * Nebenbefund: das Render-Profil bekam ein Erwachsenen-Alter. Ohne
        `birthDate` rechnet die App mit 0 Jahren, und 0 ist ein
        Minderjähriger – der Datenschutz-Screen zeigte im Store die
        Jugendschutz-Variante („In deinem Alter bleibt die Entfernung
        aus"), während die Kachel-Überschrift das Erwachsenen-Verhalten
        beschrieb. Zwei widersprüchliche Aussagen in einem Bild.
- [ ] F-Droid-Einreichung (google-freier Flavor, UnifiedPush, Fastlane-
      Metadaten liegen vor; Einreichung steht aus). **Ziel: 0.10.0**,
      unabhängig vom Play-Upload
- [x] **Vorstellungs-Vorlagen (Text + Audio)**: Prompt-Karten (rotierend,
      z. B. „Erzähl von einem Moment, der dich zuletzt zum Lachen gebracht
      hat") als opt-in Gerüst für die Text-Vorstellung – ein Tipp fügt
      einen Einstiegssatz ein, Freitext bleibt erlaubt. Für die Audio-
      Vorstellung ein 3-Schritte-Leitfaden als Bildschirm-Begleitung beim
      Aufnehmen (Wer bist du? / Was macht dich aus? / Warum bist du hier?).
      Ziel: natürliche, persönliche Vorstellungen statt stumpfer Daten-
      Aufzählung – zahlt direkt auf das Audio-first-Matching von
      Find your Match ein. **Ziel: 0.10.0**, ausformuliert unter
      „Geplant für 0.10.0".
      **Umgesetzt:** Der Text-Teil war schon in 0.9.2 fertig (rotierende
      Prompt-Karten aus vier Themen, `lib/data/intro_prompt_catalog.dart`;
      ein Tipp hängt den Einstiegssatz an, Freitext bleibt erlaubt).
      Der Audio-Teil kam in 0.10.0: `lib/widgets/intro_recording_guide.dart`
      zeigt während der Aufnahme die drei Winkel in fester Reihenfolge.
      Zwei Entscheidungen, die absicht sind: die Schritte laufen von
      selbst (alle 15 Sekunden ein neuer Winkel), ein Tipp auf einen
      Schritt übernimmt aber dauerhaft die Steuerung – der Nutzer hat
      das letzte Wort; und nach dem dritten Schritt bleibt der dritte
      stehen, weil die Aufnahme bis 5 Minuten laufen darf und der
      Leitfaden nur drei Winkel hat. Der Leitfaden ist eine Stütze, kein
      Fragebogen. **Seit 0.10.0 (Build 49) ist die Aufnahme optional** (Befund vom
09.11.2026): Pflicht ist der **Text**; die Aufnahme bleibt
verschluesselt gespeichert und wird erst beim Funke gehoert.

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

### Umgesetzt: 0.10.1 – der Name bei Transit Spark

> **Neuer Wunsch vom Betreiber (10.11.2026):** „Ich finde aber, dass man
> bei Transit Spark einstellen können soll, ob der Name für andere sichtbar
> sein soll oder nicht."
>
> **Was das genau bedeutet (und was nicht):** Beim Transit Spark sieht
> die andere Person heute dein **Merkmal** (Haarfarbe, Brille, Hemd …) und
> deine **freie Notiz**. Dein **Name** wird erst sichtbar, wenn daraus ein
> Funke wird – dann ist er ohnehin über den Chat bekannt. Die Einstellung
> betrifft also genau eine Stelle: **der Name, solange noch kein Funke
> besteht**.
>
> **Die Regel, die dafür gelten muss (das ist der schwierige Teil):**
> Ein Schalter, der nur im Gerät steht, wäre wertlos – die andere Person
> sieht den Namen über den **Server** (die Merkmale laufen über
> `transit_signals`). Die Einstellung muss deshalb **serverseitig**
> durchgesetzt werden: Der Server darf den Namen im Signal gar nicht
> mitgeben, wenn er abgeschaltet ist. Sonst wäre der Schalter nur Theater.
>
> **Bekannte Grenze, die vorher geklärt sein muss:** Bei einem echten
> Treffen ist der Name meist ohnehin bekannt (man sieht sich). Der
> Schalter schützt also vor allem den Fall „ich bin in der Nähe, aber
> niemand soll meinen Namen wissen" – und **nicht** davor, dass dich
> jemand erkennt. Das gehört in den Text der Einstellung, sonst
> entsteht eine falsche Sicherheit.
>
> **Vorschlag für die Umsetzung:**
> 1. **Beim ersten Öffnen** des Transit-Radars fragt ein Dialog: Name
>    sichtbar ja oder nein? (umgesetzt, Migration 208/209)
> 2. Serverseitig: `profiles.transit_show_name` (der Wert) und
>    `profiles.transit_show_name_set` (hat entschieden). Der Name wird
>    beim Lesen der Soft-Pings aufgelöst – nie gespeichert – und nur
>    übertragen, wenn der Nutzer ihn freigegeben hat (umgesetzt).
> 3. Der Transit-Screen zeigt den Schalter an – mit dem Hinweis auf die
>    Grenze aus oben. Jede Änderung am Schalter zählt als Entscheidung
>    (umgesetzt).
> 4. Die Datenschutzerklärung (V6) bekommt den Eintrag: welche Angabe
>    wann sichtbar ist (umgesetzt, Abschnitt 3b-1).
> **ENTSCHIEDEN (Betreiber, 10.11.2026):** Es gibt **keinen
> Default** – der Nutzer entscheidet selbst. Beim **ersten Öffnen** des
> Transit-Radars fragt ein Dialog: Name sichtbar ja oder nein? Danach
> kommt der Dialog nicht mehr, und der Schalter in der Ansicht bleibt
> **jederzeit änderbar** (jede Änderung am Schalter zählt ebenfalls als
> bewusste Entscheidung).
>
> **Umsetzung:** Migration 208 (der Wert) + Migration 209 (das Flag „hat
> entschieden"). Der Dialog lässt sich nicht wegklicken – die Entscheidung
> soll bewusst sein; „nein, bleib anonym" ist ja auch eine Entscheidung.
> Die Antwort liegt auf dem **Server**, damit das zweite Gerät nicht
> nochmal fragt.

### Stand 11.11.2026: 0.10.1 ist umgesetzt (Build 51/52)

Der Wunsch des Betreibers („der Name beim Zuwinken soll abschaltbar
sein") ist umgesetzt – und die Entscheidung liegt beim **Nutzer**:
Beim ersten Öffnen des Transit-Radars fragt ein Dialog, danach bleibt
der Schalter jederzeit änderbar.

Dazu kamen die drei Verbesserungsideen und die Frage nach dem
Nachrichtenlöschen:

| Punkt | Stand |
|---|---|
| Die kleine Zahl in der Kachel (serverseitig) | umgesetzt (Migration 210) |
| Die Kategorie-Sicht ohne Sackgasse | umgesetzt |
| Die Nah-Liste zeigt die Gesamtzahl | umgesetzt |
| „Nachricht für alle löschen" (wie WhatsApp) | umgesetzt – der Server speichert **nur die Tatsache**, keinen Inhalt (Migration 210/214) |
| Transit Spark: mehrere mit derselben Beschreibung | umgesetzt (Migration 213) |
| Transit Spark: der ungefähre Ort (Selbstauskunft) | umgesetzt (Migration 213) |

**Datenschutz-Bewertung zum Löschen:** Der Server merkt sich nur, *dass*
eine Nachricht gelöscht wurde – kein Text, keine Chiffre. Das ist mit
dem E2E-Modell vereinbar. Ehrlich gesagt werden muss: die bereits
zugestellte Kopie beim Gegenüber kann nicht zurückgerufen werden.

## Umgesetzt: 0.10.0 – Standort-Privatisierung, Transit Spark auf echten Geräten & Qualitätssicherung

> Status: v0.10.0 ist in Vorbereitung (Build 43, 07.11.2026) und die
> **erste Fassung für den Play Store** – das Play-Console-Projekt wird
> erst angelegt. Zuletzt veröffentlicht wurde v0.9.1 (Prerelease auf
> GitHub); intern wird v0.9.2 getestet. Der Stand ist unten bei den
> Nachträgen festgehalten.
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
- [x] **Folge des Contract-Schritts prüfen** – Migration 138 macht
      **jede** bereits gebaute App unbrauchbar, die `city` oder
      `location_*` aus `profiles` liest. Das ist kein Absturz, sondern
      ein stillschweigend fehlgeschlagener Profilabgleich – die schlimmste
      Fehlerform, weil niemand etwas meldet. Vor einem Upload ist zu
      entscheiden, ob eine Mindestversion durchgesetzt wird (z. B. über
      `auth.jwt()->>'ver'` im RPC) oder ob der Play-Zwang genügt.
      > **Umgesetzt (Migration 156):** `min_app_version_build` steht jetzt
      > auf **31**. Build 30 fragt die in Migration 138 entfernten Spalten
      > ab und bekommt deshalb einen Fehler – der Profilabgleich blieb
      > stillschweigend unvollständig. Build 31 ist der erste Stand, der
      > die Verifikationssperren, die Transit-Merkmale und das
      > Datenschutz-Modell kennt. Ältere Clients bekommen jetzt den
      > Update-Hinweis beim Start.
- [x] **BLE-Gerätetest als HARTER Release-Blocker** – Transit Spark gilt
      erst als stabil, wenn Reichweite, Advertise-Abdeckung und der
      komplette Match-Flow auf MINDESTENS 2 echten Geräten verschiedener
      Android-Hersteller erfolgreich durchlaufen. Simulator und Emulator
      zählen nicht (kein echtes Advertising, keine realistische
      Reichweite, kein Funkrauschen). Der in 0.9.0 als „Gerätetest
      ausstehend" vermerkte Punkt bleibt bis dahin offen – er ist kein
      Nice-to-have, sondern Abnahmekriterium. **Durchsetzung: siehe
      Statusblock oben.** Protokoll: `docs/BLE-GERAETETEST.md`
      > **BESTANDEN (10.11.2026):** Der Betreiber hat den Transit-Spark-
      > Test auf echten Geräten erfolgreich durchlaufen und als Erfolg
      > gemeldet. Damit ist die Release-Bedingung für 0.10.0 erfüllt und
      > die Notbremse (`transit_spark_enabled`) bleibt auf `true` - sie
      > ist die Rückfallebene, nicht der Normalzustand.
      > Den Test selbst kann die Entwicklung nicht ausführen (er braucht
      > zwei echte Geräte); das Ergebnis ist deshalb als Meldung des
      > Betreibers festgehalten, nicht als eigene Messung.
      > **Notbremse ist jetzt vorbereitet (Migration 159):** Der im
      > Statusblock geforderte Schalter in `app_config` existiert:
      > `transit_spark_enabled`. Auf `false` gesetzt ist Transit Spark
      > serverseitig für alle gesperrt – ohne Deploy und ohne App-Update,
      > weil der Schalter in `transit_spark_adult()` sitzt und damit
      > Radar, Matching und Kontaktversand gemeinsam trifft. Die App
      > fragt den Stand ab und zeigt eine klare Meldung, statt eine
      > Alters-Begründung zu geben, die nicht zutrifft. Der Wert steht
      > im Auslieferungszustand auf `true`.
- [x] **BLE-Tracking-Härtung (Privacy im Funk)** – *vorgezogen, stand vor den
      kosmetischen Punkten, weil die Exposition bereits gegenwärtig für jeden
      Nutzer mit aktivem Transit Spark besteht.*
      **Was die App tatsächlich steuern kann - und das ist umgesetzt**
      (`lib/services/transit_ble_privacy.dart`):
      * **Token-Rotation mit Jitter:** Basis 10 min, Streuung ± 40 %
        (6-14 min). Ohne Jitter wäre der Rotationszeitpunkt selbst ein
        Fingerprint: wer morgens immer zur selben Sekunde startet, ist
        wiederzuerkennen.
      * **Sendepausen mit Jitter:** Advertising-Zyklus 20-45 s. Ein
        durchgehender Sender verrät Anwesenheit, ein unregelmäßiger
        Sender verrät nur, dass dort jemand ist, der Transit Spark
        benutzt.
      * **Gepulstes Scanning:** 12 s an, 8-20 s aus. Ein Dauer-Scanner
        erzeugt ein eigenes, wiedererkennbares Muster.
      * **Frisches Token bei jedem Neustart des Advertising** (03.11.2026):
        nach dem Hintergrund wurde mit demselben Token weitergemacht - wer
        das Gerät eine Stunde lang ausgeschaltet hatte, sendete danach
        denselben Pseudonym-Token wieder; das ist genau die Kontinuität,
        die ein Beobachter sucht.
      * **Zufall aus `Random.secure`**, nicht aus `Random()`: ein
        vorhersagbarer Jitter ist schlimmer als gar keiner, weil er ein
        Muster verspricht, das keines ist.
      **Was die App NICHT steuern kann - und das ist keine offene
      Aufgabe, sondern eine Eigenschaft der Plattform:** Resolvable
      Private Addresses rotieren auf Android als Plattformverhalten.
      Eine App kann die Adresse ihres eigenen Advertising nicht erzwingen,
      und `flutter_blue_plus` bietet dafür keine API. Der Eintrag wird
      deshalb ausdrücklich **nicht** als „RPA umgesetzt" verbucht: die
      Rotation der Adresse selbst liegt bei Android, nicht bei uns. Was
      wir tun, ist die darüberliegende Schicht (Pseudonym-Token statt
      Gerätekennung) so zu gestalten, dass ein Beobachter keine
      Kontinuität herstellen kann, auch wenn die Adresse rotiert.
      Der verbleibende Teil ist **nicht** bei uns, sondern beim Gerät:
      der BLE-Gerätetest (siehe oben) muss zeigen, dass die Kombination
      auf echten Geräten funktioniert.
- [x] **Dependency-Hygiene in CI** – erledigt: `flutter pub outdated`- und
      CVE-Prüfung je Pipeline-Lauf, exakte Pins für alle 16
      sicherheitsrelevanten direkten Abhängigkeiten (kein `^` für
      Anything mit Sicherheitsverhalten), SBOM (CycloneDX) für die
      F-Droid-Einreichung, zentral gepinnte Tool-Versionen in
      `tool/requirements.txt`. CI-Jobs: `dependency-audit` und
      `static-checks`
- [x] **Öffentliches Threat-Model** – fertig: [passkey-assets/threat-model.md](passkey-assets/threat-model.md).
      Benennt Vertrauensgrenzen, Angriffsflächen (RLS/`SECURITY DEFINER`,
      Jugendschutz, BLE-Metadaten, Standort, E2E-Irrtum, Lieferkette,
      Moderation/Drittland, Authentifizierung), die Maßnahmen und – ohne
      Beschönigung – die Restrisiken. `SECURITY.md` und die
      Datenschutzerklärung verweisen darauf. `SECURITY.md` selbst war
      bereits öffentlich und nennt `security@thestia.de`
- [x] **Incident-Response mit 72-Stunden-Uhr (Art. 33 DSGVO)** –
      fertig: das betriebliche Ablauf-Dokument liegt lokal beim Betreiber
      (bewusst nicht im öffentlichen Repository).
      Rollen, Triage in 4 h, Schweregrade mit Fristen, konkreter
      Reaktionsablauf (Eindämmen vor Ursachenanalyse, Sitzungswiderruf),
      Umgang mit kompromittiertem Signing-Key und Firebase-Key, Nachbereitung
      mit Pflicht zur Konsequenz
- [~] **Datenschutzfolgeabschätzung (Art. 35 DSGVO)** – fachlich
      erstellt (liegt lokal beim Betreiber, **als Entwurf markiert**).
      Nicht rechtsgeprüft. Enthält Rechtsgrundlagen je Verarbeitung,
      Risikobewertung und – für Minderjährige – fünf zusätzliche
      Vorkehrungen. **Offen und nicht wegformuliert:** neun Punkte in
      Abschnitt 7, darunter Mindestalter, Auftragsverarbeitungsverträge
      je Anbieter, Art. 22 für den Matching-Score, Widerspruchsverfahren
      bei Altersablehnung, Bewertung der Krisen-Erkennung als
      Nicht-Medizinprodukt. Vor dem Launch rechtlich zu prüfen
- [x] **Mindestalter: 16 Jahre – verbindlich festgelegt**
      (Betreiberentscheidung 03.11.2026: "Die App ist keinesfalls für
      unter 16 jährige gedacht!").
      * **Unter 16 ist die App nicht gedacht und nicht zugänglich.**
        Durchgesetzt wird das an drei Stellen, nicht nur in der Anzeige:
        die Altersprüfung im Registrierungsformular
        (`lib/utils/validators.dart`, Mindestalter 16), der
        Datenbank-Constraint `chk_profiles_birth_date_age`
        (Migration 154 – auch ein manipulierter Client kommt nicht
        daran vorbei) und die serverseitige Verifikation, deren
        Altersannahme nie unter 16 liegt.
      * **BLE-Nahbereich (Transit Spark) für unter 18-Jährige
        abgeschaltet:** serverseitig erzwungen, nicht nur im Gerät
        (`transit_spark_adult()`, Migration 131; zusätzlich der
        Kill-Switch aus Migration 159).
      * **Live-Board und Same-Train-Matching für Minderjährige:** die
        Funktionen sind nicht gebaut (Web-Bridge, geplant ab v0.12.0).
        Für 16- und 17-Jährige gibt es sie damit ohnehin nicht.
      * Für 16- und 17-Jährige gilt die Elternaufsicht (Abschnitt
        unten): Zustimmung der Sorgeberechtigten, freie Wahl des
        Kindes, jederzeitiger Widerruf, Entscheidung mit 18.
      * **Offen bleibt die rechtliche Prüfung** (siehe DSFA Abschnitt 7):
        Form und Nachweis der Einwilligung, die Einwilligungsfähigkeit
        ab 16 nach § 3a JUG und die Abgrenzung zu Art. 8 DSGVO.
- [x] **Vorstellungs-Vorlagen (Text + Audio)** – erledigt in 0.10.0.
      Der Text-Teil war schon in 0.9.2 fertig (rotierende Prompt-Karten
      aus vier Themen, `lib/data/intro_prompt_catalog.dart`; ein Tipp
      hängt den Einstiegssatz an, Freitext bleibt erlaubt). Der
      Audio-Teil ist neu: `lib/widgets/intro_recording_guide.dart`
      begleitet die Aufnahme mit drei Winkeln in fester Reihenfolge
      (Wer bist du? / Was macht dich aus? / Warum bist du hier?). Die
      Schritte laufen von selbst (alle 15 Sekunden ein neuer Winkel),
      ein Tipp auf einen Schritt übernimmt dauerhaft die Steuerung, und
      nach dem dritten Schritt bleibt der dritte stehen. Der Leitfaden
      ist eine Stütze, kein Fragebogen – Pflicht bleibt Text UND Audio.
      Kleines Feature, aber es hebt die Profilqualität der frühen
      Nutzerschaft direkt, solange das Match-Erlebnis noch ohne Stimmen
      auskommt

- [x] **Suchfilter mit drei echten Modi** – „Entfernung (km)",
      „Bundesland" und „Ganz Deutschland" filtern jetzt auch
      unterschiedlich. Vorher filterten die beiden letzten Modi
      dasselbe: gar nichts – der Bundesland-Vergleich fehlte
      vollständig, und niemand hat es gemerkt, weil die Liste
      plausibel aussah (Migration 169).
- [x] **Suchradius für 16- und 17-Jährige begrenzt** – höchstens 25 km
      oder nur das gleiche Bundesland; „Ganz Deutschland" ist gesperrt
      und wird serverseitig wie 25 km behandelt (Migration 164).
- [x] **Posteingang im Admin-Bereich** - eingehende Mails nach Adresse
      sortiert (Kinderschutz, Support, Datenschutz, Presse), nur
      anzeigen, nicht antworten: es gibt bewusst keinen SMTP-Zugang aus
      der App heraus (Migration 168).
- [x] **Keine Session-Fixierung über einen Deep-Link** - der
      Deep-Link-Filter akzeptiert nur noch den PKCE-Code. Ein
      exportiertes Custom Scheme lässt jede fremde App die Thestia-App
      mit einer fremden Session starten.
- [x] **Akku: das Funk-Radio schweigt im Hintergrund** - das
      BLE-Advertising lief bis zu 45 Minuten im 100-ms-Takt weiter, auch
      wenn die App nicht im Vordergrund war. Ebenso: kein Polling im
      Hintergrund (Transit-Radar, Dating Hour, Quiz), kein Ticker ohne
      Nutzungszeit-Beschränkung, Bildverarbeitung im Isolate.
- [x] **FLAG_SECURE auf allen Bildschirmen** - auch auf dem Bild-Crop.
- [x] **Downloads und Push-Endpunkte werden geprüft** - nur HTTPS und
      nur eigene Hosts.

### Nachtrag vom 06./07.11.2026 (Build 34 bis 41)

Der Test auf echten Geräten hat eine Reihe von Fehlern zutage
gefördert, die alle im Code lagen – dazu die Korrekturen an der
Website.

- [x] **Der Ende-zu-Ende-Chat funktionierte nicht** – der Kernbefund:
      das Feld `type` ist vom Realtime-Client reserviert (er setzt
      `type = 'broadcast'`). Die App las aber `type` und verwarf
      **jede** Signaling-Nachricht – Offer, Answer, ICE-Kandidaten und
      Relay-Weckmeldung. Das Feld heisst jetzt `kind`. Dazu: die
      Answer nach einem Retry konnte die Verbindung nicht mehr
      reparieren, ein verbrauchter PreKey wurde wiederbelebt, ein
      fehlendes Bundle brach den Aufbau ab, und die Diagnose war im
      Store-Build blind (der Betreiber sah nicht, woran es lag).
- [x] **Drei Blocker, live im Emulator gefunden** – nach dem Login
      threw die App einen `CircularDependencyError` und blieb im
      Login-Screen; beim Start geriet sie in einen Fehlerzustand
      („Thestia isn't responding"); der Dialog „Chat-Hintergrund"
      blieb leer – und genau der erscheint beim *ersten* Chat-Besuch.
- [x] **Transit Spark zählte auf Android 16 jedes fremde
      Bluetooth-Gerät als Thestia-Gerät** (über 100 bei höchstens einem
      in der Nähe): die Hersteller-ID `0xFFFF` ist die reservierte
      SIG-Nummer und wird von vielen echten Geräten benutzt, und die
      alte Prüfung las „irgendetwas nach dem Marker" als Token. Ein Token
      ist jetzt **exakt 20 Hexzeichen**.
- [x] **Transit Spark fand auf Android 11 gar keins** – der BLE-Scan
      ist dort nur mit der *genauen* Standortberechtigung erlaubt, und
      die war per `tools:node="remove"` entfernt: Android blockierte
      den Scan still. Die Berechtigung ist jetzt mit
      `maxSdkVersion="30"` deklariert (auf aktuellen Geräten ändert
      sich nichts – dort reicht `BLUETOOTH_SCAN`).
- [x] **Der Standort bleibt ungefähr** – auf Android 11 und älter
      kann die App den genauen Standort technisch bekommen; sie rastet
      ihn deshalb selbst auf das 5-km-Raster, bevor sie ihn speichert
      oder überträgt (auch der Verifizierungs-Standort, der bisher roh
      im Keystore lag). Dazu eine prominente Offenlegung vor der
      Anfrage – Google Play verlangt sie für empfindliche
      Berechtigungen, und die App hatte sie für Kamera und Mikrofon
      schon.
- [x] **14 Haarfarben statt 8** (dunkelbraun, hellbraun, Kupferrot,
      Platinblond, Silbergrau, Salz und Pfeffer) – Migration 184, auf
      dem Produktivsystem ausgeführt.
- [x] **Die Löschpunkte stehen unten** – „Daten löschen" stand
      mitten in den Einstellungen; beide Löschwege stehen jetzt in
      einer eigenen Gefahrenzone ganz unten.
- [x] **Die Website hat ein Favicon** – in der Google-Suche stand
      neben „Thestia" ein allgemeiner Globus-Knopf statt des Logos.

> **Der BLE-Gerätetest bleibt offen** (siehe oben). Die Notbremse
> (`transit_spark_enabled`, Migration 159) ist vorbereitet und steht
> auf `true`. Sie wird **vor** dem Store-Upload auf `false` gesetzt,
> wenn der Test bis dahin nicht auf zwei echten Geräten
> verschiedener Hersteller durchgelaufen ist.

#### Die Auslieferungs-Hygiene beim ersten echten Store-Upload

Beim Durchgehen der Abnahme vor dem ersten Store-Upload kam heraus,
dass drei Prüfungen nicht das prüften, was sie zu prüfen vorgaben:

- [x] **Die Release-Abnahme zeigte auf den falschen Ordner.** Sie
      stand fest auf `releases/v0.9.2`. Die Abnahme von v0.10.0 hätte
      die Dateien von v0.9.2 geprüft und "alles in Ordnung" gemeldet.
      Der Ordner folgt jetzt der Version aus `pubspec.yaml`.
- [x] **Das AAB wurde überhaupt nicht geprüft** - und genau das AAB
      geht in den Play Store. Es wird jetzt gelesen (Manifest aus
      dem Bundle) und mit den APKs verglichen: versionCode,
      versionName und Berechtigungen.
- [x] **Die Abnahme hätte den richtigen Build abgelehnt.**
      `ACCESS_FINE_LOCATION` stand auf der Verbotsliste, obwohl
      Android 11 und älter die genaue Berechtigung für den BLE-Scan
      verlangen. Die Regel lautet jetzt: nur mit `maxSdkVersion=30`.

> **Und die Begründungen für die Play-Formulare liegen fertig vor:**
> `releases/v0.10.0/PLAY-BEREECHTIGUNGEN.md` (Berechtigungen,
> Data Safety, Zielgruppe) - zum Kopieren in die Console. Jede
> Angabe ist am Artefakt geprüft, nicht am Buildskript.

#### Build 39: der Betreiber testete eine alte Datei

Der Betreiber meldete am 07.11.2026, die Überschrift in der
Merkmals-Auswahl stehe "noch immer" in der Statusleiste – und
fragte: "Sind die APKs veraltet?" **Ja.** Die Admin-APKs im
Release-Ordner waren Build 33 vom 06.11. 19:00, der Fix steckte im
Build 38. Es war also kein offener Fehler, sondern ein alter Build.

Damit das nicht wieder passiert, sind drei Dinge dazugekommen:

- [x] **Die Versionsfußzeile zeigt die Build-Nummer** ("Version 0.10.0
      (39)"). Vorher stand dort nur "Version 0.10.0" - beide Dateien
      hießen gleich, und es gab nichts zu vergleichen.
- [x] **Der Admin-Build hat eine eigene Build-Nummer** (Basis + 9000,
      z. B. 9039). Er ist auf dem Gerät erkennbar und lässt sich über
      dem öffentlichen Build installieren.
- [x] **Das Release-Gate behandelt einen veralteten Admin-Build als
      Fehler**, nicht als Warnung - und prüft die Build-Nummer der
      Admin-APK gegen die des öffentlichen Builds.

Und der Fehler selbst ist abgesichert: ein Test öffnet die
Merkmals-Auswahl über den Weg, den die App geht, und misst, wo die
Überschrift landet. Ohne den `useSafeArea` landet sie **in** der
Statusleiste - der Test schlägt dann an.

#### Build 40: der Match war mit genau zwei Geräten unmöglich

Der Betreiber meldete am 07.11.2026: „Beide Geräte suchen eine Person
bei Transit Spark (Beide haben gleiche beschreibung und beide haben
sich gegenseitig blicke getauscht/gefunkt, aber gibt keinen Funken.)"

**Das war kein Bedienfehler, sondern ein Bug in der Kernfunktion.**
Das Signal enthielt die Tokens der *gesehenen Geräte*, nicht den
eigenen Token des Absenders – und gesucht wurde mit genau diesen
Tokens. Zwei Personen, die nur einander sehen, haben disjunkte
Token-Mengen: **mit genau zwei Geräten konnte die Bedingung nie
erfüllt werden.** (Belegt an den echten Signalen des Betreibers: zwei
`pending`-Signale, 16 Sekunden auseinander, gleiche Beschreibung,
keine gemeinsamen Tokens.)

- [x] **Der eigene Token wird mitgeschickt** (Migration 185) und in
      einer eigenen Spalte gespeichert. Damit lässt sich die Frage
      stellen, die die Sache meint: *HAT DER ANDERE MICH GESEHEN?* –
      denn der eigene Token des anderen steht in dessen
      Sichtungsliste, wenn der andere mich gesehen hat. Die Bedingung
      wird symmetrisch, und der Match ist an die Identität gebunden:
      zwei Personen, die nur dasselbe dritte Gerät gesehen haben,
      matchen nicht mehr.
- [x] **Die Migration enthält einen Selbsttest**, der den Fall des
      Betreibers nachstellt – und den Falschtreffer. Er läuft in einem
      SAVEPOINT und wird zurückgerollt; bricht er ab, wird die
      Migration nicht ausgerollt.
- [x] **Ohne den eigenen Token wird gar nicht erst gesendet.** Ein
      Versuch ohne ihn kann keinen Match finden und würde den Nutzer
      mit einem stillen „kein Match" im Glauben lassen, es sei niemand
      in der Nähe.
- [x] **18 Haarfarben** (Migration 186) – lila, rosa, blau, grün sind
      dazu gekommen. Und ein Werkzeug (`tool/check_transit_catalog.py`),
      das prüft, dass App und Server dieselben Merkmale kennen: ein
      Wert, den der Server nicht kennt, wird beim Senden
      **stillschweigend weggefiltert** – der Nutzer wählt ihn, er
      verschwindet, und der Funke kommt nie.
- [x] **Die Chat-Hintergrund-Auswahl muss nicht mehr gescrollt
      werden** (die feste Höhe 280 zeigte nur zwei von drei Reihen),
      und **die Haarfarben liegen in einem Raster statt in einer
      Reihe**, mit dem Namen der gewählten Farbe daneben.

> **Der Server kennt neun Merkmale, die die App nicht anbietet**
> (`ausweis`, `brille`, `hair_length`, `hair_style`, `helm`,
> `kopfhoerer`, `rucksack`, `sandalen`, `sportlich`). Das ist kein
> Fehler - aber `hair_length` und `hair_style` wären die logische
> Ergänzung zu den 18 Haarfarben, wenn der Betreiber sie will.

#### Build 46: Transit Spark und Chatten - der zweite Durchgang

BEFUND (07.11.2026, Betreiber, nach dem Test auf zwei echten
Smartphones): sieben Punkte, alle rund um Transit Spark und den Chat.

**1. Nachrichten kamen nicht an - das Relay hat NIE funktioniert.**
Der Aufruf von `relay_store` antwortete mit `HTTP 400 - query has no
destination for result data`. Die Funktion endete mit `RETURNING id;` -
in PL/pgSQL ist das **kein RETURN**. Die Funktion lieferte also keinen
Wert und jeder Aufruf scheiterte. Das heisst: Jede Nachricht, die
ueber den Relay-Weg ging (also immer dann, wenn der Direktkanal nicht
steht), wurde verworfen. (Migration 196.)

**2. Beidseitige Likes erzeugten keinen Funke.** `like_user` legte nur
einen offenen Like an; der Match entstand erst, wenn die Gegenseite
ihn von Hand annahm. (Migration 197.)

**3. „Man kann nicht von einer Person einen Like haben, mit der man
schon einen Funken hat."** Bei einem bestehenden Funke tat `like_user`
nichts - der Like wurde stillschweigend geschluckt. Jetzt gibt die
Funktion das Ergebnis zurueck und die App sagt es.

**4. Das Auge mit dem Strich lehnte ab, statt auszublenden.** Es war
mit „Ignorieren" beschriftet, rief aber das Ablehnen auf - die andere
Person sah die Ablehnung. Jetzt blendet es nur aus (Migration 198).

**5. Der gewaehlte Chat-Hintergrund verschwand.** Das Schreiben in den
Keystore kann scheitern; der Fehler wurde nur protokolliert. Die
Oberflaeche zeigte den Hintergrund trotzdem an - beim naechsten Start
war er weg. Jetzt: dreimal versuchen, und wenn es nicht klappt, wird
es gemeldet.

**6. Die Markierung der gewaehlten Farbe war am Rand abgeschnitten**
(der Schatten ragte nach aussen). Jetzt ist sie ein Rahmen innerhalb
der Kachel.

**7. Beim Wechsel vom Transit Spark in den Chat wird jetzt gefragt**,
ob das Radar anbleiben soll - wie beim Verlassen des
Radar-Bildschirms.

> **Und das Werkzeug gegen diese Klasse:**
> `tool/check_function_returns.py` findet Funktionen, die einen Wert
> zurueckgeben **sollten**, aber kein `RETURN` haben. Der Aufruf
> scheitert dann mit „query has no destination for result data" -
> ohne dass irgendwo ein Fehler sichtbar wird. Der Selbsttest (eine
> absichtlich kaputte Funktion) beweist, dass der Pruefer sie findet.

#### Build 46, Nachpruefung: der Nachrichtenweg bis zum Ende belegt

FRAGE DES BETREIBERS (08.11.2026): „Bist du dir jetzt sicher, dass der
Chat und alle Modi reibungslos laufen?"

Die ehrliche Antwort war: **nein**. Zwei Dinge waren zu dem Zeitpunkt
unbelegt - und eines davon war ein Fehler in meiner eigenen Pruefung:
Der erste Live-Nachweis hat eine **Nutzlast abgelegt, die keine war**
(base64 von „Hallo"). Damit war die Server-Kette belegt, aber **nicht
die Verschluesselung**. Wenn die Krypto kaputt waere, kaemen die
Nachrichten weiterhin nicht an - und genau das war die gemeldete
Symptom.

**Was jetzt belegt ist (live geprueft, nicht vermutet):**

- `test/signal_first_message_test.dart` beweist an den echten
  Bausteinen der Bibliothek: die **erste** Nachricht traegt den PreKey
  und laesst sich **ohne vorhandene Sitzung** entschluesseln. Eine
  unbekannte Person kann die erste Nachricht also ueberhaupt lesen.
- `test/live_prekey_bundle_test.dart` holt das **echte** Bundle eines
  echten Kontos vom Server und prueft die Signatur des Signed Pre
  Keys gegen die Identity-Key. Passt die nicht, kann die App keine
  Sitzung aufbauen und damit **keine** Nachricht verschluesseln -
  ohne dass irgendwo ein Fehler sichtbar wird.
- `test/live_message_flow_test.dart` macht den ganzen Weg in einem
  Lauf: beidseitiger Like -> **Funke** -> PreKey-Bundle holen ->
  Sitzung bauen -> Nachricht verschluesseln -> Relay ablegen ->
  abholen. Die Nutzlast im Relay enthaelt den Klartext nicht.

> **Die wichtigste Lehre:** Mein Verdacht, die Krypto sei kaputt, war
> **falsch**. Der Test hat es widerlegt, **bevor** die App angefasst
> wurde. Genau dafuer ist der Test da: ein Verdacht, der aus einem Test
> kommt, ist eine Vermutung - ein Verdacht, der durch einen Test
> widerlegt ist, ist eine Tatsache.

> **Und die Grenzen, ehrlich benannt:** Der P2P-Direktkanal (Offer ->
> Answer -> ICE) ist auf zwei echten Geraeten **nie** durchgelaufen.
> Ohne TURN kein P2P hinter CGNAT (der Serverweg funktioniert, ist
> aber langsamer). Bild- und Sprachnachrichten sind nicht
> Ende-zu-Ende geprueft. Der Login auf dem Emulator scheitert am
> CAPTCHA, deshalb sind die Bildschirmablaeufe ueber Widget-Tests
> belegt statt ueber eine Sitzung auf einem Geraet. Ausfuehrlich in
> `releases/v0.10.0/TESTANLEITUNG.md`, Abschnitt 7.

> **Das Werkzeug gegen diese Klasse:** `tool/cleanup_transit_testdata.sql`
> raeumt die Testdaten der Live-Nachweise weg (zwei Likes, ein Match)
> und prueft danach, dass nichts mehr da ist. Ohne das bliebe beim
> Betreiber ein Phantom-Funke zurueck - ein Funke, den er nicht
> ausgeloest hat.

#### Build 48: die Sicherheitspruefung gegen bekannte Luecken

FRAGE DES BETREIBERS (08.11.2026): „Check im Internet einmal, ob es
bestimmte Sicherheitsluecken gibt, die Thestia haben koennte und pruef
die App dann darauf."

**Die Methode:** Alle 274 Pakete aus `pubspec.lock` wurden gegen die
OSV-Datenbank (Google) und die GitHub Advisory Database abgefragt, dazu
der WebRTC-SDK, die Flutter-Engine (Skia, libpng), der Dart-SDK, die
GitHub Actions und die Maven-Abhaengigkeiten des Android-Builds. Jede
gefundene Luecke wurde gegen den eigenen Code geprueft.

**Das Ergebnis:** Kein einziges der 274 Pakete ist von einer bekannten
Advisory betroffen. Zwei Luecken waren es - der **Flutter-/Dart-SDK**
und der **WebRTC-SDK im lokalen Fork**.

**Luecke 1 (High, GHSA-frr6-h895-5pxp): der Dart-/Flutter-SDK war zu
alt.** Im Oktober 2026 wurden die privaten Schluessel von acht
Zwischenzertifikaten der CA eMudhra oeffentlich als kompromittiert
gemeldet. Wer sie hat, kann gueltige TLS-Zertifikate fuer beliebige
Domains FAELSCHEN. `dart:io` prueft auf Android mit einem eingebauten
BoringSSL und liest die Sperrliste des Betriebssystems NICHT - ein
Angreifer im Netzpfad kann also ein gefaelschtes Zertifikat fuer
`*.supabase.co` vortaeuschen. Betroffen: Flutter < 3.47.8, Dart <
3.13.7. Thestia hatte 3.44.6 / 3.12.2.

**Die App-Pruefung:** Drei Datenpfade liefen ungeschuetzt - Supabase
**Realtime** (WebSocket), die Passkey-Registrierung und der
Storage-URL-Download. Sie gingen ueber den System-Root-Store, und Dart
ruft den Pin-Callback nur auf, wenn die System-Validierung
**fehlgeschlagen** ist: ein vom System akzeptiertes Zertifikat umging
das Pinning also vollstaendig. Behoben: alle drei laufen jetzt ueber
den **gepinnten** Client mit leerem Root-Store (fail-closed). Supabase
REST und das WebRTC-Signaling waren bereits gepinnt; Play Integrity
und FCM laufen nativ und nutzen den Trust-Store des Betriebssystems.

**Luecke 2 (Medium): der WebRTC-SDK im lokalen Fork.** `flutter_webrtc`
ist in Thestia kein Pub-Paket, sondern ein Fork. Er zog den nativen
WebRTC-SDK aus Maven: `144.7559.09` - mit der kompromittierten
eMudhra-CA noch in der eigenen CA-Liste. Behoben: jetzt `150.7871.04`,
exakt die Version des Upstream-1.6.3 („drop compromised eMudhra CA
root").

> **Das Werkzeug, das die Klasse fängt:**
> `tool/check_sdk_security.py` haelt die Sicherheitsuntergrenzen fest
> (SDK-Version der CI, lokal installierte Version, WebRTC-SDK) und ist
> blockierend im CI. Ein Rueckfall auf eine alte SDK-Version wird rot,
> statt stillschweigend zu passieren. Das vollstaendige Audit mit allen
> Quellen liegt in `docs/SICHERHEITSPRUEFUNG-2026-11-08.md`.

#### Build 46, Nachpruefung II: eine Benachrichtigung pro Ereignis

BEFUND (08.11.2026, Betreiber): „Keine doppelten Benachrichtigungen fuer
das Selbe."

**Die Ursache (live gemessen, nicht vermutet):** Der Like-Versand lief
**zweimal** - einmal ueber den DB-Trigger (`notify_push_trigger`) und
einmal ueber einen Aufruf der App (`notify-user` mit `kind='likes'`).
Dazu kam der Transit-Weg: der legt fuer EINEN Funke drei Zeilen an
(zwei technische Likes, ein Match, ein Soft-Ping) und erzeugte damit
**vier** Push-Aufrufe. Beide Seiten bekamen je **zwei** Meldungen fuer
ein Ereignis - und die Like-Meldung war inhaltlich falsch, denn im
Radar wird kein Profil geliked, sondern gefunkt.

**Das Werkzeug, das diese Klasse fängt:**
`tool/measure_push_duplicates.sql` zaehlt die Push-Aufrufe, ohne dass
eine einzige Nachricht rausgeht: die Zaehlung laeuft in einer
Transaktion, und der pg_net-Worker sieht uncommittete Zeilen einer
anderen Sitzung nicht. `tool/check_push_duplicates.py` macht daraus ein
Gate (statisch: kein Client darf `notify-user` mit `kind='likes'` rufen;
live: die vier Szenarien mit der Soll-Zahl), mit einem Selbsttest, der
alle vier Fehlerquellen nachbaut.

**Die Regel ab jetzt: ein Ereignis, eine Meldung.**

- Ein technischer Transit-Like erzeugt keine Meldung
  (`likes.source = 'transit'`).
- Ein Like, aus dem ein Funke wird, erzeugt nur die Funke-Meldung -
  der Match entsteht darum vor dem Like-Insert.
- Ein Soft-Ping zu einem bestehenden Funke erzeugt keine Meldung (der
  Ping bleibt fuer den Radar sichtbar).
- `notify-user` lehnt Like-Pushes von Clients ab (HTTP 400,
  `kind_server_only`) - der Like-Versand ist Sache des Servers.

**Live gemessen:** Transit-Funke 4 -> 2 (je einer pro Seite),
einseitiger Profil-Like 2 -> 1, gegenseitiger Like 4 -> 2, manueller
„Zuzwinken" 0 -> 1 (der Trigger war seit der Secret-Umbenennung in
Migration 146 tot).

#### Build 44: der Funke erzeugt jetzt einen echten Funke

BEFUND (07.11.2026, Betreiber, nach dem Test auf zwei echten
Smartphones): „Der Funke entsteht, aber es ist nichts sichtbar.“ Und
danach: „Funke wurde angezeigt, ist dann aber wieder verschwunden.“

**Die Ursache** (live gelesen, nicht vermutet): Ein Match entsteht
ausschliesslich durch einen INSERT in `public.matches` - den macht
**nur** `create_match_if_mutual`. Der direkte Client-INSERT ist seit
Migration 040 per RLS gesperrt.

Transit Spark legte aber **nur Likes** an (`match_proximity_spark` und
`accept_soft_ping`). Keine der beiden Funktionen ruft
`create_match_if_mutual` auf - und kann es auch nicht: sie setzen fuer
**beide** Seiten die Likes, ohne dass ein Client-Hook laeuft.

*Die Likes sind fuer die App unsichtbar:* Die Chatliste liest aus
`matches`, nicht aus `likes`. Der Funke „entstand“, aber er erschien
nirgends.

- [x] **Die Paarung legt den Match selbst an** (Migration 194) - mit
      denselben Regeln wie `create_match_if_mutual`, also bleibt es bei
      **einem** Match je Paar.
- [x] **Die Annahme liefert die `match_id`** - damit fuehrt der
      Chat-Knopf direkt in den neuen Chat.
- [x] **„Ausblenden“ fragt vorher nach.** Vorher hat der Knopf die
      Zeile unwiderruflich geloescht, ohne Rueckfrage - und er sitzt
      genau dort, wo der Finger schon liegt, wenn die Liste gerade
      gewachsen ist.
- [x] **Das Aufräum-Werkzeug räumt nur auf, was es selbst angelegt
      hat** (Vorher-Nachher-Vergleich) und **bricht ab**, wenn
      zwischen den Testkonten schon etwas liegt.

- [x] **Der Geburtstag wird in der Zeitzone des Betrachtenden gerechnet**
      (Migration 195). Der Server rechnete in UTC, die App lokal -
      zwischen 22:00 UTC und Mitternacht sah der Nutzer seinen
      Geburtstag, die andere Person aber nicht. Und die App meldet ihre
      Zeitzone jetzt bei **jedem Start** (bisher nur der Elternbereich),
      weil sie sich mit dem Reisen aendert.

> **Und die ehrliche Lehre daraus:** Der erste Teil des Befunds war
> **mein Verschulden** - das Aufräum-Skript hat die Testdaten des
> Betreibers mitgelöscht, weil es pauschal alles zwischen den beiden
> Testkonten im Zeitfenster löschte. Ein Werkzeug, das in der
> Produktivdatenbank schreibt, muss genau das tun, was es behauptet:
> nur seine eigenen Zeilen zurückräumen.

#### Build 43: die Vorstellung, der Funke und die Rechte

BEFUND (07.11.2026, Betreiber): 13 Meldungen auf zwei echten Geräten.
Diese Runde hat **fünf** davon behoben - und vor allem die Fehler
gefunden, die man auf dem Gerät **nicht** sehen kann.

**1. Die Vorstellung war in der Datenbank, aber nicht in der App.**
„Meine Vorstellung stimmt auch nicht, da beide Nutzer eine Vorstellung
gemacht haben aber hier steht, dass keine hinterlegt wurde."

Live geprüft: Text und Audio-Datei waren vorhanden. Der Fehler lag im
Client: `UserProfile.fromJson` bedient drei Quellen mit drei
Schreibweisen und kannte nur eine. Beide Parser lesen jetzt alle.

**2. Die Vorstellung ließ sich nicht abhören.** `await _player.play()`
wartet bei just_audio, bis die Aufnahme **zu Ende** ist - die ganze
Abspielzeit blieb der Lade-Spinner stehen. Dieselbe Falle an drei
Stellen; alle behoben, plus ein Zeitlimit statt eines endlosen
Spinners.

**3. Der Funke war für die Gegenseite unsichtbar.** Die Paarung
meldete den Treffer nur dem Absender. Jetzt legt sie für die Gegenseite
einen Soft-Ping an - der Eingang pollt alle 15 Sekunden.

**4. Zwei Funktionen, die der Server nicht ausführen durfte.**
„Entblockieren" und „Annehmen" antworteten mit `403 permission denied`:
beim Rechte-Widerruf (Migration 123) war das Ausführungsrecht für
`authenticated` vergessen worden. Zwei Minuten Testen auf dem Gerät
hätten das nie gezeigt - der Server sagt es nur, wenn man ihn fragt.

**5. Der Zufallschat verlor Nachrichten**, weil er ausschließlich über
den P2P-Kanal sendete. Jetzt: P2P, dann E2E-Relay, dann Outbox.

> **Die Werkzeuge, die diese Klasse fangen:**
> * `tool/check_function_grants.py` - sammelt alle RPC-Aufrufe des
>   Clients und fragt die Produktivdatenbank nach den Rechten. Hat
>   `unblock_user` und `accept_soft_ping` gefunden.
> * `tool/check_profile_cache_keys.py` - vergleicht, was der Cache
>   schreibt, was die Parser lesen und was die Server-Zuordnung kennt.
>   Hat die Vorstellung gefunden.
> * `tool/check_on_conflict.py` - findet Konflikt-Ziele, die kein Index
>   trägt (der Dating-Hour-Bug).
> * `tool/check_migration_history.py` - findet Migrationen, die als
>   „angewandt" markiert sind, aber nicht vollständig gelaufen sind.
> * `tool/check_release_version.py` - findet die alte APK im
>   Release-Ordner.

> **Die Lehre daraus (und die Antwort auf die Frage des Betreibers,
> warum es immer neue Probleme gab):** Die Fehler der letzten Wochen
> waren fast alle **stille** - kein Absturz, keine Fehlermeldung, nur
> ein leeres Feld oder eine alte Datei. Sie fielen nur auf, wenn man
> genau hinsah. Ein Test prüft den Quelltext; er prüft nicht, was der
> **Server** daraus macht und nicht, was in der **Release-Datei**
> steckt. Deshalb prüfen diese Werkzeuge beides: gegen die
> Produktivdatenbank und gegen das ausgelieferte Artefakt.

#### Build 42: Dating Hour - die Partner konnten sich nie finden

BEFUND (07.11.2026, Betreiber): „Bei Dating Hour finden sich die
Partner nicht (zwei user drin (meine geräte)) und es passiert nichts.
Es steht, dass die sich suchen, aber finden niemanden."

**Die Ursache** (live geprüft, nicht vermutet): Die Paarungsrunde
sagte `ON CONFLICT (event_id, user_a, user_b) DO NOTHING` - der
Unique-Index lautet aber `… WHERE (ended_at IS NULL)`. Ein
**partieller** Index trägt ein `ON CONFLICT`-Ziel nur, wenn die
Bedingung **genau dieselbe** ist; sonst antwortet der Server mit
`42P10`. **Die Paarungsrunde konnte also nie eine Sitzung anlegen.**
Im Cron-Log fällt so etwas nicht auf - der Cron lief alle 30 Minuten,
und in der App sieht man nur „sie suchen sich" und wartet.

Dazu kam, dass der Cron alle **30** Minuten lief, das Event aber nur
**60** Minuten dauert: wer in der ersten halben Stunde beitritt,
bekam keine Runde mehr.

- [x] **Das `ON CONFLICT`-Ziel trägt die Bedingung des partiellen
      Index** (Migration 190). *Nachgewiesen:* Vorher 2 Teilnahmen und
      0 Sitzungen, nach der Reparatur erzeugt derselbe Aufruf eine
      Sitzung.
- [x] **Der Cron läuft alle 5 Minuten** statt alle 30 (Migration 189).
- [x] **Die App löst die Paarungsrunde nach dem Beitritt selbst aus** -
      damit entsteht die Sitzung sofort, ohne auf den Cron zu warten.

> **Und derselbe Fehlertyp steckte noch an einer zweiten Stelle:**
> `register_chat_image_hash` schrieb in `public.chat_image_hashes` -
> **die Tabelle gab es nicht**. Migration 068 hatte sie angelegt, war
> aber beim Anwenden gescheitert; die Historie wurde trotzdem
> fortgeschrieben, und Migration 108 legte die Funktion neu an und
> verwies auf die Tabelle. Damit sah alles fertig aus, aber der
> **Bild-Missbrauchsschutz** aus der Datenschutzerklärung hat nie
> gearbeitet: jede Meldung eines Chat-Bildes schlug mit „relation
> does not exist" fehl. Migration 190 legt die Tabelle nach.

> **Das Werkzeug, das beides gefunden hat:**
> `tool/check_on_conflict.py` fragt die Produktivdatenbank ab und
> vergleicht **jedes** `ON CONFLICT`-Ziel mit den tatsächlichen
> Indizes - es sieht alle 26 Funktionen auf einmal. Dazu
> `tool/check_migration_history.py` (jede Migration aus dem
> Repository ist auch angewandt) und `tool/check_release_version.py`
> (die ausgelieferten Artefakte tragen den aktuellen Code).

#### Build 41: Haarlänge, Frisur - und ein Redesign des Bildschirms

BEFUND (07.11.2026, Betreiber): "Ja kannst du auch mit aufnehmen,
also Hairstyle und so. Aber bitte gut umsetzen auf der Seite, da es so
schon echt voll ist, braucht es schon fast ein Redesign vom wie siehst
du aus screen."

Der Server kannte `hair_length` und `hair_style` schon - aber als
blosse Merkmale waren sie wertlos ("hat Haarlaenge?"). Migration 187
gibt dem Katalog deshalb eine **Werteliste**: neben "slug" (Ja/Nein)
und "slug:farbe" gibt es jetzt "slug:wert" ("hair_style:lockig"). Die
App bietet **7 Haarlängen** (kurz, schulterlang, mittellang, lang,
sehrlang, bis zur Schulter, Stoppeln) und **8 Frisuren** (glatt,
lockig, gewellt, kraus, geflechtet, Zopf, Pferdeschwanz, kurz
geschnitten) an.

**Das Redesign:**

- [x] **Die Haare stehen oben.** Vorher standen sie ganz hinten (nach
      Ober- und Unterteil) - der Bildschirm heisst aber "Wie siehst du
      gerade aus?", und was man im Gesicht sieht, kommt zuerst.
- [x] **Der Kategorie-Filter ist ein Chip mit Menü** statt eines Bandes
      aus acht Chips. Er hat eine ganze Bildschirmzeile gebraucht und
      nur wiederholt, was die Gruppierung unten schon zeigt.
- [x] **Die Werte stehen direkt unter dem Merkmal**, das sie brauchen -
      nicht in einer eigenen Liste weiter unten.
- [x] **Ein Fortschrittsbalken** zeigt, wie viele Merkmale noch
      fehlen (mindestens zwei, höchstens acht).
- [x] **Die Kategorie-Ueberschrift entfaellt bei einer Kategorie mit nur
      einem Merkmal.** Vorher stand "Frisur" zweimal auf dem Bildschirm:
      als Kategorie und als Merkmal.

> **Zwei Fehler, die der neue Test gefunden hat** - und die man beim
> Testen auf dem Geraet nicht gesehen haette:
> * **Haarlaenge und Frisur schlossen sich aus.** Je Kategorie ist nur
>   *ein* Merkmal erlaubt (sonst koennte jemand "Hemd" UND "Bluse"
>   waehlen). Beide lagen aber in der Kategorie `hair` - man konnte also
>   nur eines von beiden angeben. Migration 188 gibt ihnen eigene
>   Kategorien.

### Elternfreigabe und Aufsicht für 16- und 17-Jährige (Teil von 0.10.0)

> **Status: umgesetzt in v0.10.0 (03.11.2026).** Aufgeschrieben am
> 24.10.2026 auf Wunsch des Betreibers, umgesetzt am 03.11.2026.
> Der Wunsch ist klar: 16- und 17-Jährige sollen die App nutzen können –
> mit Zustimmung der Eltern, die die App herunterladen und dem Kind zur
> Verfügung stellen. Eine Weitergabe an Personen, die nicht geeignet sind
> (etwa unter 16-Jährige), ist in keinem Fall erlaubt.
>
> **UMGESETZT (in v0.10.0):** Migrationen 165 (Freigabe, Audit-Trail,
> Digest-Trigger, Cron), 166 (Portal-Status), 167 (Änderungen nur mit
> PIN); Edge Functions `guardian-consent` und `guardian-digest`;
> Eltern-Portal unter `auth.thestia.de/eltern`; App: Freigabe-Screen nach
> dem Willkommens-Screen, Einstellungsabschnitt „Kinderschutz &
> Elternzugriff", Übergangs-Screen mit 18, PIN-geschützte Nutzungszeit.
>
> Dieser Block hält fest, was das rechtlich und technisch bedeutet, was
> Google Play zulässt und was es nicht zulässt. Er ist eine
> Entscheidungsgrundlage, kein Umsetzungsplan.

### 1. Was Google Play zulässt – und was nicht

Die maßgebliche Regel ist die „Age-Restricted Content and Functionality"
im Developer Programme Policy. Sie kennt **zwei** Fälle:

1. **„Apps whose core functionality is to facilitate matchmaking or
   dating."** → Diese Apps **müssen** Play-Werkzeuge benutzen, um
   Minderjährige auszusperren (Restrict Minor Access, Zielgruppe 18+).
   Eine Ausnahme gibt es hier nicht.
2. **„Apps where matchmaking or dating is an incidental feature are not
   required to block minors, provided that they implement appropriate
   age-verification safeguards to prevent minors from accessing those
   specific features."** → Nur wenn die Begegnungsfunktion **nicht** der
   Kern der App ist. Dann genügt ein belastbarer Altersnachweis, statt
   die Minderjährigen komplett zu sperren.

Thestia ist eine Dating-App mit Dating-Kern → **Fall 1**. Die
Eltern-Einwilligung öffnet den Play-Kanal also **nicht** für 16-Jährige.
Das ist keine Auslegungsfrage und keine Verhandlungsposition: Play hat
das in der Policy formuliert, und der Support hat es am 24.10.2026
bestätigt (es gibt keine Vorab-Prüfung, nur die reguläre Prüfung bei
Einreichung).

Interessant für das technische Design ist trotzdem Fall 2, denn Play
formuliert dort die Anforderung, an der sich das Modell messen lassen
muss: *„It is your responsibility to ensure that your age-gating
mechanism is robust and effective. Simple age gates that can be easily
circumvented may not be considered reasonable."* Ein einfaches Häkchen
„ich bin 16“ wäre also weder für Play noch für den Jugendschutz
ausreichend. Genau das ist der Maßstab, an dem unten entworfen wird.

**Folge für die Verteilung:**

- **Play-Kanal:** Zielgruppe 18+, Restrict Minor Access aktiv. Die
  16+-Pfade sind im Play-Build nicht erreichbar. Ob die F-Droid-Variante
  (eigener Build ohne Firebase/Play Integrity) neben dem Play-Build
  vertrieben werden darf, ist eine Rechtsfrage, die vor einer
  Entscheidung juristisch zu klären ist – hier steht sie offen.

- **Nicht-Play-Kanäle:** Dort gilt nicht die Play-Policy, sondern das
  deutsche Recht. Das ist der Ort, an dem das Modell unten seinen Sinn
  hätte.
**ENTSCHEIDUNG 05.11.2026: Der 16+-Pfad bleibt (bewusst).**

Bei der Bestandsaufnahme vom 05.11.2026 (siehe
`docs/MINDERJAEHRIGE-NUTZUNG.md`) wurde die Frage gestellt, ob der
Minderjährigen-Pfad (Elternfreigabe, Nutzungszeit, Aufsicht) ganz
entfernt werden soll. Entscheidung: **er bleibt.** Begründung:

- Die technische Absicherung für 16- und 17-Jährige ist vollständig
  und serverseitig erzwungen (Altersgrenzen, Sichtbarkeitsregeln,
  Suchradius, keine Entfernungsanzeige, Transit Spark ab 18, Audit-Trail).
  Sie wird auch für die Verifikation von Erwachsenen gebraucht.
- Der Parentschutz ist ein Verkaufsargument gegenüber Familien, und die
  Elternseite (`/eltern`) erklärt ihn ausführlich.
- Der Aufwand des Entfernens (rund 25 Dateien, zwei Migrationen, zwei
  Edge Functions, Website und Store-Text) steht in keinem Verhältnis zu
  einem Nutzen, solange der **Play-Kanal** die 16+-Pfade ohnehin nicht
  ausliefert.


**Die Store-Frage ist entschieden (05.11.2026):** Das Listing nennt
beides, ohne zu verschweigen, dass es zwei Kanäle gibt:

> Im Play Store ab 18 Jahren: Google verlangt für Dating-Apps ohnehin
> eine Altersgrenze von 18. In anderen Kanälen (F-Droid) ist die App ab
> 16 Jahren mit Elternfreigabe nutzbar – für Erwachsene bleiben
> Minderjährige unsichtbar

Damit stimmen Listing und Wirklichkeit überein: der Kanal gibt 18+ her,
die App kann 16+. Eine Invariante (`tool/check_security_invariants.py`)
sichert das ab - schreibt jemand wieder „ab 16 Jahren, mit
Elternfreigabe" ins Listing, schlägt sie an.

**Bleiben würde Weg 2:** den Minderjährigen-Pfad ganz entfernen. Das ist
eine Markt- und Rechtsfrage, keine technische; die technische Umsetzung
steht in `docs/MINDERJAEHRIGE-NUTZUNG.md` (Abschnitt 9).

### 2. Der juristische Anker (Deutschland)

- **DSGVO Art. 8:** Die Einwilligung für Dienste, die sich an Kinder
  richten, bedarf bei Minderjährigen der Zustimmung der
  Sorgeberechtigten; die Mitgliedstaaten dürfen das Alter selbst
  festlegen.
- **§ 3a JUG** (früher § 5 TMG): In Deutschland kann eine Person ab dem
  **vollendeten 16. Lebensjahr** selbst einwilligen. Darunter ist die
  Zustimmung der Sorgeberechtigten erforderlich.

Damit deckt sich das Modell mit dem bestehenden Altersdesign der App
(16 ↔ 16/17 erlaubt, Erwachsene untereinander): Die App müsste also
**zwei** getrennte Nachweiswege haben – einen elterlichen
Einwilligungsweg für 13–15 (nur wenn das überhaupt gewollt wird) und
einen Selbsteinwilligungsweg ab 16. Der Vorschlag des Betreibers deckt
sich mit dem Gesetz für 16 und 17: dort genügt die eigene Einwilligung,
die Zustimmung der Eltern ist freiwillig, aber der **Nachweis** des
Alters bleibt zwingend.

> **Rechtlich prüfen lassen (Medienrecht/Datenschutz), bevor das
> umgesetzt wird.** Dieser Block ist keine Rechtsberatung. Zu prüfen sind
> mindestens: Art. 8 DSGVO, § 3a JUG, die Einwilligungsform, die
> Nachweispflicht des Betreibers, die Frage der Weitergabe des Kontos
> und die Frage, ob eine Dating-App besondere Kategorien personenbezogener
> Daten verarbeitet.

### 3. Technischer Entwurf: was „mit Zustimmung der Eltern" serverseitig heißen muss

Die Anforderung des Betreibers enthält die entscheidende Einschränkung
selbst: **keine Weitergabe an nicht geeignete Personen.** Ein
Einwilligungs-Häkchen im Registrierungsformular wäre wertlos, weil es
sich kopieren ließe. Der Nachweis muss also serverseitig hängen.

**Kernpunkt: Das Konto gehört dem verifizierten Kind, nicht dem
Elternteil.** Der Elternteil ist Genehmiger, nicht Nutzer. Damit ist die
Weitergabe technisch ausgeschlossen: Ein Konto, das einem 16-Jährigen
gehört, wird von einem anderen nicht benutzt – es existiert nur für
diesen einen, verifizierten Menschen.

Vorgesehene Bausteine (noch nicht umgesetzt):

| Baustein | Zweck | Aufwand | Stand |
|---|---|---|---|
| `profiles.supervised` (bool) | Konto steht unter Aufsicht | klein | ✅ Migration 165 |
| `profiles.consent_state` (`none`/`pending`/`granted`/`revoked`) | Stand der Einwilligung, serverseitig | klein | ✅ Migration 165 |
| `profiles.consent_parent_ref` | Verweis auf den Einwilligungsdatensatz, **kein** Konto des Elternteils | klein | ✅ Migration 165 |
| `profiles.consent_verified_at` / `consent_revoked_at` | Nachweiszeitpunkt und Widerruf | klein | ✅ Migration 165 |
| Einwilligungs-Flow (Elternseite) | Eltern bestätigen per Einmal-Link an ihre eigene Adresse; der Link ist an die **konkrete, verifizierte** Minderperson gebunden | mittel | ✅ Eltern-Portal `auth.thestia.de/eltern`, Token nur als Hash gespeichert |
| Widerrufs-Flow | Eltern widerrufen per Link; der Server setzt `consent_state='revoked'` und sperrt die Funktionen | mittel | ✅ Migration 165 |
| Kopplung an die Altersprüfung | Das bestehende Video-Alter entscheidet; die Einwilligung gilt **nur** für das Alter 16/17 und **nur** für dieses Konto | mittel | ✅ `guardian_eligible_age()` - das **verifizierte** Alter |
| Aufsichtsmodus | Eltern können einzelne Funktionen abschalten (BLE/Transit Spark, Zufallschat, Standort) | groß | 🟡 teilweise: Nutzungszeit per PIN gesetzt; das Abschalten einzelner Funktionen ist nicht gebaut |
| Audit-Trail | Jede Einwilligung und jeder Widerruf wird protokolliert (wer, wann, für wen) | mittel | ✅ `guardian_consent_audit` |
| Eltern-Benachrichtigung | Elternteil erfährt, dass ein Funke entstanden ist - ohne Namen, Profile oder Inhalte | mittel | ✅ Digest per `pg_cron`, Frequenz daily/weekly/monthly/none |
| Entscheidung mit 18 | Jugendlicher entscheidet: Zugriff beenden, 1-6 Monate behalten oder erstmal behalten | mittel | ✅ `set_guardian_access_policy()`, Übergangs-Screen in der App |
| Nutzungszeit | Zeitfenster, in dem die App genutzt werden darf | mittel | ✅ PIN-geschützt (`set_guardian_settings_with_pin`), Sperre in der App |

**Regeln, die daraus zwingend folgen:**

1. Ein 16-/17-Jähriger muss sein Alter **serverseitig verifiziert**
   haben (das gibt es bereits: Video-Verifikation). Eine Einwilligung
   ohne Altersnachweis ist wertlos – sonst bestätigt ein 14-Jähriger
   einfach, er sei 16.
2. Die Einwilligung ist an **eine** Minderperson und **eine** Elternadresse
   gebunden. Sie ist nicht übertragbar und nicht wiederholbar.
3. Die Einwilligung ist **widerrufbar**, und der Widerruf wirkt
   serverseitig sofort – nicht erst beim nächsten Login.
4. **Keine Vollversion.** Ein beaufsichtigtes Konto bekommt keine
   Funktionen, die für diese Altersgruppe grundsätzlich gesperrt sind
   (Transit Spark/BLE ist bereits serverseitig auf 18+ gesperrt,
   Migration 131; der Zufallschat ist für Volljährige gedacht).
5. Der **Kontaktweg** bleibt bei den Sorgeberechtigten: Meldungen zu
   einem beaufsichtigten Konto gehen an die Eltern, nicht an das Kind.
6. Kein Volltext-Profil, keine exakte Standortanzeige, keine
   Weitergabe der Kontaktdaten an Minderjährige (Datenschutz-Folgen).

### 4. Offene Entscheidungen (bewusst nicht getroffen)

- [x] Wird das Modell **überhaupt** umgesetzt – oder bleibt es bei 18+
      und wird nur dokumentiert? → **Umgesetzt (03.11.2026).**
- [ ] Gilt es nur für 16/17 (Selbsteinwilligung ab 16) oder auch für
      13–15 (elterliche Einwilligung)? Play erlaubt in keinem Fall
      unter 18; die Entscheidung betrifft also nur Nicht-Play-Kanäle.
- [ ] Welche Kanäle dürfen das beaufsichtigte Konto ausliefern, und ist
      das rechtlich sauber?
- [ ] Aufsichtsmodus: welche Funktionen werden per Elternentscheid
      abgeschaltet, und wie wird das im Kind-Account sichtbar gemacht,
      ohne dass es wie eine Überwachung wirkt?
- [ ] Wie verhält sich das Modell zur Verifikation (Video) und zur
      Altersspanne? Ein beaufsichtigtes Konto braucht eigene Regeln im
      Jugendschutz-Filter.
- [ ] Prüfung durch eine Rechtsberatung (Medienrecht/Datenschutz), bevor
      irgendetwas davon live geht. → **OFFEN.** Die Technik ist live
      (Migrationen 165-167), die rechtliche Prüfung steht aus. Der
      Kernpunkt ist in der DSFA (Abschnitt 5, Punkt 6) festgehalten:
      Form und Nachweis der Einwilligung nach § 3a JUG und Art. 8 DSGVO,
      die Verantwortlichkeit für die Einrichtung eines kindlichen
      Kontos und die Einordnung der Nutzungszeit.
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

## Geplant für 0.11.0 – Emotionaler Rückzugsort (Sanctuary) & Lokaler KI-Reflexions-Chat

## Umgesetzt in 0.10.0 – Ausbau von „Find your Spark“: Zufall oder Kategorie

> Der Ausbau ist **gebaut** (Migration 203/204, Bildschirm „Nach Kategorie“, Build 49 der Linie 0.10.0). Die Gruppen und Foren kommen danach - sie stehen weiter unten.

### 9. Find your Spark – Ausbau: Zufallsvorstellung und Kategorien

> BEFUND (Betreiber, 09.11.2026): „Der Modus Find your Spark soll
> erweitert werden. Wenn man auf ihn drauf drückt, kommt wie gehabt
> erst, dass man seine Vorstellung machen muss (Muss geprüft werden, ob
> man schon gemacht hat oder nicht, damit nicht doppelt), dann
> entweder Zufallsvorstellung oder Vorstellungen anderer nach Kategorien
> ansehen. Also Kategorien sind die Interessens-Kategorien. Auf
> diesen neuen Teil mit den Kategorien soll ein Bereich mit 18+ sein,
> wo von 18 bis 99+ alle gesehen werden (Aber man kann nach Alter
> filtern mit Regler) und ein 16-17 Bereich ohne Vorstellung mit Alter
> darüber. Wichtig ist, dass diese Grenze wirklich klappt, wie auch
> überall anders auch, damit die Kinder/Jugend geschützt sind.
> Natürlich da dann E2E immer. Verschlüsselt auf Server speichern."

**Einstieg (in dieser Reihenfolge):**

1. **Vorstellungs-Check**: Fehlt die eigene Vorstellung, kommt zuerst
   der Hinweis „Mach erst deine Vorstellung" – **mit Prüfung, ob
   schon eine existiert** (sonst wird ein zweites Mal aufgefordert,
   obwohl längst eine da ist). Der bestehende Weg
   (`lib/widgets/intro_editor.dart`) wird dafür geprüft, nicht
   dupliziert. **Eine Textvorstellung genügt** – das Audio ist
   optional (und wird erst bei einem Funke gehört).
2. **Zwei Wege**: *Zufallsvorstellung* (ein Kandidat nach dem anderen,
   wie heute) oder *Nach Kategorien stöbern*.

**Die zwei Bereiche (Altersgrenze):**

| Bereich | Alter | Vorstellung | Altersregler |
|---|---|---|---|
| **18+** | 18 bis 99+ | Pflicht | 18…99, per Regler filterbar |
| **16/17** | 16 und 17 | Pflicht | Obergrenze 17 |

**Die Vorstellung bleibt Pflicht - auch in der Erweiterung** (und auch
für 16-/17-Jährige). **Sie darf aber rein TEXTLICH sein:** wer sich
vorstellt, schreibt seinen Text; **das Audio ist optional** und wird
erst bei einem Funke gehört (dort, wo die Vorstellung heute ohnehin
über `match-media` freigegeben wird). Die Kategorie-Sicht zeigt den
**Text** und die Interessen - nicht die Aufnahme.

- Die Grenzen sind **keine UI-Kosmetik**: sie stehen serverseitig in
  `age_compatible_bidirectional` (Migration 154/155) und werden von
  `lib/utils/age_safety_rules.dart` nur noch gespiegelt. **Minderjährige
  sehen ausschließlich Minderjährige, Erwachsene ausschließlich
  Erwachsene.** Ein 18-Jähriger bekommt nie einen 16-Jährigen zu
  sehen – auch nicht über die neue Kategorie-Sicht.
- Der Altersregler im 18+-Bereich geht bis **99** (`maxFilterAge` gibt
  für Erwachsene 99 zurück, für Minderjährige 17) – der Wunsch „18 bis
  99+" ist damit schon abgedeckt.
- **Die neue Sicht darf die Altersregel nicht umgehen.** Die
  Kategorie-Abfrage läuft serverseitig und filtert mit derselben
  Funktion; ein manipulierter Client bekommt dieselbe Grenze.

**Was neu serverseitig gebraucht wird (RPC, Migration):**

```
browse_by_category(
  p_category text,       -- die Interessens-Kategorie
  p_age_min  int,       -- 18 (Erwachsene) bzw. 16 (Minderjährige)
  p_age_max  int,       -- 99 bzw. 17
  p_limit    int        -- Seitengrösse
) returns table (...)
```

- Die Funktion wendet **`age_compatible_bidirectional`** auf den
  Betrachter an – **fail-closed**: ohne gültiges Alter (oder mit
  manipuliertem Geburtsdatum) kommt nichts zurück.
- Sie liefert **keine** Vorstellungs-Audios. Das Audio wird pro
  Kandidat über den bestehenden Weg geholt (`match-media`, serverseitige
  Berechtigungsprüfung) – **verschlüsselt auf dem Server, Entschlüsselung
  erst auf dem Gerät** (E2E wie bei Profilbildern und -Vorstellungen).
- **Interessen stehen im Klartext** auf dem Server (das steht so in der
  Datenschutzerklärung: „Features in plaintext: the selected features
  (category, value, colour)"). Eine Kategorie-Sicht ändert daran
  nichts – sie macht nur sichtbar, **wer** zu einer Kategorie gehört.
  Das ist eine neue Verknüpfbarkeit und damit **ein eigener
  Eintrag in der Datenschutzerklärung** (welche Interessen anderer
  sieht man, und in welcher Menge).
- Der Server nennt die Kategorie-Mitglieder **nur dem Alter nach
  passend**: Wer 16/17 ist, bekommt ausschließlich 16/17 – auch dann,
  wenn die Kategorie passt.

**Vom Betreiber entschieden (09.11.2026):**

- **Die Vorstellung bleibt Pflicht** – auch in der Erweiterung und
  auch für 16-/17-Jährige.
- **Sie darf rein textlich sein.** Das Audio ist optional und wird
  **bei einem Funke** gehört (der bestehende `match-media`-Weg gibt
  es ohnehin erst nach dem Match frei).
- **16- und 17-Jährige sehen KEINE 18+-Personen.** Die Trennung ist
  serverseitig (`age_compatible_bidirectional`) und gilt für jeden
  Abrufweg – auch für die Kategorie-Sicht.

**Noch zu entscheiden:**

- Wie viele Kandidaten eine Kategorie liefert (Vorschlag: 20 pro
  Seite, mit „weitere laden").


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
- [ ] **TURN-Relay fuer WebRTC-Anrufe (Video/Sprache)**: Aktuell
  wird ausschliesslich STUN verwendet. Hinter symmetrischem NAT oder
  strengen Firmen-Firewalls kommt deshalb keine Verbindung zustande.
  Es fehlt ein Relay-Anbieter, der ohne Kreditkarte und ohne
  Eigenbetrieb nutzbar ist. **Reihenfolge:** Anbieter festlegen ->
  `ice-config` um den Credential-Modus des Anbieters erweitern ->
  **Datenschutz-Erklaerung um den Anbieter ergaenzen (Abschnitt 6)** ->
  erst dann freischalten. Ohne den Erklaerungs-Eintrag waere die
  veroeffentlichte Aussage falsch.
  - Bekannte Stolperstelle: `openrelay.metered.ca` zeigt auf
    Test-Net-Adressen (192.0.2.1 / 100::1) und ist nicht benutzbar;
    `openrelayai.com` ist ein Tunnel-Dienst, kein TURN-Server, und eine
    `wss://`-Adresse ist ein Signalisierungskanal, kein ICE-Server.
  - Eine WebRTC-Signalisierung ueber WebSocket ist davon **nicht**
    betroffen - das ist ein eigener Weg, kein TURN.
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

### 10. Gruppen und Foren (später, nach 0.12.0)

- [ ] **Gruppen nach Interessen und Region** (z. B. „Wandern in
      Brandenburg", „Technik & Games"): eigene Thread-Struktur statt
      der 1:1-Chats, mit Moderation, Meldeweg und Löschfristen
- [ ] **Altersgetrennte Gruppen**: Für Gruppen gilt dieselbe Trennung
      wie im Rest der App (16/17 nur untereinander, Erwachsene nur
      untereinander) – **serverseitig erzwungen, nicht im Client**.
      Gruppen mit gemischten Altersgruppen werden **nicht** gebaut.
- [ ] **Moderation**: Jede Gruppe braucht einen Moderationsweg
      (Meldung → Admin-Prüfung) und eine Regel, wer sie liest. Ohne
      beides keine Gruppen.
- [ ] **Datenschutz**: Gruppen sind ein neuer Verarbeitungszweck
      (sichtbare Teilnehmerliste, Thread-Inhalte) → eigener Eintrag in
      der Datenschutzerklärung und in der DSFA.

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
- [~] **Belastbare Durchsetzung des Mindestalters**: Die Roadmap nannte
      „serverseitig erzwungenen Jugendschutz" und eine KI-Alters-Triage
      mit manueller Queue, aber kein konkretes Mindestalter, keine
      Rechtsgrundlage, kein Widerspruchsverfahren, keine Regel für
      Altersband-Unschärfe und keine Aufbewahrung der
      Verifizierungsmedien. Für eine App mit Jugendschutz ist das die
      zentrale rechtliche Voraussetzung, kein Feature.
      **Erledigt in 0.10.0:** das Mindestalter ist entschieden (16 Jahre,
      Betreiberentscheidung 03.11.2026) und an drei Stellen erzwungen -
      im Registrierungsformular (`lib/utils/validators.dart`), in der
      Datenbank (`chk_profiles_birth_date_age`, Migration 154, greift
      auch bei manipuliertem Client) und bei der serverseitigen
      Altersannahme. Der BLE-Nahbereich ist für unter 18-Jährige
      serverseitig gesperrt (Migration 131, fail-closed).
      **Offen bleibt ausdrücklich die Rechtsseite** (nicht bei uns, sondern
      bei der Rechtsberatung): Rechtsgrundlage der Einwilligung ab 16
      (§ 3a JUG, Abgrenzung zu Art. 8 DSGVO), Widerspruchsverfahren bei
      Altersablehnung, Regel für die Altersband-Unschärfe und die
      Aufbewahrung der Verifizierungsmedien. Das sind die Punkte aus
      Abschnitt 7 der DSFA (siehe dort, und die Datenschutzfolge-
      abschätzung oben).
- Öffentliches Threat-Model: **nach 0.10.0 vorgezogen**, dort geführt

## Versionierungsprinzip

Semantic Versioning (`MAJOR.MINOR.PATCH`), Start in der `0.x`-
Entwicklungsphase. Details: [CHANGELOG.md](CHANGELOG.md).
