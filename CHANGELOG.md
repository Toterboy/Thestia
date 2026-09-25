# Changelog – Thestia

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/)
und folgt der [Semantic Versioning Specification (SemVer)](https://semver.org/lang/de/).
Solange die Versionsnummer mit `0.` beginnt (Initial Development Phase nach SemVer §4),
können sich Schnittstellen und Verhalten jederzeit ändern.

## [Unreleased] – v0.9.0-Nachträge

### Sicherheit (Build 22)

- **Video-Verifizierung, Mehrframe-Median**: Altersschätzung aus bis
  zu 6 Frames (5 Video-Frames + 1 Selfie), Median statt Einzelbild;
  2-Jahre-Regel und manuelle Prüfung unverändert.
- **Stichproben-Audit** (Migration 120, live): Admin-Tab listet
  Auto-Freigaben mit Video, Bestätigen und Entziehen.
- **Play Integrity** (nur Play-Builds, `docs/PLAY_INTEGRITY.md`):
  Token + serverseitige Verdict-Prüfung in `verify-account/action
  "auto"` (deployed); ohne Play-Eintrag/Secret fällt alles sicher
  auf manuell zurück.
- **Modell-Integrität**: SHA-256-Check der ONNX-Modelle (fail-closed
  in manuell). **TLS-Pinning** für allen Dart-Traffic.
- **Dart-Obfuskierung** in Release-Builds (R8-Keep-Regel für den
  Reflection-geladenen Integrity-Helper). Abgelaufener
  Supabase-Leaf-Pin erneuert (gültig bis 24.11.2026).
- **Kontolöschung vollständig (DSGVO Art. 17)**: `delete-account`
  löscht zusätzlich Bug-Reports, Meldungen gegen den Nutzer und
  Rate-Limit-Reste (Rest via CASCADE, live per pg_constraint
  verifiziert); lokal werden Chat-Verlauf, Melde-Entwürfe und
  Crash-Journal mitgelöscht (auch bei Logout gegen Kontowechsel-
  Reste). Erhalten bleiben nur der irreversible Tombstone-Hash,
  Admin-Auditspalten und die Sperrliste.
- **API-Keys umgestellt (Legacy anon/service_role -> Publishable/
  Secret)**: Client liest nur noch `SUPABASE_PUBLISHABLE_KEY`, alle
  18 Edge Functions nutzen ausschließlich die sb_-Quellen
  (`SUPABASE_SECRET_KEY` / `SUPABASE_SECRET_KEYS`, supabase-js
  2.44.0); alle Legacy-JWT-Fallbacks sind entfernt (inkl. Secret
  `WISP_SERVICE_ROLE_KEY`). Legacy anon/service_role-Keys im
  Dashboard deaktiviert; Migration 122 ergänzt die SELECT-Grants,
  die PostgREST für Filter-DELETEs benötigt.
- **Versions-Support**: v0.9.0 (Build 28) ist die unterste
  unterstützte Version. v0.8.x und älter sind End-of-Support
  (seit 24.09.2026, siehe [SUPPORT.md](SUPPORT.md)); sie erhalten
  beim Start einen Update-Hinweis (serverseitig
  `app_config.min_app_version_build = 28`).
- **Behoben (Build 28)**: Standort-Eingabe (Onboarding + Profil):
  Geokodieren läuft erst bei Tipppause (Debounce), der getippte
  Text wird nicht mehr gelöscht, „Ort nicht gefunden" ist eine
  eigene Meldung. Verifiziert-Badge steht im eigenen Profil neben
  dem Persönlichkeitstyp.

Server: Migrationen **086, 087 + 088** einspielen + Edge Functions
`notify-user` erneut deployen.

### Behoben

- **Vorstellung mit Audio ging bei Aktualisierung/Neuinstallation
  verloren**: Der Intro-Upload setzte keinen Content-Type - der
  MIME-Whitelist-Bucket (nur Bilder) verweigerte ihn still. Migration
  088 erlaubt audio/mp4 (+mpeg); der Upload setzt jetzt explizit
  `audio/mp4`. Zusätzlich schreibt "Profil bearbeiten" die
  Intro-Felder nur noch, wenn sie geändert wurden (kein
  Stale-Null-Overwrite aus veralteten Screen-Zuständen).

- **„Bad state: DataChannel nicht verbunden"** (Zufallschat, QR-Chat,
  Ideen-Rad-Vorschläge): Sendungen vor verbundenem DataChannel landen
  jetzt in einer Outbox und werden AUTOMATISCH verschickt, sobald der
  Kanal offen ist (max. 50, pro Chat-Session, kein Transport in den
  falschen Chat).
- **„Dieser Chat existiert nicht mehr" beim Öffnen aus dem Funken-Tab**:
  Server-Matches existierten nur serverseitig; der Chat-Screen lädt sie
  jetzt via `list_my_matches_with_state` lokal nach (gleiche Match-ID,
  P2P-Aufbau danach).
- **Radar startete auf Android 11 nicht**: Beim Radar-Start fehlten die
  Laufzeit-Berechtigungen komplett. Jetzt Pre-Flight: Android ≤ 11
  STANDORT (Pflicht für BLE-Scan), Android 12+ BLUETOOTH_SCAN/CONNECT,
  iOS Bluetooth - plus vorhandener Bluetooth-Prompt.

- **QR-Scan öffnete nur ein „Fenster" statt des Chats**: Der Scanner
  navigierte zur PARTNER-ID (`/chat/<peerId>`), der Chat-Screen suchte
  aber nach der lokal generierten MATCH-ID → „Dieser Chat existiert
  nicht mehr". Jetzt wird mit der Match-ID navigiert
  (`findOrCreateMatch` liefert das Match), Regressionstests ergänzt.
- **QR-Kontakt hieß "Unbekannt"**: Nach dem Scan wird das echte
  Profil (Name, Alter, Interessen, Vorstellung) via
  `get_public_profile` geladen und der lokale Kontakt befüllt - auch
  nachträglich im Chat-Screen (Fallback, falls der Scan offline war).
- **Empfangender Like konnte die Vorstellung nicht anhören**: Der
  Chat zeigt jetzt eine Vorstellungs-Karte (Text + Audio-Player) für
  BEIDE Seiten; im „Erhalten"-Tab bleibt der Player (solange das
  Profil eine Audio-Vorstellung hat).

- **QR-Scan = erstmal nur Like** (kein sofortiger Chat): Online entsteht
  der Chat erst, wenn die gescannte Person annimmt (Funken-Tab
  „Erhalten"). Offline wird das Profil lokal gespeichert (max. 5) und
  das Like beim späteren Öffnen des Chats automatisch nachgeholt.
- **Radar-Verlassen**: Dialog „Radar laufen lassen?" (Stoppen/Weiter-
  laufen) mit Merk-Checkbox „zukünftig automatisch so beibehalten".

### Geändert

- **KEINE Streaks**: Flamme mit Tageszähler ("Funke-Streak") aus Chat-
  AppBar und Funken-Liste entfernt, Widget gelöscht.
- **Chat zuerst, Quiz später**: Match-Kacheln im Funken-Tab öffnen
  IMMER den Chat (vorher direkt das Quiz); das Quiz-Gate blockiert
  Text/Bild/Sprachnachricht/Anruf nicht mehr - es schaltet
  ausschließlich das Profilfoto frei (weiterhin serverseitig
  erzwungen via match-media). Banner im Chat verweist aufs Quiz.
- **P2P-Fehler entschärft**: Wenn die andere Seite (noch) nicht im
  Chat ist, erscheint keine rote Fehlermeldung mehr - der orange
  E2E-Badge zeigt "Verbindung wird aufgebaut".
- **Push bei erhaltenem Like** (QR-Scan): `notify-user` unterstützt
  das Kind `likes` (fixer Server-Text, Like-Beziehungsprüfung,
  Einzel-Schalter `notify_likes` respektiert).

### Neu

- **Mehrere Profilbilder (max. 3, abgerundet-rechteckig)**: Im Profil
  bis zu drei Bilder (primäres + 2 zusätzliche), Anzeige abgerundet
  rechteckig statt rund; Entfernen per Knopf, Upload bleibt lokal
  NSFW-geprüft und verschlüsselt (Slot 0 bleibt match-media-kompatibel
  unter avatar.jpg).
- **"Ich suche"-Reziprozität (Migration 088)**: Wer NACH FREUNDEN
  sucht, findet nur Personen, die ebenfalls Freunde suchen - und
  umgekehrt; Freunde-Sucher bekommen im Chat KEINE Date-Vorschläge
  (Meet-Intent + Ideen-Rad ausgeblendet).
- **Transit Spark: 2-Stunden-Ruhezeit**: Gesehene Geräte bleiben nach
  dem Radar-Ende 2 Stunden sichtbar (zum Nachschauen/Anschreiben in
  Ruhe); Button "Gesehene Geräte ansehen (2 Stunden)" unten auf der
  Radar-Seite. Die eigenen Presence-Tokens bleiben weiterhin sofort
  entfernt (Privacy).

