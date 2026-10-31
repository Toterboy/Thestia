# Datenschutzerklärung für Thestia

**Stand: Oktober 2026** · Version 17 (v0.10.0)

Thestia ist ein datenschutzorientiertes Open-Source-Projekt (AGPLv3).
Der Schutz deiner persönlichen Sphäre steht an erster Stelle: Es werden
keine Werbetracker eingesetzt, keine Verhaltensprofile erstellt und keine
Nutzerdaten an Dritte verkauft.

---

## 1. Grundsatz und Verantwortliche Stelle

**Kontakt:** Fragen zur Verarbeitung deiner Daten, Auskunft, Berichtigung
oder Löschung erreichst du über das In-App-Bug-Report-Formular
(*Einstellungen → Datenschutz → Bug melden*) oder über die
**Kontaktadresse `datenschutz@thestia.de`**. Für eine Löschung auf
Anfrage nenne deine User-ID - dann werden auch die nach dem obigen
aufgeführten Restdaten entfernt.

Verantwortliche Stelle im Sinne der DSGVO ist **Thestia**, das Projekt
von Thoralf Illg (Store-Eintrag: *Thestia*). Kontaktaufnahme für alle
datenschutzbezogenen Anliegen: über das **In-App-Bug-Report-Formular**
(Einstellungen) oder per E-Mail an `datenschutz@thestia.de`. Für die
Anbieterkennzeichnung nach § 5 DDG (Impressum) siehe
<https://auth.thestia.de/impressum>.

Die serverseitige Verarbeitung erfolgt in der EU-Region von Supabase
(Vertragspflichten als Auftragsverarbeiter nach Art. 28 DSGVO, siehe
Abschnitt 6). Der Quellcode ist öffentlich einsehbar und selbst
hostbar; betreibt jemand eine eigene Instanz, ist diese Instanz
selbst Verantwortliche Stelle, und zwar unter ihrem eigenen Namen.

**Prinzipien (Art. 5 DSGVO):** Datenminimierung, Zweckbindung,
Speicherbegrenzung, Datenschutz durch Technik (E2E, on-device) und
Transparenz. Es gibt **keine** Werbe-Ökosystem-Integration, **kein**
Tracking-Pixel und **keine** nutzerübergreifende Verhaltensanalyse.

## 2. Erhobene Daten und Verarbeitungszwecke

