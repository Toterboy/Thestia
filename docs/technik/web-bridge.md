# Web-Bridge und Zero-Install-Gastverbindungen - der Plan fuer 0.12.0

Aus der Roadmap (Stand 23.11.2026) in ein eigenes Dokument verschoben.


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