- **Personalisierte Quiz-Fragen (Migrationen 086 + 087, ohne LLM)**:
  `start_quiz_attempt` zieht bevorzugt Fragen aus dem PARTNER-Profil:
  - **Lückentext aus der Vorstellung (087)**: „Vorstellung von Anna:
    ›Ich verbringe mein Wochenende gern ___.‹ Welches Wort gehört in
    die Lücke?" – korrekt = echtes Wort ihrer Vorstellung, Ablenker =
    weitere Worte aus derselben Vorstellung (mit Präfix-Guard gegen
    film/filme-Fallen); Stoppwörter werden gefiltert, Intro-Änderung
    verwirft veraltete Fragen, Best-Effort mit Fallback-Kette.
  - „Welches dieser Interessen gehört zu <Name>?" und „Wie alt ist
    <Name>?" (086).
  - Deterministisch aus (Match, Versuchszahl) generiert, damit BEIDE
    dieselbe Frage bekommen; korrekte Antwort bleibt serverseitig,
    Optionen werden wie bisher pro Match gemischt. Fällt nichts an,
    greift der generische Pool (075). Bewusst KEIN Cloud-LLM
    (Datenschutz: die Vorstellung verlässt den Server nicht) – ein
    lokales Modell am Gerät könnte die Antwort ohnehin nicht
    cheatsicher erzeugen.
- **Neues Design für Sprachnachrichten im Chat**: Play/Pause-Knopf,
  Wellenform (deterministische Balken aus der Message-ID - beide
  Seiten sehen dieselbe Form), Fortschritt-Färbung und Dauer; nach
  dem Anhören wird die entschlüsselte Datei gelöscht (M-17) und der
  Zustand „angehört" verständlich angezeigt.
- **Gespeicherte Profile (max. 5, lokal)**: QR-Kontakte sind jetzt
  PERSISTENT (AES-256-verschlüsselt, SecureHive) - gescannte Profile
  überleben den App-Neustart, damit man sie später anschreiben kann,
  wenn man unterwegs kein Internet hatte. Maximum 5 (kein stilles
  Verdrängen: beim Scan öffnet ein Auswahl-Dialog zum Löschen),
  einzeln löschbar (Funken-Tab „Gespeicherte Profile" + Lesezeichen-
  Aktion im Profil-Detail). Profil-Updates (Name/Vorstellung nach dem
  Online-Fetch) werden sofort persistiert; offline gescannte Kontakte
  bleiben „Unbekannt" und laden ihren Namen automatisch, sobald
  wieder Internet da ist.

## [0.9.0] – Beta – 2026-09-08

Server: Migrationen **080, 081, 082** einspielen (Reihenfolge).

### Neu