| Kategorie | Daten | Zweck | Löschung |
|---|---|---|---|
| Kontodaten | Name, E-Mail, Geburtsdatum, Geschlecht | Kontoverwaltung, Jugendschutzfilter (serverseitig erzwungen) | Mit Account-Löschung |
| Standortdaten | Bundesland sowie Koordinaten, vor dem Speichern auf ein 5-km-Raster gerundet | Entfernungsberechnung; die Koordinaten liegen ausschließlich in einer nur für den Eigentümer lesbaren Tabelle und verlassen den Server nicht | 30 Tage nach dem letzten Standortschreiben; mit Account-Löschung |
| Standortanzeige | Entfernung in Stufen von 10 km, nur wenn die betroffene Person das **eingeschaltet** hat; unter 5 km wird nichts angezeigt | Andere Nutzer sehen nur die Stufe, nie einen Wert in Metern oder Kilometern. Ohne Einschaltung sehen sie gar keine Entfernung | – |
| Ortsangabe | Wird nicht erhoben | Seit v0.10.0 wird kein Ort, keine Stadt und kein Postleitzahl-Bereich gespeichert oder angezeigt – nur das Bundesland | – |
| Profilangaben | Bio, Interessen, Audio-Vorstellung, Gewohnheiten (Rauchen/Alkohol/Drogen), Mood, Musik-Geschmack, **Profilbild** (siehe Abschnitt 3a) | Vermittlung passender Kontakte („Funken") | Mit Account-Löschung |
| Geräte-Liste | Gerätemodell (Hersteller + Modellkennung, z. B. „Samsung SM-S921B"), Plattform, App-Version, Zeitstempel der letzten Anmeldung | Anzeige „Wo bin ich eingeloggt?" + „Überall abmelden" (Migration 071/078); kein Standort, keine Seriennummer, keine Werbe-ID | Automatisch beim Abmelden; mit Account-Löschung |
| Präferenzen | Suchradius, Altersspanne, Geschlechts-Filter, „Ich suche", Farbwelt, UI-Schalter (Blind Mode, Sichtbarkeit, Benachrichtigungen) | Wiederherstellung nach Neuinstallation (Migration 066/071/074/076) | Mit Account-Löschung |
| Push-Tokens | FCM-Token (nur Play) bzw. UnifiedPush-Endpunkt (F-Droid) | Zustellung von Push-Signalen **ohne Nachrichteninhalt** | Mit Account-Löschung / Abmelden |
| Aussehen-Merkmale (Transit Spark) | Kategorie und Wert eines Merkmals (Kleidung je Kategorie, Kopfbedeckung, Schuhe, Accessoires, Haarfarbe/-länge/-frisur, Augenfarbe) sowie die zugehörige Farbangabe, jeweils als Liste von bis zu acht Werten | Merkmals-Abgleich in Transit Spark: "was ich an dir bemerkt habe" gegen "was du über dich sagst". Nur die Auswahl wird übertragen, nicht der Zweck | Nach 24 Stunden (Cron `cleanup-transit-signals`) |
| Land | Wohnsitzland (DE, AT, CH und weitere) | Anzeige des Landes im Profil und bei Match-Partnern | Mit Account-Löschung |
| Gerätekennung | Zufällige Kennung des Geräts (UUID, keine MAC-Adresse, keine Werbe-ID) | Anmeldung deiner eigenen Geräte für die Ende-zu-Ende-Verschlüsselung | Automatisch beim Abmelden; mit Account-Löschung |
| Bild-Prüfhash | SHA-256-Hash eines von dir gesendeten Chatbildes, zusammen mit der Kennung des Empfängers | Nachweis, dass ein gemeldetes Bild tatsächlich in einem Chat geflossen ist (Missbrauchsschutz gegen willkürliche Meldungen) | Mit Account-Löschung |
| Standort-Zeitstempel | Zeitpunkt der letzten Standortprüfung | Plausibilitätsprüfung (unplausible Ortswechsel) | Mit Account-Löschung |
| Merkzeichen des Kontos | MD5-Hash der Kontokennung | Verhinderung, dass ein gelöschtes Konto erneut registriert wird | Bleibt dauerhaft bestehen, ohne Klarnamen |
| Verifizierung | Selbstaufnahme mit Bild **und Ton** zur Schätzung des Alters. Das Video wird **auf dem Gerät verschlüsselt** (AES-256-GCM) und nur der Chiffrat übertragen; der Schlüssel liegt in einer Tabelle, auf die die App keinen Zugriff hat. Zweck: Altersprüfung für den Jugendschutz und die 18+-Freigabe von Transit Spark. Bei Ablehnung werden Video und Schlüssel gelöscht, sonst nach spätestens 30 Tagen nach Einreichung (Abschnitt 7). Nur bei einer manuellen Sichtung durch die Administration entsteht kurzzeitig eine entschlüsselte Kopie, die nach 20 Minuten automatisch gelöscht wird |

## 3. Ende-zu-Ende-Verschlüsselung (Signal-Protokoll)

Sämtliche regulären Chat-Nachrichten, Bilder und Sprachanrufe zwischen
Nutzern werden Ende-zu-Ende über das **Signal-Protokoll** verschlüsselt.
Weder die Betreiber noch zwischengeschaltete Server können
Nachrichteninhalte einsehen.

- **Übertragungsweg:** Direkte Peer-to-Peer-Verbindung (WebRTC) wird
  versucht; gelingt sie nicht, übernimmt der Server **ausschließlich den
  Transport des verschlüsselten Chiffrats** (Relay-Fallback). Die
  Verschlüsselung ist in beiden Fällen Ende-zu-Ende und identisch – der
  Server sieht und verarbeitet in keinem Fall Klartext. Auf die
  Verbindungsqualität hat das keinen Einfluss, auf die Privatsphäre
  ebenso wenig.
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

## 3b. Nahbereichsfunk (BLE, „Transit Spark")

Transit Spark nutzt Bluetooth Low Energy, damit zwei Personen sich in der
Nähe begegnen können, ohne sich ansprechen zu müssen. Dabei werden
Funk-Metadaten verarbeitet.

**Was gesendet wird:** ein ephemerer, zufälliger Token (keine Geräte-ID,
kein Name, keine MAC-Adresse des Geräts). Der Stack des Betriebssystems
vergibt für das Advertising eine auflösbare Privatadresse; die App setzt
keine feste Adresse.

**Was empfangen wird:** der Scanner ist seit v0.9.2 auf die Hersteller-ID der
App gefiltert. Vorher verarbeitete er jedes Bluetooth-Signal in Reichweite
(Uhren, Kopfhörer, Beacons); das ist korrigiert.

**Was lokal bleibt:** Begegnungen (Token, Zeitstempel, stärkstes RSSI) werden
ausschließlich auf dem Gerät gespeichert, mit einer Vorhaltezeit von
45 Minuten, danach automatische Löschung. Sie werden nicht an den Server
übertragen.

**Was der Server sieht:** sobald eine Person den Radarscan startet, wird deren
eigenes anonymes Token auf dem Server hinterlegt – ohne das könnte gar
keine Begegnung zustande kommen. Erst wenn beide Personen ausdrücklich
bestätigen ("Blicke getauscht"), werden die zuletzt beobachteten Tokens,
die gewählten Merkmale und die von der Person angegebene
Selbstbeschreibung zur Prüfung übermittelt. Der Server
prüft Alter und Blockierstatus. Aus einem Token lässt sich keine
Geräte-Identität ableiten.

**Merkmale im Klartext:** Die gewählten Merkmale (Kategorie, Wert, Farbe)
und die freitextliche Selbstbeschreibung liegen als Klartext in
`transit_signals` – anders als Chat-Nachrichten, die als Chiffrat
transportiert werden. Grund: die Merkmale sind der Matching-Input, und
ein Chiffrat könnte nicht verglichen werden. Sie sind nur für die
Gegenseite bestimmt und werden nach 24 Stunden gelöscht.

**Merkmale einer dritten Person:** Die Merkmale, die du an einer anderen
Person bemerkt hast, sind Aussehensdaten über jemanden, der selbst nichts
davon weiÕ. Sie werden ausschließlich im Transit-Matching
verwendet, nicht angezeigt und nicht an Dritte weitergegeben. Die
Selbstbeschreibung (dein eigenes Aussehen) sieht dagegen nur die Person,
mit der du dich getroffen hast.

**Verminderung des Funk-Fingerprints:** Das Advertising wird in
unregelmäßigen Abständen neu gestartet und das Encounter-Token wird nicht
in einem starren Zeitraster gewechselt. Damit ist das Sendemuster nicht
sessionübergreifend konstant. Ein vollständiger Schutz gegen das
Mitschreiben des Funks ist damit nicht verbunden: Bluetooth ist ein
Funkmedium und im Umfeld beobachtbar.

**Keine Ortung:** Transit Spark ermittelt keine Position per Funk. Der
Standort wird nur für die Entfernungsanzeige der Profile verwendet und
dient serverseitig nach 30 Tagen der Löschung (Migration 129, Cron
`purge_stale_locations`).

**Gespeichert wird nicht der Standort, sondern ein Rasterpunkt:** Seit
v0.10.0 werden Koordinaten vor dem Speichern auf ein Raster von 5 km
gerundet – serverseitig erzwungen, nicht nur in der App. Wer in einem
Land mit Millionen Einwohnern wohnt, kann aus diesen Daten keinen
Wohnort ableiten. Der Ort selbst wird nicht erhoben, angezeigt oder
gespeichert; sichtbar ist ausschließlich das Bundesland.

**Entfernungsanzeige ist Zustimmungssache:** Die Anzeige ist
standardmäßig aus und muss pro Person eingeschaltet werden. Aus bedeutet
serverseitig `null` – es wird keine Restentfernung aus dem Bundesland
zurückgerechnet. Eingeschaltet bedeutet: andere sehen eine Stufe von
10 km, keine Zahl.

## 3c. Lokale Kontaktdaten („Connect to others") und Sicherheits-Aufklärung

**Kontaktdaten (freiwillig, ausschließlich lokal):** In „Connect to
others" kannst du freiwillig eine Telefonnummer sowie Handles für Signal,
Threema, Instagram, Snapchat, Discord oder eigene Apps hinterlegen. Diese
Angaben werden **ausschließlich auf deinem Gerät** im verschlüsselten
Keystore (Android) bzw. in der Keychain (iOS) gespeichert – in einem
eigenen Speicherbereich (`SecureNamespaces.contacts`). Sie werden **nicht
an Supabase, an Thestia-Server oder an Dritte übertragen** und nicht
serverseitig gesichert. Ein Gerätewechsel oder eine Neuinstallation
überträgt sie nicht.

Geteilt werden die Angaben nur, wenn du in der App aktiv auf „Teilen"
oder „Kopieren" tippst: „Teilen" übergibt den von dir erzeugten Text an
das Betriebssystem (Share-Sheet), „Kopieren" legt ihn in die
Zwischenablage. Was danach mit dem Text geschieht, liegt außerhalb
unseres Einflussbereichs. Du kannst die Angaben jederzeit im Formular
entfernen und erneut speichern; mit dem Löschen der App-Daten werden sie
ebenfalls entfernt. Telefonnummern werden vor dem Speichern auf ein
gültiges Format geprüft, aber nicht an einen Server zur Validierung
gesendet.

**Sicherheits-Aufklärung vor dem Setup:** Nach der E-Mail-Bestätigung
fragt die App, ob du schon einmal eine Dating-App benutzt hast und ob dir
die Gefahren beim Online-Dating bewusst sind. Die Antworten (Ja/Nein),
der aktuelle Schritt und die Startzeit der Aufklärung werden **nur lokal**
in den App-Einstellungen (SharedPreferences) gespeichert, damit der
Ablauf nach einem Neustart fortgesetzt werden kann. Sie werden nicht an
den Server übertragen und nicht für Profiling oder Werbung genutzt. Die
Aufklärung dauert höchstens fünf Minuten; die ausführliche Fassung steht
unter <https://auth.thestia.de/dating-sicherheit>.

## 4. Lokaler Chat-Verlauf (optional) und lokaler KI-Reflexions-Chat (Sanctuary, geplant ab v0.11.0)

**Lokaler Chat-Verlauf (seit v0.8.x):** Auf Wunsch speichert die App
Chats verschlüsselt (AES-256, SecureHive; Schlüssel im Keystore) lokal
auf dem Gerät – wählbar zwischen „Aus", „200 Nachrichten pro Chat" und
„Kompletter Verlauf" (Standard). Die Daten verlassen das Gerät nicht und
können jederzeit durch Deaktivieren gelöscht werden. Der JSON-Datenexport
enthält den Verlauf (Einsicht/Übertragbarkeit), der Import stellt ihn
wieder her.

Der folgende Reflexions-Assistent ist **geplant für v0.11.0** und
noch nicht Teil dieser Version; die Beschreibung gilt dem
geplanten Stand. Sämtliche Zusagen dieses Abschnitts - lokal,
ohne Übertragung - sind erst mit der Veröffentlichung
einschlägig.

Geplant läuft er vollständig lokal
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
  Bild an die
  Administration zur manuellen Prüfung übertragen. Der Bildinhalt wird
  dabei zur automatischen Einordnung an einen **externen KI-Dienst**
  (Abschnitt 6) weitergegeben; eine automatische Entscheidung über eine
  Meldung wird daraus nicht getroffen.
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
| Spaceship (Domain- und Mail-Hosting) | Empfängeradresse, bei eingehenden Mails der Absender, bei ausgehenden Mails der Inhalt der Transaktions-Mail; beim Weiterleiten der Kinderschutz-Meldung der vollständige Meldungsinhalt | Weiterleitung eingehender Mails an das Postfach der Kontaktperson; Versand der Transaktions-Mails über den Mail-Relay des Providers | EU (Niederlande/USA, je nach Relay) |
| Brevo | E-Mail-Adresse; bei einem Bug-Report zusätzlich die von dir angegebene Beschreibung, Geräteinformationen, deine User-ID und bis zu fünf Screenshots; bei einer Bildmeldung das gemeldete Bild | Transaktions-E-Mails (Bestätigung, Passwort-Reset, Bug-Report), Kopie an den Support, manuelle Sichtung gemeldeter Bilder | EU |
| Mailjet (optional, derzeit nicht konfiguriert) | E-Mail-Adresse, Bestätigungs- und Bestätigungslinks | Versand der Transaktions-E-Mails (Registrierungsbestätigung, Passwort-Reset), falls Mailjet konfiguriert ist; andernfalls versendet Brevo | Frankreich (EU) |
| Cloudflare | CAPTCHA-Token (Turnstile) | Bot-Schutz | Global (EU-PoP bevorzugt) |
| Netlify | CAPTCHA-Zwischenseite, Datenschutzerklärung | Hosting der Anmelde-/CAPTCHA-Seite und der veröffentlichten Datenschutzerklärung | Global |
| Hugging Face | Beim Melden eines Bildes: der **Bildinhalt** (zur automatischen Einordnung als anständig oder unauffällig); beim Download einer KI-Modelldatei: keine personenbezogenen Daten | Automatische Vorauswertung gemeldeter Bilder; ansonsten ausschließlich der optionale, nutzerinitiiierte Download frei verfügbarer KI-Modelldateien (GGUF) | Global |
| STUN-Server (nextcloud/Hetzner, miwifi/OVH, voipgate, voipstunt) | Deine IP-Adresse | Ermittlung der öffentlichen Adresse für den Direktverbindungsversuch bei Video- und Sprachanrufen; über diese Server wird kein Inhalt übertragen | Deutschland, Frankreich, Niederlande (EU) |
| Codeberg e.V. (geplant ab v0.12.0) | Keine personenbezogenen Daten | Trackerfreies Hosting der Flutter-Web-Artefakte (statische Dateien) | Berlin, Deutschland |

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
- Flüchtige Web-Gast-Sitzungen (geplant ab v0.12.0) zerstören sich
  serverseitig nach 24–48 Stunden rückstandslos.
- Transit-Spark-Signale (Tokens, Merkmale, Selbstbeschreibung) werden nach
  24 Stunden automatisch gelöscht (Cron `cleanup-transit-signals`).
- Das Verifikations-Video wird verschlüsselt gespeichert (nur der Chiffrat
  liegt dauerhaft im Speicher). Bei der Sichtung durch die Administration
  entsteht kurzzeitig eine entschlüsselte Kopie, die nach 20 Minuten
  automatisch gelöscht wird. Das Video selbst wird nach spätestens
  30 Tagen nach Einreichung gelöscht - zusammen mit seinem Schlüssel
  (Cron `cleanup-verification-videos`).

## 8. Deine Rechte (Art. 15–21 DSGVO)

- **Auskunft (Art. 15):** Der In-App-Datenexport („Meine Daten
  exportieren") liefert die auf deinem Gerät gespeicherten personenbezogenen
  Daten als JSON-Download. Daten, die ausschließlich auf dem Server liegen
  (z. B. Matches, Likes, gemeldete Inhalte, deine Geräteliste), holen wir
  auf Anfrage bei uns nach – schreibe uns dazu.
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

**Transit Spark ist davon ausgenommen und nur ab 18 Jahren nutzbar.**
Die Sperre sitzt an zwei Stellen, weil eine allein nichts taugt:

- **Im Gerät**, fail-closed: fehlt das Geburtsdatum, gilt die Person
  nicht als nachgewiesen volljährig und wird gesperrt - nicht etwa
  freigelassen.
- **In der Datenbank**, für den Radar, das Matching und die
  Kontaktaufnahme (`transit_spark_adult()`, Migration 131). Geprüft
  wird dort zusätzlich die gefundene Person, weil die übliche
  Altersband-Regel sonst auch 16-Jährige zuließe. Alte
  RPC-Signaturen wurden entfernt, weil sie die Sperre umgangen hätten.

Voraussetzung für die Freigabe ist die Altersverifikation aus
Abschnitt 2: Sie nutzt Kamera **und** Mikrofon und fragt beide erst
nach einem erklärenden Dialog an, der verrät, wofür sie gebraucht
werden.

**Massgebliches Alter (v0.10.0):** Fuer den Jugendschutz zählt das Alter, das
per Video **verifiziert** wurde - nicht die Angabe im Profil. Ein Konto
ohne Verifizierung erscheint in keiner Begegnungsliste; die Angabe im
Profil wirkt erst nach der Verifizierung. Wer sich mit einem falschen
Geburtsdatum anmeldet, wird deshalb nicht als erwachsen behandelt,
sondern gar nicht erst vorgeschlagen.

**Beidseitige Sichtbarkeit (v0.10.0):** Wer 16 oder 17 Jahre alt ist,
sieht ausschließlich Personen, die ebenfalls 16 oder 17 Jahre alt sind
– niemals einen Erwachsenen. Und ein Erwachsener sieht niemals eine
Person unter 18. Das gilt in beide Richtungen, nicht nur in einer: der
Filter beruht auf einem Vergleich beider Altersangaben. Die Altersspanne
im Profil ist nach unten auf 10 Jahre unter dem eigenen Alter begrenzt
(und nie unter 18, sobald du volljährig bist) - wer eine grössere
Altersdifferenz wählt, bekommt sie serverseitig nicht geliefert.

**Verpflichtende Kinderschutz-Standards (v0.10.0):** Google Play verlangt
für Dating-, Social- und Random-Chat-Apps unabhängig von einer
Altersbeschränkung vier Dinge, die wir über die App und über eine
öffentliche Seite bereitstellen:

- Ein **ausdrückliches Verbot** von Kindesmissbrauch und sexueller
  Ausbeutung von Kindern (CSAE/CSAM) in den in der App akzeptierten
  Community-Standards.
- Eine **benannte Kontaktperson** für Hinweise auf Kindesmissbrauch.
- Ein **beschriebener Meldeweg**: in der App über die Meldung mit dem
  Grund „Hinweis auf Kindesmissbrauch (CSAE/CSAM)“, per E-Mail an die
  Kontaktperson oder bei unmittelbarer Gefahr direkt an Polizei oder
  Notruf.
- Ein dokumentierter **Prozess bei Bekanntwerden** solcher Fälle:
  vorrangige Prüfung, Sperre des Kontos bis zum Abschluss, Entfernung
  des Inhalts und Meldung bestätigter Fälle an die zuständigen
  Stellen.

Die öffentliche Seite liegt unter
<https://auth.thestia.de/kinderschutz>. Die Kontaktperson wird auf dieser
Seite namentlich genannt.
## 10. Angriffsbild und Risikoabschätzung

Die technische Bewertung der Verarbeitung ist öffentlich: das
Angriffsbild findest du unter
<https://auth.thestia.de/threat-model.md>. Die Risiken nach Art. 35
DSGVO nach Art. 35 DSGVO (Datenschutz-Folgenabschätzung) liegen als
Entwurf vor und sind noch nicht rechtlich geprüft; wir stellen sie auf
Anfrage zur Verfügung. Dort sind auch die Punkte benannt, die Thestia
bewusst **nicht** zusichert:
Funk-Metadaten sind technisch beobachtbar, und Ende-zu-Ende-
Verschlüsselung schützt Inhalte, nicht Kommunikationsmuster.

## 11. Änderungen dieser Erklärung

Bei funktionalen Änderungen (neue Datenkategorien, neue Anbieter) wird
diese Erklärung in der App und im Repository aktualisiert; die
Änderungshistorie ist über die Versionszeile am Dokumentkopf und die
Git-Historie nachvollziehbar.

---

### Historie

| Version | Datum | Änderung |
|---|---|---|
| 17 | 2026-10 | **Lokale Kontaktdaten und Sicherheits-Aufklärung:** „Connect to others" speichert Telefonnummer und Handles freiwillig und ausschließlich verschlüsselt auf dem Gerät; keine Übertragung an Server, kein Geräte-Sync. Die neue Aufklärung vor dem Setup speichert Antworten und Fortschritt nur lokal. Ergänzt Abschnitt 3c und die öffentliche Seite `/dating-sicherheit` |
| 15 | 2026-10 | **Speicherfristen eingeloest und Kontaktweg ergänzt:** Die Erklärung kündigte seit Version 8 die Löschung des Verifikations-Videos nach 30 Tagen an - eingelöst war sie nicht (es gab keinen Löschjob). Der Cronjob `cleanup-verification-videos` (Migration 160) entfernt jetzt Chiffrat und Schlüssel nach 30 Tagen. Außerdem: der Kontaktweg nennt eine eigene E-Mail-Adresse, die verantwortliche Stelle wird namentlich benannt, und Spaceship ist als Auftragsverarbeiter für das Mail-Hosting eingetragen. Der Satz zu den Transit-Spark-Signalen in Abschnitt 7 war zudem zerbrochen |
| 16 | 2026-10 | **Sicherheitscheck (CAPTCHA) genauer beschrieben:** Die WebView des Sicherheitschecks wird nur für diesen Zweck geöffnet und lässt ausschließlich `auth.thestia.de` und die Turnstile-Dienste von Cloudflare zu. Drittanbieter-Cookies sind dort **nicht** zugelassen - es wird deshalb kein Sitzungs-Cookie von Cloudflare gespeichert, weder im Gerät noch in der App. Im Fehlerfall zeigt die App den technischen Turnstile-Code, damit ein Fehler einer Meldung zugeordnet werden kann, statt ihn in einer allgemeinen Fehlermeldung zu verstecken |
| 14 | 2026-10 | **Kinderschutz-Standards:** Verbot von Kindesmissbrauch (CSAE/CSAM) in den Community-Standards, eigene Meldeart in der App, oeffentliche Kinderschutz-Seite mit benannter Kontaktperson und Meldeweg an die zustaendigen Stellen. Von Google Play fuer Dating-Apps unabhaengig von einer Altersbeschraenkung verlangt |
| 13 | 2026-10 | **Lösch-URL und Kontaktweg:** Die Löschung des Kontos ist über die Webseite <https://auth.thestia.de/konto-loeschen> beschrieben (Pflichtfeld im Play Console) und der Kontaktweg für Auskunft, Berichtigung und Löschung auf Anfrage ist in Abschnitt 1 genannt |
| 12 | 2026-10 | **Kein TURN-Relay:** Fuer Video- und Sprachanrufe wird weiterhin ausschliesslich STUN verwendet - es gibt aktuell keinen Relay-Anbieter, der ohne Kreditkarte und ohne Eigenbetrieb nutzbar waere. Der TURN-Support ist als Aufgabe auf der Roadmap hinterlegt und wird erst mit Anbieter und Datenschutz-Eintrag umgesetzt |
| 11 | 2026-10 | **TURN-Relay aufgeführt:** Der bei Video- und Sprachanrufen eingesetzte Relay-Server (Metered Open Relay) ist jetzt als Drittanbieter benannt - mit den Daten, die er sieht (IP-Adresse, Zeitpunkt, Dauer der Weiterleitung) und der Aussage, dass die übertragenen Medien Ende-zu-Ende verschlüsselt bleiben |
| 10 | 2026-10 | **Verifiziertes Alter ist massgeblich:** Der Jugendschutz-Filter rechnet jetzt mit dem per Video bestätigten Alter statt mit der Angabe im Profil, und Konten ohne Verifizierung erscheinen in keiner Begegnungsliste. Vorher konnte jede Altersangabe ungeprüft durchgesetzt werden |
| 9 | 2026-10 | **Jugendschutz verschaerft:** Die Sichtbarkeit ist jetzt beidseitig gefiltert - 16- und 17-Jährige sehen nur Gleichaltrige, nie einen Erwachsenen, und ein Erwachsener sie nie. Die Altersspanne ist nach unten auf 10 Jahre unter dem eigenen Alter begrenzt. Minderjährige werden bei der Video-Verifizierung immer von Hand geprüft |
| 8 | 2026-10 | **Video verschlüsselt:** Das Verifikations-Video wird auf dem Gerät mit AES-256-GCM verschlüsselt; im Speicher liegt nur der Chiffrat. Der Schlüssel liegt in einer Tabelle ohne Client-Zugriff. Die früheren Angaben „verschlüsselt nur auf dem Gerät“ und „7 Tage“ waren falsch |
| 7 | 2026-10 | **v0.10.0 – Aussehen-Merkmale:** Die Merkmale in Transit Spark sind jetzt in Kategorien gegliedert (Oberteil, Unterteil, Kopf, Schuhe, Accessoires, Haar, Augen) mit je einem Wert pro Kategorie, einer Suche und eigenen Farbpaletten für Haar- und Augenfarbe. Die Merkmale liegen im Klartext in `transit_signals` – anders als Chat-Inhalte, die als Chiffrat transportiert werden – und werden nach 24 Stunden gelöscht. Merkmale, die du an einer anderen Person bemerkt hast, werden nur für das Matching verwendet, nicht angezeigt und nicht an Dritte weitergegeben |
| 6 | 2026-10 | **v0.10.0 – Standort neu:** Der Ort (Stadt) wird nicht mehr erhoben, gespeichert oder angezeigt; sichtbar ist nur das Bundesland. Koordinaten liegen vor dem Speichern auf einem 5-km-Raster in einer nur für den Eigentümer lesbaren Tabelle. Die Entfernungsanzeige ist aus und muss eingeschaltet werden; eingeschaltet zeigt sie Stufen von 10 km, unter 5 km gar nichts. Die Spalten `city`, `location_lat` und `location_lng` wurden aus `profiles` entfernt. Löschung nach 30 Tagen bleibt bestehen |
| 5 | 2026-10 | v0.9.2: Altersprüfung mit Kamera **und** Ton korrekt als aktiv beschrieben (war als "deaktiviert" geführt), 18+-Sperre für Transit Spark, Entfernungsangabe korrigiert, Sanctuary als geplant für v0.11.0 gekennzeichnet |
| 4 | 2026-09 | Verschlüsselte Profilbilder + on-device NSFW-Vorprüfung (3a), lokaler Chat-Verlauf (3 Modi), Gerätemodell in der Geräte-Liste (078), Präferenzen-/UI-Sync (074/076) ergänzt |
| 3 | 2026-09 | Sanctuary (on-device KI), Geräte-Liste (071), Web-Bridge/Codeberg (0.12.0-Ausblick), Rechte-Kapitel ergänzt |
| 2 | 2026-08 | UnifiedPush, NSFW-Melde-Workflow, Ban-Einträge |
| 1 | 2026-07 | Erste öffentliche Fassung (Beta) |
