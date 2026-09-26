# BLE-Gerätetest Transit Spark (v0.9.2)

> **Status: OFFEN.** Dieses Dokument ist das Abnahmeprotokoll, kein
> Ergebnisbericht. Transit Spark gilt laut [ROADMAP.md](../ROADMAP.md) erst
> als stabil, wenn die drei Kriterien unten auf **mindestens zwei echten
> Geräten verschiedener Android-Hersteller** bestanden sind. Simulator und
> Emulator zählen nicht: dort gibt es kein echtes Advertising, keine
> realistische Reichweite und kein Funkrauschen.

## Warum ein Handtest nötig ist

Der BLE-Pfad ist zur Hälfte nativ. `android/app/src/main/kotlin/com/thestia/app/MainActivity.kt`
steuert Advertising und Neustart-Zyklus, `lib/services/transit_ble_service.dart`
den Scan. Beides ist in `flutter test` **nicht** abgedeckt: Der
`MethodChannel('thestia/transit_ble')` existiert im Test-Runner nicht, jeder
Aufruf läuft in `MissingPluginException`, was der Service bewusst schluckt.

Der Teil, was Unit-Tests abdeckt, ist die Mathematik:
`test/transit_ble_privacy_test.dart` prüft Jitter-Fenster, Rotationsband und
Duty-Cycle. **Nicht** prüfbar ist, ob das Advertising auf echter Hardware
tatsächlich startet und über Reichweite funktioniert.

## Messaufbau

| Position | Gerät | Rolle |
|---|---|---|
| A | (Hersteller, Modell, Android-Version) | Gerät A |
| B | (Hersteller, Modell, Android-Version) | Gerät B |

Anforderungen an das Setup:

- Beide Geräte **akkuversorgt**, kein Deep-Sleep-Zwang (Flight Mode ist
  ungeeignet, weil dort der Funk abschaltet)
- Bluetooth an, Standortberechtigung erteilt (Android 11 braucht sie fürs
  Scanning, ab Android 12 zusätzlich `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`)
- Beide Geräte mit **derselben** App-Version (`pubspec.yaml`), verschiedene
  Konten (gegenseitiges Blockieren darf nicht aktiv sein)
- Abstand jeweils per Schrittzählen oder Laser messen, nicht schätzen

## Kriterien und Protokoll

Für jedes Kriterium beide Richtungen testen (A→B und B→A), sonst
verschlechtert das Ergebnis unbemerkt.

### Kriterium 1: Advertise-Abdeckung

| # | Test | Erwartung | Ergebnis |
|---|---|---|---|
| 1.1 | Radar starten, `logcat` auf `ThestiaTransit` filtern | `Advertising fehlgeschlagen` **darf nicht** erscheinen; in der App „Signal aktiv" | ☐ |
| 1.2 | Beide Geräte 1 m voneinander, 5 min laufen lassen | beide sehen mindestens eine Begegnung (`Encounter` im Log/UI) | ☐ |
| 1.3 | Gerät A im Flugmodus, B allein | A sieht nichts, B läuft ohne Fehler | ☐ |
| 1.4 | Neustart-Zyklus beobachten (v0.9.2) | `Advertising` startet alle 20–45 s neu, **ohne** Fehlermeldung und ohne Funklücke > 2 s | ☐ |
| 1.5 | 10 min laufen lassen, Akkustand notieren | kein ungewöhnlicher Akkuverlust (Referenz: gleiche Zeit ohne Transit Spark) | ☐ |

### Kriterium 2: Reichweite

| # | Test | Erwartung | Ergebnis |
|---|---|---|---|
| 2.1 | Abstand 1 m | Begegnung, RSSI ca. > −60 dBm | ☐ |
| 2.2 | 3 m (typische Nahbereichs-Szene) | Begegnung, RSSI ca. > −75 dBm | ☐ |
| 2.3 | 10 m | Begegnung noch möglich, RSSI ca. > −85 dBm | ☐ |
| 2.4 | Waggontrennwand / Betonwand dazwischen | Verhalten notieren, **kein** Sollwert: BLE wird hier erwartbar gedämpft | ☐ |
| 2.5 | Menschliches Dazwischengehen | Sichtbeziehung nötig, kein Durchreichen durch Menschen | ☐ |

