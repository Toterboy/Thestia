# Datenschutzerklärung für Thestia

**Stand: September 2026** · Version 4 (v0.8.x)

Thestia ist ein datenschutzorientiertes Open-Source-Projekt (AGPLv3).
Der Schutz deiner persönlichen Sphäre steht an erster Stelle: Es werden
keine Werbetracker eingesetzt, keine Verhaltensprofile erstellt und keine
Nutzerdaten an Dritte verkauft.

---

## 1. Grundsatz und Verantwortliche Stelle

Verantwortliche Stelle im Sinne der DSGVO ist der Betreiber der
Thestia-Instanz (Hosting Supabase EU-Region). Kontaktaufnahme für alle
datenschutzbezogenen Anliegen: über das **In-App-Bug-Report-Formular**
(Einstellungen) oder das Issue-Tracker des öffentlichen
Projekt-Repositorys. Da Thestia als Community-Projekt betrieben wird,
kann die kontaktierbare Stelle je nach Instanz variieren; der Code ist
jederzeit öffentlich einsehbar und selbst hostbar.

**Prinzipien (Art. 5 DSGVO):** Datenminimierung, Zweckbindung,
Speicherbegrenzung, Datenschutz durch Technik (E2E, on-device) und
Transparenz. Es gibt **keine** Werbe-Ökosystem-Integration, **kein**
Tracking-Pixel und **keine** nutzerübergreifende Verhaltensanalyse.

## 2. Erhobene Daten und Verarbeitungszwecke

