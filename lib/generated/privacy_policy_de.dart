// GENERIERTE DATEI - NICHT VON HAND AENDERN.
// Quelle: docs/DATENSCHUTZ.md
// Neu erzeugen mit: python tool/make_privacy_policy.py

/// Ein Abschnitt der Datenschutzerklaerung fuer die Anzeige in der
/// App.
///
/// Google Play verlangt die Erklaerung nicht nur als Link im Store,
/// sondern ausdruecklich auch als Text innerhalb der App selbst.
/// Deshalb steht sie hier und wird im Privacy-Screen gelesen, statt
/// nur verlinkt zu werden - eine URL kann falsch oder nicht erreichbar
/// sein, dieser Text nicht.
class PrivacyBlock {
  const PrivacyBlock(this.kind, this.text, {this.cells});

  /// h1, h2, h3, p, li oder table.
  final String kind;

  /// Fliesstext bzw. Ueberschrift. Fuer [kind] == 'table' leer.
  final String text;

  /// Zellen einer Tabellenzeile. Nur bei [kind] == 'table' gesetzt.
  final List<String>? cells;
}

/// Die vollstaendige Datenschutzerklaerung als Bloecke, in der
/// Reihenfolge von docs/DATENSCHUTZ.md.
const List<PrivacyBlock> kPrivacyPolicyDe = <PrivacyBlock>[
  PrivacyBlock('h1', 'Datenschutzerklärung für Thestia'),
  PrivacyBlock('p', '**Stand: September 2026** · Version 4 (v0.8.x)'),
  PrivacyBlock('p', 'Thestia ist ein datenschutzorientiertes Open-Source-Projekt (AGPLv3). Der Schutz deiner persönlichen Sphäre steht an erster Stelle: Es werden keine Werbetracker eingesetzt, keine Verhaltensprofile erstellt und keine Nutzerdaten an Dritte verkauft.'),
  PrivacyBlock('p', '---'),
  PrivacyBlock('h2', '1. Grundsatz und Verantwortliche Stelle'),
  PrivacyBlock('p', 'Verantwortliche Stelle im Sinne der DSGVO ist **Thestia**, die Anwendung, die Sie gerade benutzen (Store-Eintrag: *Thestia*). Kontaktaufnahme für alle datenschutzbezogenen Anliegen: über das **In-App-Bug-Report-Formular** (Einstellungen) oder das Issue-Tracker des öffentlichen Projekt-Repositorys.'),
  PrivacyBlock('p', 'Die serverseitige Verarbeitung erfolgt in der EU-Region von Supabase (Vertragspflichten als Auftragsverarbeiter nach Art. 28 DSGVO, siehe Abschnitt 6). Der Quellcode ist öffentlich einsehbar und selbst hostbar; betreibt jemand eine eigene Instanz, ist diese Instanz selbst Verantwortliche Stelle, und zwar unter ihrem eigenen Namen.'),
  PrivacyBlock('p', '**Prinzipien (Art. 5 DSGVO):** Datenminimierung, Zweckbindung, Speicherbegrenzung, Datenschutz durch Technik (E2E, on-device) und Transparenz. Es gibt **keine** Werbe-Ökosystem-Integration, **kein** Tracking-Pixel und **keine** nutzerübergreifende Verhaltensanalyse.'),
  PrivacyBlock('h2', '2. Erhobene Daten und Verarbeitungszwecke'),
  PrivacyBlock('table_head', '', cells: <String>['Kategorie', 'Daten', 'Zweck', 'Löschung']),
  PrivacyBlock('table', '', cells: <String>['Kontodaten', 'Name, E-Mail, Geburtsdatum, Geschlecht', 'Kontoverwaltung, Jugendschutzfilter (serverseitig erzwungen)', 'Mit Account-Löschung']),
  PrivacyBlock('table', '', cells: <String>['Standortdaten', 'Koordinaten (einmalig bei Freigabe)', 'Entfernungsberechnung; exakte Koordinaten verlassen den Server nicht', 'Mit Account-Löschung']),
  PrivacyBlock('table', '', cells: <String>['Standortanzeige', '5-km-gerundete Entfernung (~11 km Genauigkeit für Koordinaten-Näherung)', 'Andere Nutzer sehen nur gerundete Werte', '–']),
  PrivacyBlock('table', '', cells: <String>['Profilangaben', 'Bio, Interessen, Audio-Vorstellung, Gewohnheiten (Rauchen/Alkohol/Drogen), Mood, Musik-Geschmack, **Profilbild** (siehe Abschnitt 3a)', 'Vermittlung passender Kontakte („Funken")', 'Mit Account-Löschung']),
  PrivacyBlock('table', '', cells: <String>['Geräte-Liste', 'Gerätemodell (Hersteller + Modellkennung, z. B. „Samsung SM-S921B"), Plattform, App-Version, Zeitstempel der letzten Anmeldung', 'Anzeige „Wo bin ich eingeloggt?" + „Überall abmelden" (Migration 071/078); kein Standort, keine Seriennummer, keine Werbe-ID', 'Automatisch beim Abmelden; mit Account-Löschung']),
  PrivacyBlock('table', '', cells: <String>['Präferenzen', 'Suchradius, Altersspanne, Geschlechts-Filter, „Ich suche", Farbwelt, UI-Schalter (Blind Mode, Sichtbarkeit, Benachrichtigungen)', 'Wiederherstellung nach Neuinstallation (Migration 066/071/074/076)', 'Mit Account-Löschung']),
  PrivacyBlock('table', '', cells: <String>['Push-Tokens', 'FCM-Token (nur Play) bzw. UnifiedPush-Endpunkt (F-Droid)', 'Zustellung von Push-Signalen **ohne Nachrichteninhalt**', 'Mit Account-Löschung / Abmelden']),
  PrivacyBlock('table', '', cells: <String>['Verifizierung', 'Beta-Funktion, derzeit deaktiviert', '–', '–']),
  PrivacyBlock('h2', '3. Ende-zu-Ende-Verschlüsselung (Signal-Protokoll)'),
  PrivacyBlock('p', 'Sämtliche regulären Chat-Nachrichten, Bilder und Sprachanrufe zwischen Nutzern werden Ende-zu-Ende über das **Signal-Protokoll** verschlüsselt. Weder die Betreiber noch zwischengeschaltete Server können Nachrichteninhalte einsehen.'),
  PrivacyBlock('li', '**Übertragungsweg:** Direkte Peer-to-Peer-Verbindung (WebRTC) wird versucht; gelingt sie nicht, übernimmt der Server **ausschließlich den Transport des verschlüsselten Chiffrats** (Relay-Fallback). Die Verschlüsselung ist in beiden Fällen Ende-zu-Ende und identisch – der Server sieht und verarbeitet in keinem Fall Klartext. Auf die Verbindungsqualität hat das keinen Einfluss, auf die Privatsphäre ebenso wenig.'),
  PrivacyBlock('li', 'Identitäts- und Sitzungsschlüssel werden im verschlüsselten Geräte-Keystore (Android Keystore / iOS Keychain) gehalten.'),
  PrivacyBlock('li', 'Ein optionales, **passwortverschlüsseltes Key-Backup** (PBKDF2 + AES-256-GCM) erlaubt den Gerätewechsel; der Schlüssel liegt ausschließlich beim Nutzer. Verlust von Backup **und** Passwort ist unwiederbringlich – daraus kann keine Datenwiederherstellung durch das Team erfolgen.'),
  PrivacyBlock('h2', '3a. Verschlüsselte Profilbilder (neu ab v0.8.x)'),
  PrivacyBlock('p', 'Profilbilder werden **bereits auf deinem Gerät** per AES-256-GCM verschlüsselt, bevor sie hochgeladen werden. Der Server (Supabase Storage, privater Bucket) speichert ausschließlich den Ciphertext – auch bei einem Storage-Zwischenfall sind die Bilder unlesbar. Der Ent- schlüsselungs-Schlüssel wird zufällig pro Bild erzeugt und im eigenen Profil-Eintrag mitgeführt; nur Personen, die dein Profil sehen dürfen (Sichtbarkeits-Einstellung + Altersschutz), laden und entschlüsseln das Bild lokal. Zusätzlich läuft vor jedem Upload eine **rein lokale NSFW-Vorprüfung** (ONNX-Modell on-device): Bilde-Bytes, Scores und Ergebnis verarbeiten sich ausschließlich auf dem Gerät; bei Nicht- bestehen verlässt das Bild dein Gerät nicht (Einspruch mit manueller Team-Prüfung ist möglich).'),
  PrivacyBlock('h2', '3b. Nahbereichsfunk (BLE, „Transit Spark")'),
  PrivacyBlock('p', 'Transit Spark nutzt Bluetooth Low Energy, damit zwei Personen sich in der Nähe begegnen können, ohne sich ansprechen zu müssen. Dabei werden Funk-Metadaten verarbeitet.'),
  PrivacyBlock('p', '**Was gesendet wird:** ein ephemerer, zufälliger Token (keine Geräte-ID, kein Name, keine MAC-Adresse des Geräts). Der Stack des Betriebssystems vergibt für das Advertising eine auflösbare Privatadresse; die App setzt keine feste Adresse.'),
  PrivacyBlock('p', '**Was empfangen wird:** der Scanner ist seit v0.9.2 auf die Hersteller-ID der App gefiltert. Vorher verarbeitete er jedes Bluetooth-Signal in Reichweite (Uhren, Kopfhörer, Beacons); das ist korrigiert.'),
  PrivacyBlock('p', '**Was lokal bleibt:** Begegnungen (Token, Zeitstempel, stärkstes RSSI) werden ausschließlich auf dem Gerät gespeichert, mit einer Vorhaltezeit von 45 Minuten, danach automatische Löschung. Sie werden nicht an den Server übertragen.'),
  PrivacyBlock('p', '**Was der Server sieht:** erst wenn beide Personen ausdrücklich bestätigen, werden die zuletzt beobachteten Tokens zur Prüfung übermittelt. Der Server prüft Alter, Geschlecht und Blockierstatus. Aus einem Token lässt sich keine Geräte-Identität ableiten.'),
  PrivacyBlock('p', '**Verminderung des Funk-Fingerprints:** Das Advertising wird in unregelmäßigen Abständen neu gestartet und das Encounter-Token wird nicht in einem starren Zeitraster gewechselt. Damit ist das Sendemuster nicht sessionübergreifend konstant. Ein vollständiger Schutz gegen das Mitschreiben des Funks ist damit nicht verbunden: Bluetooth ist ein Funkmedium und im Umfeld beobachtbar.'),
  PrivacyBlock('p', '**Keine Ortung:** Transit Spark ermittelt keine Position per Funk. Der Standort wird nur für die Entfernungsanzeige der Profile verwendet und dient serverseitig nach 30 Tagen der Löschung (Migration 129).'),
  PrivacyBlock('h2', '4. Lokaler Chat-Verlauf (optional) und lokaler KI-Reflexions-Chat (Sanctuary, geplant ab v0.10.0)'),
  PrivacyBlock('p', '**Lokaler Chat-Verlauf (seit v0.8.x):** Auf Wunsch speichert die App Chats verschlüsselt (AES-256, SecureHive; Schlüssel im Keystore) lokal auf dem Gerät – wählbar zwischen „Aus", „200 Nachrichten pro Chat" und „Kompletter Verlauf" (Standard). Die Daten verlassen das Gerät nicht und können jederzeit durch Deaktivieren gelöscht werden. Der JSON-Datenexport enthält den Verlauf (Einsicht/Übertragbarkeit), der Import stellt ihn wieder her.'),
  PrivacyBlock('p', 'Der integrierte Reflexions-Assistent läuft vollständig lokal („On-Device") auf deinem Smartphone. Sämtliche Texteingaben, hochgeladene Screenshots und generierte Antworten verbleiben ausschließlich auf deinem Gerät und werden zu keinem Zeitpunkt an externe Server übertragen.'),
  PrivacyBlock('li', 'Chatverläufe verbleiben **flüchtig im RAM** oder werden optional **rein lokal AES-verschlüsselt** in Hive abgelegt (Standard: flüchtig).'),
  PrivacyBlock('li', 'Die Krisen-Erkennung (Regex auf suizidbezogene Begriffe) läuft ausschließlich lokal; angezeigt werden dann Notfallkontaktdaten (Telefonseelsorge 0800 111 0 111 / 0800 111 0 222, Nummer gegen Kummer 116 111). Es werden **keine** Analyse- oder Meldungsdaten erzeugt.'),
  PrivacyBlock('li', 'Die „Modellqualität beanstanden"-Funktion übermittelt ausschließlich den vom Nutzer freigegebenen Textauszug sowie Modell-Metadaten (Modellname, Quantisierung, App-Version) – niemals vollständige Chatverläufe.'),
  PrivacyBlock('li', 'Modell-Downloads (GGUF) sind nutzerinitiiert und erfolgen direkt von Hugging Face; die App übermittelt dabei keine zusätzlichen Metadaten.'),
  PrivacyBlock('h2', '5. Meldesystem und Missbrauchsschutz'),
  PrivacyBlock('li', 'Chat-Bilder werden im Regelbetrieb **niemals serverseitig gescannt**.'),
  PrivacyBlock('li', 'Meldet ein Empfänger ein empfangenes Bild, wird dieses **lokal auf dem Gerät** per ONNX-Modell vorbewertet. Der Meldende sieht das Ergebnis und entscheidet: Nur nach expliziter Bestätigung wird das betroffene Bild nebst den **letzten drei Textnachrichten** verschlüsselt an die Administration zur manuellen Prüfung übertragen.'),
  PrivacyBlock('li', 'Meldungen sind **pseudonymisiert**: Die Identität des Meldenden wird dem Gemeldeten niemals offengelegt (technisch SHA-256-Hash, Migration 069).'),
  PrivacyBlock('li', 'Berichte über unzureichende Modellqualität im Reflexions-Chat enthalten ausschließlich den vom Nutzer freigegebenen Textauszug sowie Modell-Metadaten.'),
  PrivacyBlock('h2', '6. Datenweitergabe und Drittanbieter'),
  PrivacyBlock('table_head', '', cells: <String>['Anbieter', 'Daten', 'Zweck', 'Region']),
  PrivacyBlock('table', '', cells: <String>['Supabase (EU-Region)', 'Kontodaten, verschlüsselte Authentifizierungs-Token, Profildaten', 'Hosting von Accounts, DB, Auth', 'EU (Verarbeitungsvertrag über Supabase Europe B.V.)']),
  PrivacyBlock('table', '', cells: <String>['Firebase Cloud Messaging (nur Play-Store-Version)', 'Push-Token, „stumme" Push-Signale', 'Zustellsignal; Inhalte werden danach lokal per WebRTC/E2E geladen', 'Google-Infrastruktur (verarbeitet nur das Token)']),
  PrivacyBlock('table', '', cells: <String>['UnifiedPush (F-Droid-Version, z. B. ntfy)', 'Push-Endpunkt', 'Google-freie Push-Zustellung', 'Selbst wählbar (kann vollständig selbst gehostet sein)']),
  PrivacyBlock('table', '', cells: <String>['Brevo', 'E-Mail-Adresse', 'Transaktions-E-Mails (Bestätigung, Passwort-Reset, Bug-Report-Kopie)', 'EU']),
  PrivacyBlock('table', '', cells: <String>['Cloudflare', 'CAPTCHA-Token (Turnstile), TURN-Relay für WebRTC', 'Bot-Schutz; Relais sieht **keine** Inhalte (E2E)', 'Global (EU-PoP bevorzugt)']),
  PrivacyBlock('table', '', cells: <String>['Netlify', 'CAPTCHA-Zwischenseite', 'Hosting der Anmelde-/CAPTCHA-Seite', 'Global']),
  PrivacyBlock('table', '', cells: <String>['Hugging Face', 'Keine Nutzerdaten', 'Ausschließlich für den optionalen, nutzerinitiierten Download frei verfügbarer KI-Modelldateien (GGUF)', 'Global']),
  PrivacyBlock('table', '', cells: <String>['Codeberg e.V. (geplant ab v0.11.0)', 'Keine personenbezogenen Daten', 'Trackerfreies Hosting der Flutter-Web-Artefakte (statische Dateien)', 'Berlin, Deutschland']),
  PrivacyBlock('p', '**Keine** Weitergabe an Werbenetzwerke, Datenbroker oder Analyse-Dienste. **Keine** Nutzung von Google Analytics, Crashlytics oder ähnlichen Produkten (Bug-Reports laufen über das In-App-Formular und enthalten nur die vom Nutzer geprüften Angaben).'),
  PrivacyBlock('h2', '7. Speicherfristen und Kontolöschung'),
  PrivacyBlock('p', 'Du hast jederzeit das Recht auf vollständige Löschung deines Kontos (**Art. 17 DSGVO – Recht auf Löschung**).'),
  PrivacyBlock('li', 'Bei Ausführung der In-App-Funktion **„Account löschen"** (unter Datenschutz & Account, mit 2FA-Bestätigung) werden alle personenbezogenen Daten auf den Servern unverzüglich und unwiderruflich entfernt: Profil, Nachrichten-Metadaten, Likes/Matches, Reports-Bezug, Geräte-Liste, Push-Token, Signal-PreKeys und Storage-Dateien (Avatar/Audio).'),
  PrivacyBlock('li', 'Lokale Datenbanken auf dem Gerät werden im selben Zug bereinigt (E2E-Identität, Verifizierungsdaten, Temp-Dateien).'),
  PrivacyBlock('li', 'Technisch notwendige Restdaten (z. B. Ban-Einträge gegen Umgehung von Jugendschutz-Sperren) werden nur so lange gespeichert, wie gesetzlich bzw. zweckgebunden erforderlich (Art. 6 Abs. 1 lit. f DSGVO) und anschließend gelöscht.'),
  PrivacyBlock('li', 'Flüchtige Web-Gast-Sitzungen (geplant ab v0.11.0) zerstören sich serverseitig nach 24–48 Stunden rückstandslos.'),
  PrivacyBlock('h2', '8. Deine Rechte (Art. 15–21 DSGVO)'),
  PrivacyBlock('li', '**Auskunft (Art. 15):** Der In-App-Datenexport („Meine Daten exportieren") liefert alle personenbezogenen Daten als JSON-Download.'),
  PrivacyBlock('li', '**Berichtigung (Art. 16):** Alle Profilfelder sind in der App frei editier- und löschbar.'),
  PrivacyBlock('li', '**Löschung (Art. 17):** Siehe Abschnitt 7.'),
  PrivacyBlock('li', '**Einschränkung/Widerspruch (Art. 18/21):** Über die Kontaktwege in Abschnitt 1.'),
  PrivacyBlock('li', '**Datenübertragbarkeit (Art. 20):** JSON-Export über die In-App- Funktion.'),
  PrivacyBlock('li', '**Beschwerderecht (Art. 77):** Bei einer Aufsichtsbehörde, z. B. der Landesdatenschutzbehörde.'),
  PrivacyBlock('h2', '9. Kinder- und Jugendschutz'),
  PrivacyBlock('p', 'Die Nutzung ist ab **16 Jahren** gestattet. 16- und 17-Jährige sind serverseitig strikt getrennt: Sie sehen ausschließlich andere Minderjährige, Fotos sind für Erwachsene technisch unsichtbar (Blind Mode erzwungen), und die Altersfilter sind serverseitig begrenzt (Migration 056). Geburtsdaten werden zur Durchsetzung dieses Jugendschutzes verarbeitet (Art. 6 Abs. 1 lit. c/f) und gegenüber anderen Nutzern nie angezeigt (nur gerundetes Alter).'),
  PrivacyBlock('h2', '10. Angriffsbild und Risikoabschätzung'),
  PrivacyBlock('p', 'Die technische Bewertung der Verarbeitung ist öffentlich: Angriffsbild in [THREAT-MODEL.md](THREAT-MODEL.md), Risiken nach Art. 35 DSGVO in [DSFA.md](DSFA.md) (Entwurf, rechtlich noch nicht geprüft). Dort sind auch die Punkte benannt, die Thestia bewusst **nicht** zusichert: Funk-Metadaten sind technisch beobachtbar, und Ende-zu-Ende- Verschlüsselung schützt Inhalte, nicht Kommunikationsmuster.'),
  PrivacyBlock('h2', '11. Änderungen dieser Erklärung'),
  PrivacyBlock('p', 'Bei funktionalen Änderungen (neue Datenkategorien, neue Anbieter) wird diese Erklärung in der App und im Repository aktualisiert; die Änderungshistorie ist über die Versionszeile am Dokumentkopf und die Git-Historie nachvollziehbar.'),
  PrivacyBlock('p', '---'),
  PrivacyBlock('h3', 'Historie'),
  PrivacyBlock('table_head', '', cells: <String>['Version', 'Datum', 'Änderung']),
  PrivacyBlock('table', '', cells: <String>['4', '2026-09', 'Verschlüsselte Profilbilder + on-device NSFW-Vorprüfung (3a), lokaler Chat-Verlauf (3 Modi), Gerätemodell in der Geräte-Liste (078), Präferenzen-/UI-Sync (074/076) ergänzt']),
  PrivacyBlock('table', '', cells: <String>['3', '2026-09', 'Sanctuary (on-device KI), Geräte-Liste (071), Web-Bridge/Codeberg (0.11.0-Ausblick), Rechte-Kapitel ergänzt']),
  PrivacyBlock('table', '', cells: <String>['2', '2026-08', 'UnifiedPush, NSFW-Melde-Workflow, Ban-Einträge']),
  PrivacyBlock('table', '', cells: <String>['1', '2026-07', 'Erste öffentliche Fassung (Beta)']),
];