Wichtig für die Bewertung: Die Reichweite ist **Umgebungsabhängig** und
schwankt zwischen Geräten stark. Der Zweck dieses Tests ist nicht ein
fester Meterwert, sondern die Feststellung, ob die *Einstellungen*
(`ADVERTISE_MODE_LOW_LATENCY`, `TX_POWER_MEDIUM`) auf dem jeweiligen Gerät
überhaupt funktionieren.

### Kriterium 3: Match-Flow (der eigentliche Zweck)

Der Match ist **asynchron**: Begegnung wird lokal gecacht (45 min), der
Funke entsteht erst, wenn beide „Blicke getauscht" tippen.

| # | Test | Erwartung | Ergebnis |
|---|---|---|---|
| 3.1 | Beide 2 min in Reichweite, dann beide „Blicke getauscht" + Tag wählen | „Funke übergesprungen", Chat öffnet | ☐ |
| 3.2 | Nur **eine** Person tippt | kein Funke, kein Hinweis auf den anderen | ☐ |
| 3.3 | Begegnung, dann 10 min **außer** Reichweite, dann beide tippen | Funke entsteht **trotzdem** (das ist die Kernidee) | ☐ |
| 3.4 | Nach 45 min Wartezeit | Cache-Eintrag verfallen, kein Match mehr | ☐ |
| 3.5 | Eine Person blockiert die andere, dann beide tippen | kein Funke, kein Hinweis auf Blockierung | ☐ |
| 3.6 | Altersfilter greift (Testkonten mit Altersspanne) | kein Funke bei inkompatibler Altersspanne | ☐ |
| 3.7 | Scan läuft, Radio komplett aus und wieder an | kein Absturz, Radar startet nach Rückkehr sauber neu | ☐ |

## Bekannte Fehlerbilder

| Symptom | Wahrscheinliche Ursache | Prüfen |
|---|---|---|
| `advertise_failed` in der App | 3× Bluetooth-Prompts übersprungen; `BLUETOOTH_SCAN`/`CONNECT` fehlen | Berechtigungen in den App-Einstellungen |
| Advertising startet, Gegner sieht nichts | zu großer Abstand, oder 6+ Advertisements pro Slot (Android-Limit) | 1 m Abstand, Umgebung auf viele BLE-Geräte prüfen |
| `rate_limited` | 60 Antworten/h oder 600 Media-Aufrufe/h erreicht | Testkonto zurücksetzen, Rate-Limits in `app_config` prüfen |
| Funk wirkt „an/aus“ | Jitter-Neustart alle 20–45 s (v0.9.2) — **das ist gewollt**, kein Fehler | mit `logcat` gegenprüfen |
| Kein Funke trotz beidseitigem Tippen | Tag-Kombination passt nicht, oder einer hat geblockt | Tags-Kombination testen, Blockliste prüfen |

## Ergebnis eintragen

Nach dem Test dieses Dokument aktualisieren und die Checkbox in
[ROADMAP.md](../ROADMAP.md) abhaken. Solange das nicht geschehen ist, gilt
Transit Spark laut Roadmap als **nicht stabil** und wird im Store nicht als
solches beworben.

## Verwandte Dokumente

- [ARCHITEKTUR.md](ARCHITEKTUR.md) – Schichten und Datenflüsse
- [DATENSCHUTZ.md](DATENSCHUTZ.md) – Funk-Metadaten und Aufbewahrung
- [PLAY_INTEGRITY.md](PLAY_INTEGRITY.md) – Struktur dieses Protokolls