| Kategorie | Daten | Zweck | Löschung |
|---|---|---|---|
| Kontodaten | Name, E-Mail, Geburtsdatum, Geschlecht | Kontoverwaltung, Jugendschutzfilter (serverseitig erzwungen) | Mit Account-Löschung |
| Standortdaten | Koordinaten (einmalig bei Freigabe) | Entfernungsberechnung; exakte Koordinaten verlassen den Server nicht | Mit Account-Löschung |
| Standortanzeige | 5-km-gerundete Entfernung (~11 km Genauigkeit für Koordinaten-Näherung) | Andere Nutzer sehen nur gerundete Werte | – |
| Profilangaben | Bio, Interessen, Audio-Vorstellung, Gewohnheiten (Rauchen/Alkohol/Drogen), Mood, Musik-Geschmack, **Profilbild** (siehe Abschnitt 3a) | Vermittlung passender Kontakte („Funken") | Mit Account-Löschung |
| Geräte-Liste | Gerätemodell (Hersteller + Modellkennung, z. B. „Samsung SM-S921B"), Plattform, App-Version, Zeitstempel der letzten Anmeldung | Anzeige „Wo bin ich eingeloggt?" + „Überall abmelden" (Migration 071/078); kein Standort, keine Seriennummer, keine Werbe-ID | Automatisch beim Abmelden; mit Account-Löschung |
| Präferenzen | Suchradius, Altersspanne, Geschlechts-Filter, „Ich suche", Farbwelt, UI-Schalter (Blind Mode, Sichtbarkeit, Benachrichtigungen) | Wiederherstellung nach Neuinstallation (Migration 066/071/074/076) | Mit Account-Löschung |
| Push-Tokens | FCM-Token (nur Play) bzw. UnifiedPush-Endpunkt (F-Droid) | Zustellung von Push-Signalen **ohne Nachrichteninhalt** | Mit Account-Löschung / Abmelden |
| Verifizierung | Beta-Funktion, derzeit deaktiviert | – | – |

## 3. Ende-zu-Ende-Verschlüsselung (Signal-Protokoll & P2P)

Sämtliche regulären Chat-Nachrichten, Bilder und Sprachanrufe zwischen
Nutzern werden Ende-zu-Ende über das **Signal-Protokoll** verschlüsselt
und direkt **Peer-to-Peer (WebRTC)** übertragen. Weder die Betreiber noch
zwischengeschaltete Server können Nachrichteninhalte einsehen.

- Identitäts- und Sitzungsschlüssel werden im verschlüsselten
  Geräte-Keystore (Android Keystore / iOS Keychain) gehalten.
- Ein optionales, **passwortverschlüsseltes Key-Backup** (PBKDF2 +
  AES-256-GCM) erlaubt den Gerätewechsel; der Schlüssel liegt ausschließlich
  beim Nutzer. Verlust von Backup **und** Passwort ist unwiederbringlich –
  daraus kann keine Datenwiederherstellung durch das Team erfolgen.

## 3a. Verschlüsselte Profilbilder (neu ab v0.8.x)

Profilbilder werden **bereits auf deinem Gerät** per AES-256-GCM
verschlüsselt, bevor sie hochgeladen werden. Der Server (Supabase
Storage, privater Bucket) speichert ausschließlich den Ciphertext – auch
bei einem Storage-Zwischenfall sind die Bilder unlesbar. Der Ent-
schlüsselungs-Schlüssel wird zufällig pro Bild erzeugt und im eigenen
Profil-Eintrag mitgeführt; nur Personen, die dein Profil sehen dürfen
(Sichtbarkeits-Einstellung + Altersschutz), laden und entschlüsseln das
Bild lokal. Zusätzlich läuft vor jedem Upload eine **rein lokale
NSFW-Vorprüfung** (ONNX-Modell on-device): Bilde-Bytes, Scores und
Ergebnis verarbeiten sich ausschließlich auf dem Gerät; bei Nicht-
bestehen verlässt das Bild dein Gerät nicht (Einspruch mit manueller
Team-Prüfung ist möglich).

## 4. Lokaler Chat-Verlauf (optional) und lokaler KI-Reflexions-Chat (Sanctuary, geplant ab v0.10.0)

**Lokaler Chat-Verlauf (seit v0.8.x):** Auf Wunsch speichert die App
Chats verschlüsselt (AES-256, SecureHive; Schlüssel im Keystore) lokal
auf dem Gerät – wählbar zwischen „Aus", „200 Nachrichten pro Chat" und
„Kompletter Verlauf" (Standard). Die Daten verlassen das Gerät nicht und
können jederzeit durch Deaktivieren gelöscht werden. Der JSON-Datenexport
enthält den Verlauf (Einsicht/Übertragbarkeit), der Import stellt ihn
wieder her.

Der integrierte Reflexions-Assistent läuft vollständig lokal
(„On-Device") auf deinem Smartphone. Sämtliche Texteingaben, hochgeladene
Screenshots und generierte Antworten verbleiben ausschließlich auf deinem
Gerät und werden zu keinem Zeitpunkt an externe Server übertragen.

- Chatverläufe verbleiben **flüchtig im RAM** oder werden optional **rein
  lokal AES-verschlüsselt** in Hive abgelegt (Standard: flüchtig).
- Die Krisen-Erkennung (Regex auf suizidbezogene Begriffe) läuft
  ausschließlich lokal; angezeigt werden dann Notfallkontaktdaten
  (Telefonseelsorge 0800 111 0 111 / 0800 111 0 222, Nummer gegen Kummer
  116 111). Es werden **keine** Analyse- oder Meldungsdaten erzeugt.
- Die „Modellqualität beanstanden"-Funktion übermittelt ausschließlich
  den vom Nutzer freigegebenen Textauszug sowie Modell-Metadaten
  (Modellname, Quantisierung, App-Version) – niemals vollständige
  Chatverläufe.
- Modell-Downloads (GGUF) sind nutzerinitiiert und erfolgen direkt von
  Hugging Face; die App übermittelt dabei keine zusätzlichen Metadaten.

## 5. Meldesystem und Missbrauchsschutz

- Chat-Bilder werden im Regelbetrieb **niemals serverseitig gescannt**.
- Meldet ein Empfänger ein empfangenes Bild, wird dieses **lokal auf dem
  Gerät** per ONNX-Modell vorbewertet. Der Meldende sieht das Ergebnis
  und entscheidet: Nur nach expliziter Bestätigung wird das betroffene
  Bild nebst den **letzten drei Textnachrichten** verschlüsselt an die
  Administration zur manuellen Prüfung übertragen.
- Meldungen sind **pseudonymisiert**: Die Identität des Meldenden wird dem
  Gemeldeten niemals offengelegt (technisch SHA-256-Hash, Migration 069).
- Berichte über unzureichende Modellqualität im Reflexions-Chat enthalten
  ausschließlich den vom Nutzer freigegebenen Textauszug sowie
  Modell-Metadaten.

## 6. Datenweitergabe und Drittanbieter

| Anbieter | Daten | Zweck | Region |
|---|---|---|---|
| Supabase (EU-Region) | Kontodaten, verschlüsselte Authentifizierungs-Token, Profildaten | Hosting von Accounts, DB, Auth | EU (Verarbeitungsvertrag über Supabase Europe B.V.) |
| Firebase Cloud Messaging (nur Play-Store-Version) | Push-Token, „stumme" Push-Signale | Zustellsignal; Inhalte werden danach lokal per WebRTC/E2E geladen | Google-Infrastruktur (verarbeitet nur das Token) |
| UnifiedPush (F-Droid-Version, z. B. ntfy) | Push-Endpunkt | Google-freie Push-Zustellung | Selbst wählbar (kann vollständig selbst gehostet sein) |
| Brevo | E-Mail-Adresse | Transaktions-E-Mails (Bestätigung, Passwort-Reset, Bug-Report-Kopie) | EU |
| Cloudflare | CAPTCHA-Token (Turnstile), TURN-Relay für WebRTC | Bot-Schutz; Relais sieht **keine** Inhalte (E2E) | Global (EU-PoP bevorzugt) |
| Netlify | CAPTCHA-Zwischenseite | Hosting der Anmelde-/CAPTCHA-Seite | Global |
| Hugging Face | Keine Nutzerdaten | Ausschließlich für den optionalen, nutzerinitiierten Download frei verfügbarer KI-Modelldateien (GGUF) | Global |
| Codeberg e.V. (geplant ab v0.11.0) | Keine personenbezogenen Daten | Trackerfreies Hosting der Flutter-Web-Artefakte (statische Dateien) | Berlin, Deutschland |

**Keine** Weitergabe an Werbenetzwerke, Datenbroker oder
Analyse-Dienste. **Keine** Nutzung von Google Analytics, Crashlytics oder
ähnlichen Produkten (Bug-Reports laufen über das In-App-Formular und
enthalten nur die vom Nutzer geprüften Angaben).

## 7. Speicherfristen und Kontolöschung

Du hast jederzeit das Recht auf vollständige Löschung deines Kontos
(**Art. 17 DSGVO – Recht auf Löschung**).

- Bei Ausführung der In-App-Funktion **„Account löschen"** (unter
  Datenschutz & Account, mit 2FA-Bestätigung) werden alle
  personenbezogenen Daten auf den Servern unverzüglich und unwiderruflich
  entfernt: Profil, Nachrichten-Metadaten, Likes/Matches, Reports-Bezug,
  Geräte-Liste, Push-Token, Signal-PreKeys und Storage-Dateien
  (Avatar/Audio).
- Lokale Datenbanken auf dem Gerät werden im selben Zug bereinigt
  (E2E-Identität, Verifizierungsdaten, Temp-Dateien).
- Technisch notwendige Restdaten (z. B. Ban-Einträge gegen Umgehung von
  Jugendschutz-Sperren) werden nur so lange gespeichert, wie gesetzlich
  bzw. zweckgebunden erforderlich (Art. 6 Abs. 1 lit. f DSGVO) und
  anschließend gelöscht.
- Flüchtige Web-Gast-Sitzungen (geplant ab v0.11.0) zerstören sich
  serverseitig nach 24–48 Stunden rückstandslos.

## 8. Deine Rechte (Art. 15–21 DSGVO)

- **Auskunft (Art. 15):** Der In-App-Datenexport („Meine Daten
  exportieren") liefert alle personenbezogenen Daten als JSON-Download.
- **Berichtigung (Art. 16):** Alle Profilfelder sind in der App frei
  editier- und löschbar.
- **Löschung (Art. 17):** Siehe Abschnitt 7.
- **Einschränkung/Widerspruch (Art. 18/21):** Über die Kontaktwege in
  Abschnitt 1.
- **Datenübertragbarkeit (Art. 20):** JSON-Export über die In-App-
  Funktion.
- **Beschwerderecht (Art. 77):** Bei einer Aufsichtsbehörde, z. B. der
  Landesdatenschutzbehörde.

## 9. Kinder- und Jugendschutz

Die Nutzung ist ab **16 Jahren** gestattet. 16- und 17-Jährige sind
serverseitig strikt getrennt: Sie sehen ausschließlich andere
Minderjährige, Fotos sind für Erwachsene technisch unsichtbar (Blind Mode
erzwungen), und die Altersfilter sind serverseitig begrenzt (Migration
056). Geburtsdaten werden zur Durchsetzung dieses Jugendschutzes
verarbeitet (Art. 6 Abs. 1 lit. c/f) und gegenüber anderen Nutzern nie
angezeigt (nur gerundetes Alter).

## 10. Änderungen dieser Erklärung

Bei funktionalen Änderungen (neue Datenkategorien, neue Anbieter) wird
diese Erklärung in der App und im Repository aktualisiert; die
Änderungshistorie ist über die Versionszeile am Dokumentkopf und die
Git-Historie nachvollziehbar.

---

### Historie

| Version | Datum | Änderung |
|---|---|---|
| 4 | 2026-09 | Verschlüsselte Profilbilder + on-device NSFW-Vorprüfung (3a), lokaler Chat-Verlauf (3 Modi), Gerätemodell in der Geräte-Liste (078), Präferenzen-/UI-Sync (074/076) ergänzt |
| 3 | 2026-09 | Sanctuary (on-device KI), Geräte-Liste (071), Web-Bridge/Codeberg (0.11.0-Ausblick), Rechte-Kapitel ergänzt |
| 2 | 2026-08 | UnifiedPush, NSFW-Melde-Workflow, Ban-Einträge |
| 1 | 2026-07 | Erste öffentliche Fassung (Beta) |
