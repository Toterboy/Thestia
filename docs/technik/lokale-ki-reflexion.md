# Lokale KI-Reflexion (Sanctuary) - der Plan fuer 0.11.0

Aus der Roadmap (Stand 23.11.2026) in ein eigenes Dokument verschoben.


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

### Begleitend in 0.11.0 – Die eigene Tastatur wird einstellbar

> Die eigene Tastatur (Build 54, v0.10.1) ist bisher an zwei Stellen
> fest verdrahtet: die **Belegung** folgt der Sprache der App
> (`L10n.localeOf(context)`), und die **Farben** kommen aus dem
> App-Thema (`surfaceContainer` / `surfaceContainerHighest`). Beides wird
> jetzt einstellbar.
>
> **Wichtig für die Umsetzung: beides ist rein App-seitig.** Die
> Einstellungen kommen in `profiles.ui_prefs` (jsonb, Migration 074) – es
> kommen zwei Schlüssel dazu, keine neue Spalte.
> **Keine Migration, keine neue Spalte, keine neuen Daten** – die
> Datenschutzerklärung ändert sich dadurch nicht.

- [ ] **Der Tastaturhintergrund wird anpassbar**: In den Einstellungen
      (Abschnitt *Darstellung*, neben der Farbwelt) kommt ein
      **Tastaturstil**:
      * **Wie die App** (Voreinstellung) – das heutige Verhalten: die
        Tasten nehmen die Flächenfarben des App-Themas.
      * **In der Farbe der App** – die Tasten und die Aktions-Tasten
        (Umschaltung, Zahlen, Emoji, Löschen, Enter) bekommen die
        Akzentfarbe der gewählten Farbwelt. Der Text darauf muss in
        beiden Helligkeiten lesbar bleiben (Kontrast!).
      * **Eigene Farbe** – ein einzelner, selbst gewählter Farbton
        (eigener Schlüssel `keyboardColor`).
      * **Umsetzung:** `lib/widgets/chat/secure_keyboard.dart` holt die
        Farben heute hart aus `Theme.of(context).colorScheme`. Der
        Umbau ist: die Farben kommen aus der Einstellung, die Tastatur
        bekommt sie als Parameter (kein globales Theme-Umhängen - die
        Tastatur soll sich nicht in den anderen Bildschirmen
        ausbreiten).
      * **Auswahl im Chat sichtbar:** Der Stil wird in der
        **Einstellungs-Vorschau** gezeigt (ein kleines Tastatur-Motiv),
        damit man die Wahl ohne Chat ausprobieren kann.
- [ ] **Die Tastatursprache wird unabhängig von der App-Sprache**:
      Zwei Wege sind ausdrücklich **nicht dasselbe** – bisher war die
      Belegung ein Nebenprodukt des Sprachumschalters, und wer die App
      auf Englisch stellte, bekam automatisch QWERTY. Abgeholfen wird
      das durch einen eigenen Schalter:
      * **Wie die App** (Voreinstellung) – die Belegung folgt der
        Sprache der App (deutsch → QWERTZ mit ä ö ü ß, englisch →
        QWERTY). Das ist der heutige Stand.
      * **Deutsch (QWERTZ)** – immer deutsche Belegung, auch wenn die
        App englisch ist.
      * **Englisch (QWERTY)** – immer englische Belegung, auch wenn die
        App deutsch ist.
      * **Warum das eine eigene Einstellung sein muss:** Wer auf
        Deutsch schreibt, aber in einer englischen Umgebung arbeitet
        (Schule, Arbeit, Partner), will die App-Sprache ändern, ohne
        dass sich die Tasten verschieben. Und umgekehrt. Die
        App-Sprache ist ein **Inhaltsthema**, die Tastatur ein
        **Werkzeug** – sie gehören nicht zusammen.
      * **Umsetzung:** Der Schalter liegt in `AppSettings`
        (`keyboardLayout`) und wird über `ui_prefs` gespiegelt; die
        Tastatur liest ihn statt der Locale.
      * **Was NICHT betroffen ist:** Die Emoji-Auswahl und die
        Zahlen-/Zeichenebene sind sprachneutral. Eine **Hardwaretastatur**
        ist ohnehin unabhängig (die Tastenereignisse laufen direkt in
        den Text).
- [ ] **Beide Schalter überstehen eine Neuinstallation** und sind auf
      dem zweiten Gerät da (das ist der Punkt von `ui_prefs`). Ein Test
      prüft das wie bei den anderen Einstellungen
      (`test/settings_persistence_test.dart`).

> **Ehrlich zur Grenze:** Das ist Komfort, kein Sicherheitsgewinn. Die
> Tastatur liest weiterhin nichts – die Belegung ändert daran nichts,
> und der Hintergrund ist eine Farbe. Wer die App-Sprache ändert, um die
> Tastatur zu ändern, bekommt in 0.11.0 beides getrennt.