- **Transit Spark (Experimentell)** – der Nahbereichs-Funke: „Blicke
  getauscht, sich nicht getraut?" Zwei-Phasen-Architektur: Geräte in
  BLE-Nähe (3–10 m) tauschen anonyme, zufällige Encounter-Tokens aus
  (Phase 1, lokal, 45 Minuten gecacht); tippt später eine Person auf
  „Blicke getauscht" und die andere ebenfalls, matcht der Server die
  Tokens (Phase 2, asynchron – auch Stunden später).
  - Matching per SECURITY-DEFINER-RPC `match_proximity_spark`: Token-
    Overlap + alterskompatibel + nicht blockiert → gegenseitige Likes
    erzeugen den Funke über die Bestandspipeline (Match + Push
    „Neuer Funke" automatisch)
  - **Merkmal-Tags**: 1–3 Merkmale (z. B. schwarzer Hoodie, Lanyard)
    schärfen das Matching – serverseitig auf einen festen Katalog
    whitelisted, keine Freitext-Daten (082)
  - **Modus-Wahl**: „Bahn/Café" vs. „Messe/Event" – im Messe-Modus
    zählen nur starke BLE-Signale (echter Sichtkontakt; clientseitig)
  - Token-Rotation alle 10 Minuten, Rate-Limit (1 Signal / 2 min),
    Radar-Stop jederzeit, Daten-Cleanup (45 min Fenster / 24 h Cron)
  - Radar-Screen zweisprachig (DE/EN): Countdown, Encounter-Zähler,
    Tag-Auswahl, Match-Dialog
- **Entdecken-Seite neu strukturiert**: Modi nach Zweck gruppiert –
  „Menschen kennenlernen" (Find your Match, Dating Hour), „Direkt
  verbinden" (Zufallschat), „Unterwegs" (QR-Code, Transit Spark) –
  mit NEU-Badge für frische Modi.
- **Onboarding als Interview**: Thestia stellt Fragen statt eines
  Formulars – eine Frage pro Screen in Chat-Optik (Sprechblase, warmer
  Ton), dezente Fortschritts-Dots, alles überspringbar. Keine neuen
  Datenpunkte, kein Belohnungs-Mechanismus; komplett zweisprachig.

### Geändert

- **public_profiles-View ersetzt (Option A, 080)**: Fremde Profil-
  Lesezugriffe laufen ausschließlich über die SECURITY-DEFINER-Funktionen
  `get_public_profile`/`get_public_profiles` – löst den wiederkehrenden
  Advisor-Befund „security_definer_view". Die View bleibt im Doppel-
  betrieb für Alt-Clients bestehen (Entfernung in Folgemigration).

## [0.8.0] – Nachtrag 2 – 2026-09-07

Server: Migrationen **066** (falls fehlend), **074, 075, 076, 077, 078**
einspielen; Gegenprobe mit `supabase/check_columns.sql`.

### Neu

- **Profilbilder Ende-zu-Ende-verschlüsselt**: Avatare werden VOR dem
  Upload clientseitig per AES-256-GCM verschlüsselt (Zufalls-Schlüssel
  pro Bild) - der Server sieht ausschließlich Ciphertext. Der Schlüssel
  steckt im `photos`-Eintrag (`pfad|key|iv`); jeder berechtigte
  Betrachter entschlüsselt lokal. Alte, unverschlüsselte Avatare
  bleiben lesbar (AvatarCrypto, Migration 077)
- **Profilbilder serverseitig**: Die `photos`-Spalte existierte
  serverseitig bisher gar nicht (Avatare waren rein lokal!). Neu:
  Migration 077 (Spalte + öffentlicher View), Upload-Referenz wird
  verifiziert gespeichert, `fetchOwnProfile` lädt sie zurück - das Bild
  übersteht Neuinstallationen und ist im öffentlichen Profil sichtbar
- **NSFW-Prüfung on-device wirklich aktiv**: Der still außer Kraft
  gesetzte Check funktioniert jetzt - die gebündelte Modell-Datei
  nutzte ONNX-IR-Version 10 (Runtime unterstützt max. 9, gepatcht),
  der Output-Tensor brauchte Batch-Dimension-Flattening und die
  Pixel-Vorverarbeitung die vom Modell erwartete 0-255-Skalierung.
  Neuer permanenter Test (`image_safety_model_test.dart`) führt echte
  Inferenz aus und verhindert Still-Ausfälle. Klassen-Reihenfolge
  [NSFL, NSFW, SFW] gegen die Modell-Doku verifiziert
- **Profilbild-Änderung mit Speichern-Dialog**: Bildauswahl läuft jetzt
  wie alle anderen Angaben über den Dirty-Flag - lokale Vorschau,
  Upload erst beim Speichern, Abbrechen verwirft (das Bild war nie auf
  dem Server); NSFW-Check erfolgt bereits bei der Auswahl
- **Migrationen-robuste Daten-Sync** (Fix „App merkt sich nichts mehr"):
  Profil-Laden zweistufig (mit/ohne 077-Spalten), alle Profil-Writes
  selbstheilend (PostgREST „missing column" wird automatisch aus dem
  Body entfernt), Präferenz-Laden dreistufig inkl. Theme (`theme_name`
  bleibt erhalten) - eine fehlende Spalte kann nie wieder Name, Bio,
  Theme oder Radius gemeinsam auslöschen
- **Sync-Fehler sichtbar**: Profil-Speichern zeigt im SnackBar die
  genaue Server-Fehlerursache (z. B. fehlende Migration), statt still
  „ohne Sync" zu melden; `supabase/check_columns.sql` als
  Spalten-Diagnose für den Server
- **Pausenmodus in die Profil-Sichtbarkeit integriert** (Dopplung
  aufgelöst): „Wer kann mein Profil sehen?" ist jetzt DIE eine Steuerung
  - Jeder / Nur Funken / Unsichtbar (Pausiert) mit Bestätigungsdialog;
  der frühere separate Schalter ist entfernt, `paused` bleibt
  konsistent abgeleitet (auch über Server-Sync)
- **Chat-Verlauf: drei Modi** statt fester 200er-Grenze: Aus /
  200 Nachrichten / Kompletter Verlauf (Standard), verschlüsselt
  (AES-256, SecureHive)
- **Angemeldete Geräte mit echtem Modell**: `device_info_plus` liefert
  Hersteller + Modellkennung (z. B. „Samsung SM-S921B") - nach
  Neuinstallation ist das „zweite Gerät" eindeutig zuordenbar
  (auth_devices.device_model, Migration 078)
- **Vollständige Zweisprachigkeit in neueren Bereichen**: Farbschemata
  (Ozean→Ocean u. a.), Stimmungs-Chips, Entdecken-Modi und
  Sichtbarkeits-Optionen sind jetzt zweisprachig; Sichtbarkeits-Optionen
  haben Untertitel-Erklärungen
- **Konsequente „Funken"-Sprache**: Alle verbliebenen deutschen
  „Match"-Formulierungen heißen „Funke(n)" (u. a. „Neuer Funke!",
  „Funke bestätigen", Dating-Hour-Texte, Datenschutzhinweise);
  „Discovery" heißt auf Deutsch „Entdecken"
- **Abgerundete Klick-Animation**: Der Ripple folgt global der
  24-px-Kartenrundung (ListTileTheme in Light + Dark)

### Behoben

- `public_profiles`-View: Migration 077 hing an Postgres'
  Append-Regel für Views („cannot change name of view column") -
  `photos` steht jetzt korrekt am Ende der Spaltenliste

## [0.8.0] – Nachtrag (Build 12) – 2026-09-05

### Neu

- **Dating Hour über 20 hinaus**: 20 ist nur das MINDESTZIEL - der
  Teilnehmer-Zähler nennt jetzt die echte Gesamtzahl („Mindestziel
  erreicht: 37 Teilnehmer!"), mit Hinweis, dass mehr beliebig möglich
  ist; serverseitig gab es nie ein Limit
- **Chat-Export & -Import (Gerätewechsel/Reinstall)**: Der Datenexport
  enthält jetzt (bei aktivem verschlüsseltem Verlauf) die Chat-
  Nachrichten inkl. QR-Kontakte; der Import stellt Chats mit
  ORIGINAL-Match-IDs wieder her und aktiviert die Persistenz implizit
- **Kleinere APKs / AAB**: build_release.ps1 mit `-SplitPerAbi`
  (pro-CPU-APKs: arm64 77 MB statt 167 MB) und `-Aab` (Play-App-Bundle)

## [0.8.0] – 2026-09-05

Geschmack & Matching: der große Feature-Meilenstein (Roadmap 0.8.0).
Server: Migrationen **074** + **075** einspielen.

### Neu

- **Musik-Geschmack**: Im Profil-Editor Genres wählen, die man mag
  (Mehrfachauswahl, inkl. „Instrumental") - und freiwillig solche, die man
  explizit nicht mag. Der Geschmack fließt mit 30 % in den Verbindungs-
  Score ein (Gemeinsamkeiten positiv, Konflikte negativ), ist im
  eigenen Profil sichtbar und wird im Profil anderer mit hervorgehobener
  „Gleicher Geschmack"-Anzeige angezeigt (Migration 074)
- **Verbindungs-Score sichtbar**: Find-your-Match-Kandidaten zeigen jetzt
  „Match: X %" - serverseitig berechnet aus Distanz (40 %), gemeinsamen
  Interessen (30 %) und Musik (30 %); die Kandidaten sind danach sortiert
- **Pausenmodus**: Das eigene Profil lässt sich pausieren (Einstellungen)
  - unsichtbar in Discovery und Find-your-Match, bestehende Funken und
  Chats bleiben bestehen (profiles.paused, Migration 076)
- **Habit-Dealbreaker**: Schalter im Profil-Editor - nur noch Kandidaten,
  deren Konsum (Rauchen/Alkohol/Drogen) maximal so hoch ist wie der
  eigene; serverseitig im Matching erzwungen (profiles.habits_dealbreaker,
  Migration 076)
- **Kleinere APKs / AAB**: `build_release.ps1` unterstützt jetzt
  `-SplitPerAbi` (pro-CPU-APKs, ~77 MB statt 167 MB) und `-Aab` (Play-
  App-Bundle); die nativen Bibliotheken sind sonst dreifach enthalten
- **Mindestversions-Gate**: app_config.min_app_version_build - Clients
  unterhalb der Mindestversion zeigen beim Start einen Update-Screen
  (mit Rückfallebene „Trotzdem fortfahren"), Migration 076
- **Crash-Journal**: Der letzte Absturz wird lokal gespeichert; beim
  nächsten Start fragt die App, ob ein Report über den Bug-Report-Kanal
  gesendet werden soll (datenschutzfreundlich statt Cloud-Crashlytics,
  nichts verlässt das Gerät ohne Bestätigung)
- **Verschlüsselter Chat-Verlauf (Opt-in)**: Einstellungen → Sicherheit
  im Chat - speichert die letzten 200 Nachrichten pro Chat AES-256-
  verschlüsselt via SecureHive (Key im Keystore); Standard bleibt
  reiner Arbeitsspeicher (N-8-Design bleibt, jetzt als bewusste Wahl)
- **Kontext-Icebreaker**: Gemeinsame Interessen erscheinen als
  Vorschlags-Chip im Chat (vom Nutzer deaktivierbar über das Chat-Menü)
- **E-Mail- und Passwort-Wechsel in-app** (Datenschutz & Account): mit
  Re-Auth per aktuellem Passwort; E-Mail-Wechsel mit Bestätigungs-Links
  an beide Adressen
- **Daten-Import**: JSON-Datenexport kann wieder eingespielt werden
  (Profil, Einstellungen, Präferenzen)
- **Meldungs-Feedback**: Safety Center zeigt eigene Meldungen mit Status
  (list_my_reports, Migration 076)
- **Blockierliste**: Safety Center listet blockierte Nutzer mit
  Entblocken-Button (list_blocked_users, Migration 076)
- **Inaktive Funken als „Erschlossene Funken"**: Gekühlte Verbindungen
  rutschen still an das Ende des Interessen-Feeds - ohne Countdown, ohne
  Ablauf-Benachrichtigung, ohne Verlängerungsdruck (Migration 074)
- **Re-Funke ohne Druck**: Gekühlte Verbindungen mit einem Tap wieder
  entzünden (RPC respark_match) - jederzeit, ohne Frist
- **Chats verwalten**: Im Funken-Feed „Verwalten" antippen, Chats
  mehrfach auswählen und aus der eigenen Liste entfernen (nur für mich,
  RPC hide_match) - einzeln oder alle auf einmal
- **Ehrliches Beenden**: „Funke beenden" zeigt jetzt vorbereitete,
  freundliche Absage-Texte zur Wahl - oder „Ruhig enden lassen" (ohne
  Nachricht). Ghosting aktiv erschweren (RPC cool_match)
- **Ideen-Rad im Meet-Intent** (Test): „Dreh das Rad" wählt aus den
  bestehenden Date-Kategorien einen Vorschlag, der als E2E-Nachricht
  geteilt und im Chat bestätigt wird
- **Dating Hour: Frage-Karten für Schüchterne**: Drei thematische sanfte
  Fragen (Reise/Alltag/Träume, rotieren pro Stunde) - ein Tap übernimmt
- **Quiz-Fragen-Pool**: 60 echte Fragen ersetzen die 5 Platzhalter
  (Migration 075, idempotent); die korrekte Antwort rotiert über die
  Optionspositionen
- **UI-Einstellungen serverseitig**: Blind Mode, Foto-Freigabe,
  Sichtbarkeit, Dark Mode, Benachrichtigungs-Schalter und Bild-Blur
  werden in profiles.ui_prefs gespiegelt (Migration 074) und nach
  Neuinstallation/Login wiederhergestellt - sensible Inhalte (Chats,
  E2E-Identität) bleiben ausgenommen

### NSFW on-device (Scaffold)

- **Lokale Bildmoderation implementiert** (Migration-frei, Paket
  `onnxruntime` 1.4.1): Der neue `ImageSafetyService` lädt
  `assets/models/image-safety-classifier-xs.onnx` lazy (OrtEnv + Session
  einmalig), preprocesset gemeldete Bilder auf 224x224 RGB (NCHW-Float32,
  0..1) und klassifiziert rein on-device in die Klassen
  [NSFL, NSFW, SFW] (inkl. Softmax-Fallback bei Logits)
- **Human-in-the-Loop im Meldedialog**: Die lokale Prüfung startet erst
  mit dem Öffnen des Meldedialogs (niemals beim Senden/Empfangen, E2E
  bleibt unangetastet); das Ergebnis wird transparent angezeigt
  (Warnung ab 0.65 für NSFW/NSFL, sonst neutrale Bestätigung); Übertragung
  erfolgt NUR nach aktivem Tippen auf "Meldung absenden" - Abbruch
  verwirft das Bild aus dem Speicher
- **Report-Payload erweitert**: letzte 3 Textnachrichten als Kontext,
  SHA-256-pseudonymisierte Reporter-ID und das lokale KI-Ergebnis gehen
  mit; KEINE automatischen Kontosperren (manuelles Team-Review)
- **Noch offen**: die Modell-Datei selbst muss in
  `assets/models/image-safety-classifier-xs.onnx` abgelegt werden (Fehlt
  sie, deaktiviert sich die lokale Prüfung automatisch und der
  serverseitige Fallback-Scan aus 0.7.1 greift)
- Offen ist außerdem der i18n-Rest (zweisprachige Screens)

## [0.7.3] – Nachtrag (Build 9) – 2026-09-05

### Neu

- **Ladekreis bei der Passkey-Anmeldung**: Die Passwort-Anmeldung zeigt
  seit 0.7.3 direkt nach dem Tap den großen, nicht-abwischbaren
  „Anmeldung läuft…"-Kreis - der Passkey-Pfad zeigt ihn jetzt genauso
- **Suchradius wird zuverlässig gespeichert (wie der Name)**: Regler-
  Änderungen (Entfernung, Altersspanne, Suchradius-Modus) werden jetzt
  entprellt (1,5 s) automatisch serverseitig gesichert - auch ohne
  Speichern-Knopf; „Speichern" wartet auf den Server-Sync und meldet
  einen Fehlschlag klar statt still zu schlucken
- **Scroll-Hinweis auf der Profil-Seite**: dezenter, design-passender
  „Strich" am rechten Rand zeigt, dass die Seite weiter nach unten geht
  (Profil-/Bug-melden-Buttons waren ohne Scrollen unsichtbar); er
  blendet sich am Seitenende aus

### Behoben

- **„Server-Sync fehlgeschlagen" beim Profil-Speichern (Ursache)**: Die
  Schreib-Verifikation las zur Kontrolle die VOLLSTÄNDIGE Flags-Zeile -
  fehlte nur EINE andere Spalte auf dem Server (z. B. 071 nicht
  eingespielt), scheiterte jede Verifikation und damit jeder Speicher-
  vorgang. Jetzt wird gezielt nur der geschriebene Schlüssel zurückgelesen;
  ist allein die Kontrolle nicht möglich (Schema/Netz), gilt der Schreib-
  vorgang als erfolgt. Zusätzlich Fallbacks beim Laden: Präferenzen/Flags
  kommen auch dann zurück, wenn 071-Spalten fehlen (dann ohne Theme)
- **Profildaten nach Passkey-Anmeldung leer**: Der Passkey-Pfad lief
  früher NUR über den GoTrue-Event-Listener und übersprang die Nachläufe
  der Passwort-Anmeldung - Token-Persistenz, das Setzen der Signal-User-ID
  und der explizite Server-Sync (Profil, Präferenzen, Flags) fehlten, so
  dass Name & Co. nach der Anmeldung leer blieben. Die Passkey-Anmeldung
  läuft jetzt über [AuthNotifier.loginWithPasskey] mit IDENTISCHEM Ablauf
  wie die Passwort-Anmeldung; die Demo-Implementierung weist den Flow
  erwartungsgemäß ab
- **Fehlalarme der Schreib-Verifikation bei Listen-Spalten**: Der
  Zurücklesen-Vergleich in updateSetupFlagsAndVerify ist jetzt
  typensicher (PostgREST liefert List<dynamic>, der Client
  List<String>) - vorher gab es 3 unnötige Schreibversuche und ein
  „fehlgeschlagen", obwohl gespeichert war
- **Geräte-Liste: Reparatur-Skript** `supabase/repair_auth_devices.sql`
  (idempotent, mit Prüf-Report: Tabelle/RLS/Policies) für Fälle, in
  denen 071 teilweise eingespielt wurde; Gerätename korrekt formatiert
  (z. B. „Android (SDK 34)")

## [0.7.3] – Nachtrag (Build 8) – 2026-09-05

### Behoben

- **Passkey-Registrierung (Ursache definitiv identifiziert)**: In den
  „Relying Party Origins" des Servers standen SHA-1-Fingerprints (20 Byte)
  der Signatur-Keys - `android:apk-key-hash` verlangt SHA-256 (32 Byte),
  der Abgleich konnte nie matchen. Fix ist serverseitig (Dashboard Origins
  ersetzen - exakte Werte in `docs/PASSKEYS_SERVER_SETUP.md`), die App
  unterstützt die Diagnose: Debug-Builds loggen jetzt den gesendeten
  WebAuthn-Origin, die Fehlermeldung verweist auf die Setup-Doku

### Server

- Migration **073** (Härtung `auth_devices`): Längen-Constraints für
  client-gesetzte Werte + Cap von 20 Geräte-Einträgen pro Konto
  (Trigger mit Upsert-Schonung, gehärteter `search_path`)

## [0.7.3] – Nachtrag (Build 7) – 2026-09-05

### Behoben

- **Speichern-Nachfrage im Profil-Editor (Tab-Wechsel) endgültig
  repariert**: Die Bottom-Navigation ermittelte die aktive Unter-Route
  über den Router-Delegates-Kontext - das blieb je nach Zeitpunkt stumm.
  Der Schutz prüft jetzt direkt den Dirty-Flag (der Editor setzt ihn beim
  Verlassen zurück); Widget-Tests verifizieren Textfeld-, Regler- und
  PopScope-Verhalten
- **Geräte-Liste: Fehler sichtbar statt stummer Abbruch**: Fehlgeschlagene
  Registrierung/Listung zeigt jetzt die bereinigte Ursache (Tabelle fehlt
  = Migration 071 fehlt, RLS, Netz, Sitzung) als Hinweis über der Liste
  bzw. als klarer Fehlerzustand
- **Passkey "Der Server konnte den Passkey nicht bestätigen"**: Die
  Meldung verweist jetzt auf die neue Verwaltung; vor dem Anlegen wird
  transparent auf bereits existierende Passkeys hingewiesen (deren
  Alt-Einträge die Registrierung blockieren können)

### Neu

- **Passkeys verwalten** (Einstellungen): Listet alle am Konto
  registrierten Passkeys (Name, erstellt, zuletzt genutzt) und erlaubt
  Umbenennen/Löschen - damit lassen sich Alt-/Defekt-Einträge entfernen,
  wenn der Server eine NEUE Registrierung nicht bestätigt
- **Server**: Migration 072 konsolidiert die öffentliche Profil-View
  (`public_profiles`, bewusster Definer-Modus - Datenschutz: exakte
  Geburtsdaten/Koordinaten bleiben serverseitig) und dokumentiert den
  Advisor-Befund als intentional; Migration 071 bleibt Voraussetzung für
  die Geräte-Liste

## [0.7.3] – Nachtrag (Build 6) – 2026-09-05

Neue Funktionen und Reparaturen (Konto-Datenhalt, Geräteübersicht, Regler).

Hinweis: Die Roadmap-Punkte für 0.8.0 (Geschmack & Matching, Musik-Genres,
on-device-Moderation, i18n-Ausbau) sind hier NICHT enthalten - diese Version
bleibt ein 0.7.x-Patch/Polish-Release.

### Neu

- **Angemeldete Geräte** (Einstellungen → Datenschutz & Account): Zeigt alle
  Geräte, auf denen das Konto eingeloggt ist (Gerätename, App-Version,
  letzte Aktivität, eigenes Gerät markiert). Mit einem Tastendruck meldet
  man sich ÜBERALL außer auf dem aktuellen Gerät ab
  (`signOut(scope: others)`; Migration 071 mit `auth_devices`-Tabelle,
  RLS-gesichert)
- **Themefarbe gehört zum Konto** (Migration 071, `profiles.theme_name`):
  Die Farbschema-Wahl wird serverseitig gespeichert und direkt beim Login
  wieder angewendet - auch nach einer App-Neuinstallation
- **Entfernung & Alter überstehen Neuinstallation**: Die maximale
  Entfernung wird zusätzlich in die App-Einstellungen gespiegelt (z. B.
  Dating-Hour-Filter), die Altersspanne kommt weiterhin aus dem Profil -
  beide werden nach Login/Neuinstallation serverseitig wiederhergestellt

### Behoben

- **Altersspannen-Regler eingefroren ("18-18")**: Die Regler für
  Mindest-/Höchstalter verwendeten die aktuell gewählten Werte als
  Slider-Grenzen - bei 18-18 war der Spielraum null, die Regler ließen
  sich nicht bewegen und wirkten ausgegraut. Jetzt sind es zwei gekoppelte
  Slider mit den statischen Sicherheitsgrenzen (16-99), die sich beim
  Ziehen gegenseitig mitnehmen - im Profil-Editor, in der Einrichtung und
  in den Dating-Hour-Präferenzen (gemeinsames Widget `AgeRangeSliders`,
  der dortige RangeSlider frohr bei identischen Werten ebenfalls ein)
- **Speichern-Dialog im Profil-Editor erschien nie bei Reglern/Dropdowns**:
  Änderungen an Geburtsdatum, Altersspanne, Entfernung, Suchradius-Modus
  und Bundesland-Filter lösten die "Ungespeicherte Änderungen"-Nachfrage
  nicht aus (und wurden still übernommen). Jetzt führt jede dieser
  Änderungen zur Nachfrage; "Verwerfen" setzt die Regler auf den Stand
  beim Öffnen zurück. Auch die Zurück-GESTE fragt jetzt zuverlässig (der
  Dirty-Flag wurde beobachtet statt nur post-frame gesetzt)
- **Weißes Viereck bei Benachrichtigungen behoben (echte Ursache)**: Das
  Notification-Icon wurde vom Branding-Tool ohne Alpha-Kanal erzeugt
  (`Image()`-Default = RGB) - Android zeigte daher ein volles weißes
  Quadrat statt der Herz-Silhouette. Das Icon ist jetzt ein echtes
  RGBA-Asset; beide Icon-Tools sind gegen stillen Alpha-Verlust gehärtet
- **Passkey-Erstellen: "Anfrage abgebrochen von Thestia" / "credential
  verification failed"**: Der Plugin-Authenticator brach vor JEDER
  Zeremonie eine laufende Operation ab - das konnte die eigene neue
  Anfrage mit abwürgen. Thestia nutzt jetzt einen eigenen Authenticator ohne
  dieses Vorabbrechen, plus Doppel-Tap-Schutz an der Kachel und im
  Service (nur eine Zeremonie gleichzeitig). Server-"Verifikation
  fehlgeschlagen" bekommt eine verständliche Meldung mit Lösungshinweis
- **"Speichern fehlgeschlagen"-Fehlalarme bei Präferenzen**: Die
  Schreib-Verifikation las die Präferenz-Spalten beim Zurücklesen nicht
  (`max_distance_km`, `age_range_min/max`, ...) - das Speichern von
  Entfernung/Altersspanne wurde deshalb IMMER als fehlgeschlagen gemeldet,
  obwohl es geschrieben war
- **Dating-Hour-Regeln erscheinen nur noch EINMAL** (Migration 071,
  `profiles.dating_hour_intro_seen`): Der Intro-Flow (Regeln + Erklärung)
  hängt jetzt am Konto statt am Gerät - nach Neuinstallation/Neu-Anmelden
  kommt er nicht wieder

## [0.7.3] – 2026-08-30

Fix-Release: Usability und Stabilität.

### Behoben (Nachtrag +4)

- **2FA-Status zuverlässig**: Der MFA-Status wird beim Laden mit
  Session-Auffrischung und Wiederholung versucht - die Einstellungs-Kachel
  und der MFA-Screen zeigen den echten Stand (vorher: „nicht eingerichtet"
  trotz aktiver 2FA, wenn der Status-Abruf fehlschlug)
- **Passkey-Anlegen bei aktiver 2FA mit klarer Meldung**: Existiert schon
  ein verifizierter Faktor, erscheint jetzt „2FA ist für dieses Konto
  bereits aktiviert." statt einer kryptischen Ablehnung
- **„Später erinnern" schließt die 2FA-Seite** statt sie endlos neu zu
  öffnen (PopScope-Sperre wurde vom programmatischen Verlassen nicht
  aufgehoben)
- **Profil-Editor: Tab-Wechsel fragt zuverlässig** - Reine Textfeld-
  Änderungen lösten keinen Rebuild aus, der Dirty-Flag blieb dadurch false
  und die Nachfrage beim Tab-Wechsel unterblieb (Listener halten ihn jetzt
  synchron); der Zurück-Button im AppBar fragt ebenfalls explizit
- **Altersspanne 18-18 jetzt erhöhenbar** - Die RangeSlider ließ bei
  identischen Werten nur den unteren Regler greifen; im Profil-Editor sind
  es jetzt zwei getrennte Regler (Mindest-/Höchstalter), die sich beim
  Verschieben gegenseitig mitnehmen
- **Passkey-Fehler transparent**: Bei einer Server-Ablehnung wird jetzt
  der kurze Server-Grund in der Meldung mit angezeigt (z. B. "AAL2
  required") - für die Ursachensuche statt einer pauschalen Ablehnung
- **Profil-Editor: Tab-Wechsel zuverlässig erkannt** - Die Nachfrage nach
  ungespeicherten Änderungen griff beim Reiter-Wechsel nicht, weil die
  Route-Erkennung im Shell-Kontext die Unterseite nicht sah (jetzt über
  die volle URI gelöst)
- **Alle Dropdowns abgerundet** - Die fünf Dropdowns im Profil-Editor
  (Geschlecht, „Was suchst du?", Land, Bundesland, Suchradius-Modus)
  folgen jetzt ebenfalls der 16-px-Rundung
- **Dating-Hour-Meldung präzisiert**: „Präferenzen gespeichert. Deine
  Teilnahme meldest du über ‚Ich bin dabei' am Event-Tag an." (statt der
  verwirrenden Formulierung „Du bist noch nicht angemeldet")

### Behoben

- **Automatische Abmeldung nach Stunden behoben**: Der Session-Token läuft
  nach ~1 h ab; war die App länger im Hintergrund, schlug der einzige
  Auffrischungsversuch beim Öffnen fehl und man war ausgeloggt - obwohl
  „Angemeldet bleiben" aktiv war. Jetzt wird beim Start mehrfach mit
  Pausen aufgefrischt; nur bei echtem Token-Verlust bleibt man
  ausgeloggt
- **Passkey-Erstellen trotz 2FA**: Der 2FA-Status wurde aus einem Cache
  gelesen, der veraltet oder nie geladen war - dadurch griff die 2FA-
  Bestätigung vor dem Anlegen nicht und der Server lehnte ab. Jetzt wird
  der Status frisch geladen
- **2FA-Anzeige**: Die Einstellungs-Kachel zeigt den aktuellen 2FA-Stand
  jetzt beim Antippen frisch vom Server (vorher konnte ein alter/leerer
  Stand angezeigt werden)
- **Benachrichtigungs-Symbol**: Das Statusleisten-Icon war praktisch leer
  (nur ~300 weiße Pixel aus einer zu sparsamen Logo-Rampe). Jetzt eine
  klare Herz-Silhouette
- **Dating-Hour-Zeit: Fallback gehärtet** - Schlägt der Abruf der
  Serverzeit beim Start/bei App-Rückkehr fehl, versucht die App es jetzt
  mehrfach mit Pausen (vorher: sofortiger Fallback auf die lokale
  Gerätezeit, wodurch die Dating-Hour-Anzeige von der Geräte-Zeitzone
  abhing). Das Warn-Banner bleibt solange sichtbar, bis eine Serverzeit
  verifiziert ist; die harte Beitritts-Prüfung läuft unverändert
  serverseitig
- **Zurück-Geste in der Dating Hour**: führt jetzt jeweils zur Seite
  davor (z. B. von den Präferenzen zurück zum Event) statt zur
  Haupt-Navigation
- **Altersspanne im Profil-Editor ergänzt** (fehlte dort komplett, mit
  altersbasierter Klemmung wie in der Einrichtung)
- **Ladekreis direkt nach dem Anmelde-Klick**: Nicht-abwischbarer
  Ladekreis („Anmeldung läuft…") erscheint sofort, damit keine tote Phase
  entsteht

### Hinzugefügt

- **Dating Hour: Teilnehmer-Fortschritt** (Migration 068): „X von 20
  Teilnehmern" mit Fortschrittsbalken im Event-Screen - man sieht, ob das
  Ziel erreicht ist und wie viele noch fehlen

## [0.7.2] – 2026-08-28

Dating-Hour-Release: Zeit-Fix, Fairness-Regeln und Admin-Polish.

### Hinzugefügt

- **Dating Hour: Mindestteilnehmer** – Erst ab 20 angemeldeten Personen
  startet das Event; darunter fällt es aus (klare Meldung im Event-Screen)
  und die Regeln-Karte weist darauf hin
- **Dating Hour: keine Partner-Dopplungen mehr** – Das Matching bevorzugt
  Personen, mit denen es noch NIE eine Dating-Hour-Session gab; erst wenn
  keine unbesuchte Kombination übrig ist, wird wiederholt (Migration 067)
- **Dating Hour: Altersdifferenz-Hinweis** – Liegen mindestens 10 Jahre
  zwischen beiden Chat-Partnern, erscheint ein respektvoller Hinweis-Banner
  im Event-Chat
- **Dating-Hour-Präferenzen bleiben erhalten** – Die zuletzt genutzten
  Präferenzen (Alter, Geschlecht, besonderes Merkmal, Entfernung,
  Gewohnheiten) werden global serverseitig gemerkt (Migration 067) und
  vorbelegen den Präferenzen-Screen – auch nach Neuinstallation
- **Mood of the Day öffentlich** – Die fehlende Server-Infrastruktur
  (Migration 024, idempotent nachgezogen in 067) ermöglicht es nun:
  eigener Mood setzbar und für andere sichtbar
- **Admin-Bereich im App-Look** – Listen jetzt als Karten konsistent zur
  restlichen Nutzeroberfläche

### Behoben

- **Dating Hour startet zur richtigen Zeit** – Die Startzeit war als
  20:00 UTC gespeichert (= 21/22 Uhr deutscher Zeit). Jetzt korrekt
  20:00 Europe/Berlin, mit automatischer Sommer-/Winterzeit-Umstellung.
  Bestehende zukünftige Events werden korrigiert (Migration 067)
- **Admin-Bereich: Blackscreen beim Verlassen behoben** (falscher
  Navigator-Pop auf einer GoRouter-Route)
- **Zurück-Geste in der Dating Hour beendet nicht mehr die App**, sondern
  navigiert zur Haupt-Navigation (gilt für alle Dating-Hour-Screens)
- **Formulierung korrigiert**: „Niemand außer euch beiden kann eure
  Nachrichten lesen (Signal-Protokoll)" statt des sprachlichen Fehlers
- **Passkey-Erstellung mit aktivierter 2FA**: Vor dem Anlegen eines
  Passkeys erfolgt jetzt automatisch die 2FA-Bestätigung – der Server
  verlangt sie, ohne sie schlug die Erstellung mit einer kryptischen
  Ablehnung fehl

## [0.7.1] – 2026-08-26

Polish- und Fix-Release zu 0.7.0 (das nie veröffentlicht wurde): Sprach-
Complettierung, Farbwelt-Rahmen, App-Start-Logo, 2FA-Navigation und
Passkey-Konfiguration.

### Hinzugefügt

- **Bild-Meldungen: Nachweis-Pflicht (Lückenfix)**: Beim Senden eines
  Chat-Bildes wird nur dessen SHA-256-Hash serverseitig registriert
  (Migration 068, niemals das Bild). Eine Meldung wird nur akzeptiert,
  wenn der Hash nachweist, dass dieses Bild tatsächlich zwischen den
  beiden Chat-Partnern geflossen ist - beliebige fremde Bilder können
  nicht mehr untergeschoben werden
- **Dating Hour: konsistente Teilnehmer-Zählung** - Die Mindestteilnehmer-
  Prüfung zählt wie die Anzeige nur Accounts, die mindestens 24 Stunden
  alt sind (Migration 070): kurzlebige Fake-Accounts können das Event
  weder "startbar" machen noch die Fortschrittsanzeige täuschen
- **Präferenzen überleben Neuinstallationen** (Migration 066): Entfernung,
  Altersspanne, "Ich suche" (Beziehungsart), Bundesland-Filter, Ort und
  Geschlechts-Filter werden jetzt zusätzlich serverseitig gespeichert
  (verschlüsselter Transport, RLS-geschützt) und nach der Anmeldung
  automatisch wiederhergestellt - vorher gingen sie bei einer
  Neuinstallation verloren. Gespeichert wird beim Abschluss der
  Einrichtung und beim Speichern im Profil-Editor
- **Admin: Nutzer sperren/entsperren mit Begründung** (versteckter
  Admin-Bereich): Im „Sperren"-Tab gibt es jetzt ein Formular
  (E-Mail oder User-ID + Pflicht-Begründung). Die neue Edge Function
  `admin-ban` (nur für die Admin-ID aufrufbar) hinterlegt die E-Mail in
  der Sperr-Tabelle (blockiert Neu-Registrierung) und sperrt bei Angabe
  einer User-ID zusätzlich den bestehenden Account sofort (Sessions
  ungültig). Optional erhält der Nutzer eine E-Mail mit Begründung und
  Hinweis auf den Entsperrungsantrag. Entsperren per Button in der Liste
- **Bild-Meldung mit KI-Vorprüfung (NSFW, melde-basiert)**: Chat-Bilder
  werden bewusst NIE automatisch beim Senden gescannt (E2E). Erst eine
  Meldung durch den Empfänger prüft exakt dieses eine Bild automatisch
  per NSFW-KI (neue Edge Function `report-image`, NSFW-Klassifikator,
  Token nur als Function-Secret). Der Meldende sieht das KI-Ergebnis
  SOFORT: Bestätigt die KI, gehen Bild, Report und KI-Ergebnis
  automatisch per E-Mail an das Team. Widerspricht die KI, kann der
  Meldende (falls die KI falsch liegt) eine manuelle Prüfung veranlassen -
  auch dann gehen Bild, Report und KI-Ergebnis an das Team. Migration
  064 erweitert photo_moderation um Reporter-/Eskalations-Spalten.
  Der frühere (deaktivierte) Auto-Scan beim Senden wurde entfernt

### Behoben

- **Profil nach Neuinstallation leer behoben (wichtig)**: Der
  Profil-Ladevorgang fragte eine Datenbank-Spalte (mood) ab, die in den
  Migrationen nie existiert hatte - der Abruf schlug dadurch IMMER fehl,
  und nach einer Neuinstallation blieben Name, Bio, Geburtsdatum usw.
  leer (auf dem alten Gerät unsichtbar, weil dort eine lokale Kopie
  lag). Die Spalte ist aus der Abfrage entfernt; der Abruf hat jetzt
  zusätzlich einen Wiederholungsversuch bei Netzproblemen
- **Einrichtung erscheint garantiert NIE wieder (auch nicht kurz)**:
  Neues Gesamt-Flag onboarding_done (Migration 065, mit Rückstandsaufholung
  für Bestandsnutzer): Sobald die Einrichtungskette einmal abgeschlossen
  ist, erzwingt der Router Einstellungen & Privatsphäre und den
  Persönlichkeitstest bei keiner Anmeldung und keiner Neuinstallation
  wieder - unabhängig von übersprungenen Punkten. Zusätzlich: Schlägt der
  Server-Abgleich komplett fehl, erscheint die Einrichtung ebenfalls
  nicht (nur bei einer frischen Registrierung läuft sie natürlich)
- **Sprach-Button wie der Anmelde-Button**: Das Übersetzen-Symbol auf
  Anmelde- und Registrierungs-Screen sitzt jetzt auf einem runden,
  in Primärfarbe gefüllten Button - gleicher Look wie "Einloggen",
  nur rund statt breit
- **Passkey-Diagnose entfernt**: Das Entwickler-Werkzeug ist jetzt auch
  aus dem Debug-Build der Einstellungen raus (Code im Repository bleibt
  für die Fehlersuche erhalten)
- **Doppelte Registrierung abgefangen**: Supabase meldet bei bereits
  registrierter E-Mail keinen Fehler ( Schutz vor E-Mail-Enumeration),
  sondern liefert still den bestehenden Nutzer zurück - die App schickte
  den Nutzer an den "E-Mail bestätigen"-Screen, ohne dass je eine
  Bestätigungs-Mail kam. Jetzt erscheint direkt die Meldung "Diese
  Emailadresse ist bereits registriert" mit Hinweis auf Login bzw.
  Passwort-Reset
- **Ladekreis ab dem allerersten Moment**: Während der Initialisierung
  (bis zu 4 s) war nur das statische Splash-Logo ohne jeden Ladehinweis
  zu sehen. Jetzt erscheint unmittelbar nach dem Start Logo + drehender
  Ladekreis
- **Deutsch funktioniert jetzt überall**: Die App crashte bei gesetzter
  Sprache Deutsch mit "No MaterialLocalizations found" (fehlende
  Lokalisierungs-Delegates) - Login/Registrierung waren unbenutzbar
- **2FA "Später erinnern"**: Ein Sync-Fehler blockierte die Rückkehr aus
  dem "Konto absichern"-Dialog
- **Einrichtung erscheint nicht mehr erneut**: Der Server-Stand wurde nur
  "best-effort" gesichert (stiller Fehlschlag) - jetzt mit sichtbarem
  Hinweis UND Selbstheilung beim nächsten Login (lokale erledigt-Flags
  werden zum Server nachgezogen). Die Selbstheilung greift erst nach dem
  ersten Server-Sync, damit veraltete lokale Reste (z. B. von einer
  früheren Installation) die Einrichtung bei einer NEUEN Registrierung
  nicht überspringen
- **Standort-Erkennung ohne Einfrieren**: "Standort ermitteln" während
  der Altersspannen-Anpassung konnte die App zum Einfrieren bringen
  (doppelter, gleichzeitiger GPS-Aufruf durch Text-Validierung); der
  Start-Thumb der Altersspanne rutschte außerdem bei jedem Neuaufbau
  auf 16 zurück
- **Benachrichtigungs-Icon in der Statusleiste rund statt Viereck**:
  Das Small-Icon nutzte das voll opake Launcher-Icon; jetzt die rund
  maskierte Silhouette (drawable/notification_icon.png). Zusätzlich
  setzt der Push-Versand (notify-user) jetzt explizit dieses Icon -
  vorher zeigte das System bei Server-Push-Nachrichten weiterhin ein
  Viereck neben der Uhrzeit
- **„Keine neuen Funken"-Karte**: Abgeschnittene Buchstaben bei großen
  Systemschriften behoben (Kanten-Clipping der Card deaktiviert)
- **Audio-Vorstellung**: Erneutes Hochladen schlug mit StorageException
  409 "Duplicate" fehl - jetzt mit Upsert
- **App-Start-Logo**: Es wurde das runde Benachrichtigungs-Icon statt des
  vollständigen Logos gezeigt, außerdem zu groß gerendert (Schrift
  abgeschnitten). Jetzt korrektes, skaliertes Logo inkl. Android-12+
  Kreis-Maske
- **Farbwelten**: Rahmen von Eingabefeldern folgten hartcodiert der
  Classic-Pink; jetzt übernimmt jede Farbwelt (Ozean, Wald, Sonnen-
  untergang, Lavendel, Schiefer) auch die Rahmen
- **Registrierung**: Migration 063 entfernt Invite-Reste von
  Bestandsservern (Invite-Enforcement blockierte die offene
  Registrierung mit "database error saving new user")
- Begrüßung ohne Namen jetzt "Hallo, du!" statt "Hallo, schönen Menschen!"
- **Stadt/Ort wird nach der Einrichtung übernommen**: Bei Standort-Erkennung
  und manueller Eingabe blieb der Ortsname nur im Eingabefeld (und in den
  Nutzer-Präferenzen) - er wurde nie in das Profil-Feld `city` geschrieben
  und vom nächsten Server-Sync (fetchOwnProfile) mit leer überschrieben.
  Jetzt wird der Ortsname lokal im Profil UND serverseitig persistiert
  (sowie die GPS-Koordinaten weiterhin via process-location-check)
- **Passkey-Login mit aktiver CAPTCHA**: Der Server verlangt bei
  aktivierter Dashboard-CAPTCHA auch für den Passkey-Login ein Token -
  die App rief die Zeremonie aber ohne Token auf, und GoTrue lehnte mit
  "Server hat die Passkey-Anfrage abgelehnt" ab (noch vor dem Biometrie-
  Dialog). Jetzt erscheint - wie beim Passwort-Login - zuerst der
  Sicherheitscheck; zusätzlich bekommt der Abbruch-/Ablauf-Fall eine
  eigene, verständliche Meldung
- **Einrichtung erscheint nach Neuinstallation nicht mehr erneut
  (Zuverlässigkeit)**: Zwei Lücken geschlossen. (1) Beim Login nach
  Neuinstallation wurden die serverseitigen Setup-Flags mit hartem
  3-Sekunden-Timeout und OHNE Retry geholt - ein transienter
  Netzfehler ließ die Einrichtung wieder erscheinen, obwohl der Server
  sie als abgeschlossen hatte; außerdem übersprang ein Profil-Fehler
  den Flags-Fetch komplett. Flags werden jetzt entkoppelt mit 3
  Versuchen (8 s Timeout) geholt. (2) Beim Abspeichern des
  Einrichtungs-Stands galt ein stiller 0-Zeilen-Update als "Erfolg";
  jetzt wird nach dem Schreiben zurückgelesen und bei Abweichung
  retries, und auch der Persönlichkeitstest meldet einen Fehlschlag
  sichtbar statt fire-and-forget

### Geändert

- **Applogo: EINZIGE Quelle `wispdating_icon_base.png`**: Launcher-Icons
  (rund, Light/Dark), Adaptive-Icon-Foreground, native Splash-Bilder und
  Notification-Icon werden jetzt ausnahmslos aus dem Basis-Icon generiert
  (verwaiste/veraltete Logo-Assets entfernt; Welcome-Screen precachte noch
  ein nicht mehr vorhandenes Asset). HINWEIS: Das Applogo und dessen
  Implementierung sind noch IN ARBEIT - Feinschliff (Größen, Masken,
  Farbwelten) folgt
- **Einstellungen: Sprachfeld aufklappbar** - statt eines kleinen Icons
  ist das gesamte Feld „Sprache" bedienbar und klappt nach unten auf
  (Sprachwahl per Radio-Liste)
- **Login: Sprach-Icon mit Kreis-Hintergrund** in `primaryContainer` -
  hebt sich damit in jedem Theme (Light/Dark, alle Farbwelten) klar ab
- **Einstellungen: „Account löschen" entfernt** (existiert vollständig
  unter Datenschutz & Account; der 2FA-Step-up vor der Löschung ist
  dorthin mitgezogen). Die Passkey-Diagnose ist jetzt ein reines
  Debug-Werkzeug und für Endnutzer nicht mehr sichtbar
- **Datenschutz & Account**: Auftragsverarbeiter aktualisiert - Brevo
  (Transaktions-E-Mails), Cloudflare (CAPTCHA/TURN) und Netlify (Auth-/
  CAPTCHA-Seite) ergänzt, Hugging Face entfernt (unbenutzt). Unter
  „Einwilligungen" führen jetzt Buttons direkt zu den System-Einstellungen
  (Standortfreigabe) bzw. App-Einstellungen (Push)
- **Einstellungen & Datenschutz komplett zweisprachig** (DE/EN): Alle
  sichtbaren Listen-Texte der beiden Screens sind übersetzt
- **Einrichtung: Swipen deaktiviert** - nur die Buttons führen die
  pro Schritt erforderliche Validierung/Speicherung aus; vorher konnten
  per Swipe Schritte übersprungen werden, wodurch Angaben nicht ins
  Profil übernommen wurden
- **Profil bearbeiten**: Ungespeicherte Änderungen fragen beim Verlassen
  (Tab-Wechsel und Zurück) nach Speichern/Verwerfen; nach fehlge-
  schlagener Validierung erscheint ein Hinweis direkt am Speichern-Button
- Sprach-Button: Übersetzen-Symbol mit Popup-Menü (Deutsch/Englisch),
  nur noch ein Button, positioniert auf Höhe der Überschrift; die
  "Einloggen"-Kopfzeile entfällt, Inhalt rückt höher
- Englisch vervollständigt: Login-/Registrierungs-Screen, Sicherheits-
  check-Dialog und alle Auth-Fehlermeldungen sind zweisprachig
- Standort-Autoerkennung trägt einen ORTSNAMEN ein (Plattform-Reverse-
  Geocoder) statt Koordinaten; Fallback: grobe Region
- Alle Aufklappmenüs abgerundet (16 px, konsistent zum Rest der App):
  Geschlecht bei Registrierung, Beziehungsart/Filter/Bundesland in der
  Einrichtung
- Texte: keine Gedankenstriche mehr in Nutzersichtbaren Sätzen
- Entdecken-Hinweis: „nach einem Funke bestehst" statt „nach einem
  Match bestehst" (Konsistenz zur Funke-Benennung)
- Interne Aufräumarbeiten (Verschlüsselungs-Review): Signal-Skalar-
  Metadaten (Registrierungs-ID, PreKey-Cursor, aktiver SignedPreKey)
  liegen jetzt in einer eigenen verschlüsselten Box statt zweckentfremdet
  im Identity-Adapter (inkl. Migration für Bestandsinstallationen);
  SignedPreKey-Lade-/Rotationslogik vereinfacht (verbrauchte Keys werden
  nicht mehr versehentlich reaktiviert)

### Sicherheit

- Passkeys: assetlinks.json korrigiert (Fingerprint-Format mit
  Doppelpunkten wie von der Android-API geliefert, ergänzter web-Eintrag)
  und die apk-key-hash-Origins auf die tatsächlichen Keystores korrigiert
  (Release + Debug); Root-Domain-Datei für App-Links dokumentiert
- Demo-Modus: Credential-Hashing auf 600.000 PBKDF2-Iterationen angehoben
  (OWASP-2023-Empfehlung, identisch zur Backup-KDF)
- Datenschutz-Entwurf (intern) angelegt

## [0.7.0] – 2026-08-26

Security- & Privacy-Release: Umsetzung des umfassenden Sicherheitsaudits
(App, Edge Functions, Datenbank). **Enthält Pflicht-Migrationen (056–062)
und Edge-Function-Updates – zuerst ausrollen** (siehe
`releases/v0.7.0/RELEASE_NOTES.md`).

### Sicherheit

- **Jugendschutz serverseitig erzwungen**: Alters-Sichtbarkeits- und
  Paarungsregeln (16–17 getrennt; stufenweise ab 18) gelten jetzt in
  Profil-Sicht, Feeds, Likes, Matches, Random Chat und Dating Hour
- **Geburtsdatum unveränderlich** nach Registrierung (serverseitig)
- **Session im Keystore/Keychain** statt Klartext-Speicher
  (Access-/Refresh-Token)
- **E2E (Signal Protocol) repariert**: PreKeys überleben Neustarts,
  Bundle wird automatisch veröffentlicht, One-Time-Key-Rotation,
  SignedPreKey-Rotation (90 Tage), persistenter Identity-Trust mit
  Blockade + Warn-Dialog bei Schlüsselwechsel
- **Account-Löschung vollständig**: Storage-Objekte (Avatare,
  Intro-Audios, Verifizierungs-Videos) und alle lokalen Schlüssel/Daten
  werden entfernt; Fehler werden angezeigt statt verschwiegen
- **Anti-Trilateration**: max. 5 Standort-Änderungen/Tag,
  Speed-Plausibilität serverseitig, ~1-km-Rundung „at rest",
  gedrosselte Distanzabfragen
- Like-/Report-/Dating-Hour-Rate-Limits inkl. Schließung des direkten
  DB-Pfads für Likes
- Dating-Hour: Regressionen aus Migration 055 behoben (Blockier-Schutz
  wiederhergestellt, Scheduler wieder intern), Entscheidungen nach
  Session-Ende unveränderlich
- WebRTC: autorisierte Private Channels für Signaling, optionaler TURN
  (kurzlebige Credentials), SSRF-Guard für UnifiedPush-Endpunkte
- Cert-Pinning: Rotation-Fallback nur noch bei exakt gepinntem Intermediate

### Geändert

- **Registrierung ohne Einladungscode**: Invite-System komplett entfernt
  (Tabelle + RPCs gelöscht); Schutz läuft über CAPTCHA (Dashboard-Pflicht!)
  und Rate-Limits
- Passwort-Reset meldet alle Geräte ab (Global-SignOut)
- Match-Profil zeigt Alter statt Geburtsdatum; Anti-Fraud-Flag verlässt
  den Server nicht mehr
- Quiz-Antwortoptionen werden pro Match gemischt (kein „immer Antwort 1")
- Standort-Anzeige als grobe Region (~11 km) statt Koordinaten
- Entschlüsselte Sprachnachrichten werden nach dem Anhören gelöscht;
  Verifizierungs-Videos liegen app-privat statt im System-Temp
- Bilder werden vor Versand/Upload neu enkodiert (EXIF/GPS garantiert
  entfernt)

### Behoben

- Entschlüsselte Voice-Notes akkumulierten im Temp-Verzeichnis ohne
  Löschung
- Geburtsdaten fremder Nutzer konnten in Release-Logs landen
  (Debug-Guards ergänzt)
- `city`/`state`-Spalten fehlten in den Migrationen (Schema-Drift behoben)
- Doppelte Random-Chat-Warteschlangen pro Nutzer ausgeschlossen
  (partieller Unique-Index)

### Intern

- Persistente DB-Rate-Limits in `prekeys` und `process-location-check`;
  konstante Zeitvergleiche; `user_reports`-Retention (180 Tage);
  Standard-Privilegien für künftige Tabellen entfernt; `prekeys` own-only

## [0.6.1] – 2026-08-24 *(interner Stand, nie veröffentlicht – geht mit 0.7.0 erstmals raus)*

### Behoben

- **Automatischer Logout behoben**: Beim App-Neustart wurde die Session
  verworfen und dabei lokale Daten (Profil, Einstellungen, Präferenzen)
  mitgelöscht. Jetzt bleibt alles erhalten; nach erneutem Login ist
  sofort alles wieder da
- **CI-Pipeline grün**: Flutter auf 3.44.6 gepinnt (webview_flutter braucht
  Dart ≥ 3.10), `.env` wird im Workflow erzeugt, Actions auf v5,
  Signing-Prüfung wirft nur noch bei echten Release-Builds
- KGP-Warnung für `unifiedpush_android` behoben (lokaler Fork)
- Encoding-Nachbereinigung: doppelt kodierte Umlaute in diversen Dateien
  repariert

### Hinzugefügt

- **„Angemeldet bleiben"-Schalter** im Login (standardmäßig aktiv; wer ihn
  deaktiviert, wird beim App-Start bewusst zum Login geführt)
- **Sprache Deutsch/Englisch** – umschaltbar im Login-Screen und in den
  Einstellungen (Darstellung); Kernbereiche sind zweisprachig
- **Passkey-Diagnose** (Einstellungen → E2E-Identität): prüft Domain-
  Verknüpfung und Gerät und zeigt die genaue Ursache bei Passkey-Problemen
- **Dating Hour**: Gewohnheiten (Rauchen/Alkohol/Drogen) als weiche
  Matching-Präferenz wählbar; Anzeige als Chips im Event-Chat
- **„Funke"-Animation** beim Entstehen eines Funkens (Herz + Partikel)
- **Funke-Streak**: Flamme + Tageszähler seit dem Funke – in den Funken
  und im Chat-Header, ganz ohne Schreibpflicht
- **Gemeinsame Interessen** im fremden Profil hervorgehoben
- **Sichtbarer E2E-Status** im Chat-Header (Chip: grün = P2P verbunden)
- Einrichtung: Gewohnheiten jetzt Schritt 5; Profil- und Vorstellungs-
  Angaben sind Pflicht (Bio, mindestens ein Interesse, Text + Audio)
- Passkey und 2FA werden am Ende der Einrichtung **dringend empfohlen**
  (mit Direkt-Sprung zum Einrichten)
- **Neues Thestia-Logo**: rundes Logo überall (App, Splash day/night,
  Launcher-Icons, Adaptive-Icon, Fastlane) – generiert aus der neuen
  Basis-Grafik, Schriftzug vollständig lesbar
- App-Logo mit Dark-Variante (keine weißen Flächen mehr), Splash kleiner
- Desktop/Web: NavigationRail auf breiten Screens

### Geändert

- **„Match" heißt jetzt „Funke"** (Technik unverändert)
- Captcha-Dialog an die Cloudflare-Fenstergröße angepasst
- Theme-Picker mit einheitlichen Kachelgrößen
- Bild-Zuschnitt folgt dem aktiven Farbschema
- App-Titel überall „Thestia"

## [0.6.0] – 2026-08-24

### Hinzugefügt

- **Erscheinungsbilder**: 6 Farbschemata (Classic Thestia, Ozean, Wald,
  Sonnenuntergang, Lavendel, Schiefer) – wählbar in der Einrichtung
  (Schritt „Darstellung") und in den Einstellungen; gilt für Light UND Dark
- **Verschlüsseltes E2E-Key-Backup**: private Signal-Identität per
  Passwort (PBKDF2 + AES-256-GCM) sichern und auf neuem Gerät
  wiederherstellen; PreKeys werden nach dem Restore automatisch erneuert
- **Safety Center**: zentrale Hilfe-Seite bei Belästigung/Stalking mit
  direkten Hilfetelefonen (116 016, 116 006), In-App-Maßnahmen und
  Stalking-Leitfaden
- **Bild-Blur im Chat**: eingehende Bilder standardmäßig verpixelt,
  Freischalten nur nach Bestätigung; einzelne Bilder direkt melden →
  manuelle Prüfung durch den Support
- **Push ohne Google (UnifiedPush)**: F-Droid-Variante kann über eine
  Distributor-App (z. B. ntfy) Push empfangen – komplett ohne Firebase
- **Build-Flavors** `play` / `fdroid`: die fdroid-Variante enthält kein
  google-services-Plugin und startet ohne Firebase (`--dart-define=FDROID=true`)
- **Desktop-/Web-Navigation**: ab 1000 px Breite NavigationRail statt
  Bottom-Bar
- **Fastlane-Metadaten** (de/en) als Vorbereitung für die F-Droid-Einreichung
- CI-Job für den Google-freien F-Droid-Build

### Geändert

- **„Match" heißt jetzt „Funke"** – deutsche, warme Bezeichnung für die
  entstehende Verbindung (Technik und Datenmodell unverändert)
- **Angemeldet bleiben**: neuer Schalter im Login (standardmäßig AN).
  Ein automatischer Logout löscht keine lokalen Daten mehr – nach erneutem
  Login ist dein Profil wieder da
- **Einrichtung**: Gewohnheiten sind jetzt Schritt 5 (vor den
  Sicherheitsschritten); die Schritte Filter, Profil und Vorstellung sind
  Pflicht (Bio, mindestens ein Interesse, Text- UND Audio-Vorstellung)
- **Dating Hour**: Gewohnheiten als weiche Matching-Präferenz (wählbar in
  den Präferenzen, Anzeige als Chips im Event-Chat)
- **Passkey & 2FA werden dringend empfohlen**: deutlicher Hinweis am Ende
  der Einrichtung mit Direkt-Sprung zum Einrichten; neue Passkey-Diagnose
  in den Einstellungen zeigt die genaue Ursache bei Problemen
- **Sprache Deutsch/Englisch**: umschaltbar im Login-Screen und in den
  Einstellungen (Darstellung)
- **Captcha-Dialog** kompakter (an die Cloudflare-Fenstergröße angepasst)
- **Splash/Logo**: kleiner (60 %), Dark-Variante des Logos ohne weiße
  Flächen (App + nativer Splash in night-Dichteordnern)
- **Theme-Picker**: einheitliche Kachelgrößen
- Registrierung ist jetzt **ohne Einladungscode** offen (Bot-Schutz weiter
  über optionales CAPTCHA + Rate-Limits)
- GPS-Button beim Standortfeld sitzt als suffixIcon exakt am Eingabefeld –
  auch bei großer Systemschrift
- App-Titel überall „Thestia"

### Behoben

- **CI**: Actions auf v5 (Node-20-Deprecation behoben), `.env` wird im
  Workflow aus der Beispiel-Datei erzeugt (fehlendes Asset brach den
  Asset-Build ab)

### Entfernt

- **Präsenz-Metadaten komplett gestrichen**: kein Online-Status, kein
  „schreibt gerade…", keine Lesebestätigungen (siehe ADR-0007) – Dating
  soll zurück ins echte Leben

### Sicherheit

- Profil-PII (Geburtsdatum, Koordinaten) aus dem Klartext-Speicher in den
  Keystore migriert
- Cloud-Backups deaktiviert (`allowBackup=false`)
- Server: Feld-Whitelist für Partnerprofile, Blockier-Check bei Likes,
  Rate-Limits (u. a. QR-Codes), JWT-Pflicht für PreKey-Bundles,
  Beziehungspflicht für Push, search_path-Härtung aller SECURITY-DEFINER-
  Funktionen, Distanz nur in 5-km-Schritten (max. 200 km)
- Release-Build bricht ohne echtes Signing ab (kein stiller Debug-Fallback)

## [0.5.0] – 2026-08-23

### Erste öffentliche Beta 🎉

Thestia dreht das Prinzip klassischer Dating-Apps um: **Persönlichkeit zuerst**.
Fotos sieht man erst nach einem echten Kennenlernen – und alle Kommunikation läuft
Ende-zu-Ende-verschlüsselt direkt zwischen den Geräten.

### Hinzugefügt

- **Find your Match** – Blind-Matching über Vorstellungen (Text + Sprachnachricht,
  je 10 s bis 5 Min); Fotos erst nach gegenseitigem Bestätigen
- **Quiz „Wie gut kenn ich mein Match"** – Chat, Bilder und Anrufe werden bei
  Find-your-Match-Matches erst nach bestandenem Quiz freigeschaltet (serverseitig erzwungen)
- **Zufallschat** – anonymes Peer-to-Peer-Gespräch mit zufälliger Gegenstelle
- **QR Code** – Verbindung per Scan oder manuellem 8-stelligen Code (serverseitig auflösbar)
- **Dating Hour** – wöchentliches Event mit zufälligen 5-Minuten-Gesprächen;
  Match nur bei beidseitigem „Ja"; serverzeitbasiert (Anti-Cheat)
- **Spice Questions** – Eisbrecher-Fragen im Chat; Antworten werden erst sichtbar,
  wenn beide geantwortet haben
- **Profil**: Mood of the Day, Gewohnheiten (Rauchen/Alkohol/Drogen), Interessen,
  Bio, Bundesland, Land, Persönlichkeitstest (MBTI-Stil)
- **Entfernungsanzeige** in km zu anderen Nutzern (5-km-Schritte, serverseitig
  berechnet – exakte Koordinaten verlassen den Server nie)
- **Video-Verifizierung** (Beta): privater Upload, persönliche Prüfung durch den
  Support, Verifiziert-Badge im Profil
- **2FA** via Authenticator-App (TOTP) und **Passkeys** für passwortloses Login
- **Push-Benachrichtigungen** (nur Metadaten) mit Master- und Einzelschaltern;
  Dating-Hour-Erinnerung funktioniert auch bei geschlossener App
- **Bug Report** mit Screenshots; Privacy-Screen mit JSON-Datenexport
- Account-Löschung mit vollständiger lokaler Datenentfernung (DSGVO)

### Geändert

- Altersschutz-System: 16-/17-Jährige sind ab 20 Jahren unsichtbar, Filtergrenzen
  und Foto-Sichtbarkeit folgen gestuften Regeln
- Session-Restore synchron beim Start; serverseitige Validierung im Hintergrund

### Sicherheit

- Ende-zu-Ende-Verschlüsselung (Signal Protocol) + WebRTC-Peer-to-Peer mit
  Cert-Pinning für alle Supabase-Endpunkte
- Serverseitige Härtung: RLS auf allen Tabellen, Rate-Limits (Likes, Push,
  QR-Code-Abfragen), PreKey-Bundles nur mit gültigem JWT
- Lokale Speicherung: Tokens und Profil-PII ausschließlich im Keystore/Keychain,
  Hive AES-verschlüsselt
