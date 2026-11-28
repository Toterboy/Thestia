# Lokale KI-Reflexion (Sanctuary) - der Plan für 0.11.0

Aus der Roadmap (Stand 23.11.2026) in ein eigenes Dokument verschoben.


> Vision: Ein vollständig offlinefähiger, geschützter Raum zur
> Selbstreflexion bei Frust, Zurückweisung oder emotionalen Tiefs –
> betrieben durch rein lokale On-Device-Sprachmodelle. Kein Server, kein
> Konto, keine Weitergabe: Was im Sanctuary geschrieben wird, bleibt im
> RAM (optional lokal AES-verschlüsselt).

### 1. Modell-Management & Import

> **ENTSCHEIDUNG (Betreiber, 27.11.2026): "KI Modelle muss man einfach
> selbst herunterladen. Ein paar könnte man aber vielleicht als
> Empfehlung nennen oder so."**
>
> Die App lädt **kein** Modell selbst herunter. Der Nutzer holt die
> GGUF-Datei selbst (Browser, Dateimanager, PC) und importiert sie in
> die App. Die App nennt dazu ein paar **Empfehlungen** – Name,
> Größe, RAM-Bedarf, Lizenz und woher man das Modell bekommt.
>
> **WARUM DAS ALSO GUT IST:** Damit ruft die App keinen fremden Dienst
> ab – kein Metadatenabruf, keine IP-Adresse an einen US-Anbieter. Das
> Drittlandproblem (0.12.0 führt US-Cloud-Abhängigkeit als
> Ausschlusskriterium) stellt sich damit nicht. Wer das Modell
> herunterlädt, entscheidet das selbst – und kann einen eigenen Spiegel
> nehmen.
>
> **Stand 27.11.2026: Der Grundbau steht.**
>
> * **Der Katalog der Empfehlungen**
>   (`lib/models/sanctuary/sanctuary_empfehlung.dart`): fünf Modelle in
>   zwei Stufen (kompakt und ausgewogen) mit Name, Herkunft, Dateigröße,
>   RAM-Bedarf, Lizenz-Hinweis und den verfügbaren Quantisierungen.
> * **Der Import**
>   (`lib/services/sanctuary/sanctuary_modell_service.dart`): der Nutzer
>   wählt die GGUF-Datei selbst; die App prüft sie (echte GGUF-Signatur,
>   Größe zwischen 50 MB und 20 GB), kopiert sie in ihr eigenes
>   Verzeichnis (eine Datei im Download-Ordner wäre beim Aufräumen weg)
>   und merkt sie sich. Ein fremdes Modell wird als solches markiert.
> * **Noch offen:** die Oberfläche (die Liste der Empfehlungen und der
>   Import-Knopf), die Krisen-Erkennung und die Inferenz selbst
>   (llama.cpp über FFI – die native Abhängigkeit).

- [ ] **Stufenbasierte Modellauswahl**:
      * Stufe 1 (Kompakt / Akkusparend): Gemma 4 E2B, Spark-X2.5-1.7B
        (Text-only)
      * Stufe 2 (Erweitert / Tiefgründig): Qwen 3.5-4B, Gemma 4 E4B,
        Spark-X2.5-4B
- [ ] **Quantisierungs-Varianten**: Jedes Modell gibt es in
      Q4_K_M (Standard, Balance), Q5_K_M / Q6_K (höhere Qualität) und
      Q3_K_S / IQ3 (wenig Speicher) – die **Empfehlungsliste** zeigt
      Größe und RAM-Bedarf je Variante und warnt vor zu knappem
      Speicher
- [ ] **Multimodal-Kennzeichnung (Vision-Badge)**: Modelle mit
      Bilderkennung werden optisch gekennzeichnet, um Screenshots von
      Chats zwecks Interpretation und Formulierungshilfe analysieren zu
      können
- [ ] **Die Empfehlungsliste** (die einzige Stelle, an der die App
      auf Modelle hinweist): Name, Herkunft, Größe, RAM-Bedarf, Lizenz
      und ein Hinweis, woher man die Datei bekommt. Reine Information –
      die App lädt nichts.
- [ ] **Eigener Modell-Import**: Der Nutzer wählt die GGUF-Datei aus dem
      Smartphone-Speicher (Downloads, Dateimanager, PC-Kabel). Die App
      kopiert sie in ihr eigenes Verzeichnis, prüft sie (gültiges GGUF,
      Größe, freier Speicher) und bietet sie an
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
- [x] **Drittlandproblem: entschieden (27.11.2026).** Die App lädt
      kein Modell herunter – der Nutzer tut das selbst. Damit gibt es
      keinen Metadatenabruf und keine IP-Adresse bei einem US-Anbieter
      durch die App. Die Empfehlungsliste nennt nur, woher man die
      Datei bekommt; die Wahl des Anbieters liegt beim Nutzer. (Wer
      will, nimmt einen eigenen Spiegel – die App ist dabei neutral.)
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

> **Stand 27.11.2026: Die Sync-Dates sind umgesetzt** (Migration 223
> `sync_dates`, das Modell `lib/models/dating_hour/sync_date.dart`, der
> Dienst, die Karte im Chat, das Ideen-Rad mit den Sync-Ideen und die
> Zeitwahl). Entschieden vom Betreiber:
>
> * **Immer vorschlagen**, unabhängig von der Distanz.
> * **Während des Dates ist nur dieser Chat benutzbar** - alle anderen
>   Chats und Modi sind gesperrt (die Einstellungen bleiben offen). Die
>   Sperre sitzt im Router: jeder andere Weg wird auf den Chat des
>   Dates umgeleitet.
> * **Der Zeitpunkt** kommt aus einer kurzen Liste (heute 20 Uhr, morgen
>   18 Uhr, selbst wählen) - wer das Date vorschlägt, macht den
>   Vorschlag, und wer annimmt, darf ihn ändern.
> * **Das Date endet mit dem Anruf.** Der Anruf-Screen zeigt, wie lange
>   man schon telefoniert.
>
> **Die Antizipation steht in der Chat-Kopfzeile:** sobald ein Termin
> steht, steht die Vorfreude da ("Termin: 27.11. 20:00 - freut euch auf
> das Date!"), läuft das Date gerade, steht das da. Der Termin ist das,
> worauf man sich freut - nicht die Chat-Metriken.
>
> **Noch offen:** der sanfte Nudge zu Anruf und Sprachnachricht bei
> Distanz-Funken (die zweite Hälfte der Antizipation).

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

