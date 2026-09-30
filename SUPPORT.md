# Support

Danke, dass du Thestia nutzt. Hier steht, welche Versionen unterstützt werden und wie du Feedback/Bug-Reports loswirst.

## Unterstützte Versionen

| Version | Status | Anmerkung |
| --- | --- | --- |
| **v0.9.2 und höher** (Build 30+) | ✅ **Unterstützt** | Bug-Reports willkommen; Security-Fixes |
| **unter v0.9.2** (v0.8.x, v0.9.0, v0.9.1; Build < 30) | ❌ **End of Support** (seit 29.09.2026) | Keine Bug-/Security-Fixes mehr – bitte aktualisieren |

### Warum der Support erst ab v0.9.2 beginnt

Der Support-Zustieg ist eine Folge der Alterssperre für Transit Spark,
nicht nur eine Versionspolitik.

Transit Spark ist ab v0.9.2 auf **volljährige Nutzende (18+)** beschränkt –
in der App und serverseitig. Ältere Builds enthalten diese Sperre nicht:
v0.9.1 blendet die Funktion für Minderjährige lediglich mit einem
Hinweistext aus, statt sie zu blockieren. Solange solche Builds
weitergeliefert werden, lässt sich die Beschränkung umgehen – unabhängig
vom Server, weil die alte App die serverseitige Prüfung gar nicht erst
aufruft.

Deshalb ist v0.9.2 die älteste unterstützte Version. Wer den Support
früher auf v0.9.1 setzt, muss die Beschränkung entweder wieder aus dem
Server entfernen (und damit aufheben) oder hinnehmen, dass sie für
installierte v0.9.1-Clients nicht greift.

Umsetzung: `supabase/migrations/131_transit_spark_adults_only.sql`.

### Installation von v0.9.2: deinstallieren statt aktualisieren

**v0.9.2 lässt sich nicht über eine installierte v0.9.0/0.9.1
aktualisieren.** Die alte App muss vorher deinstalliert werden:

```powershell
adb uninstall com.thestia.app
```

Grund ist der Wechsel des Signier-Zertifikats vor dem ersten
Store-Upload. Android erlaubt ein Update nur bei identischer Signatur,
sonst schlägt es mit `INSTALL_FAILED_UPDATE_INCOMPATIBLE` fehl. Die
anschließende Meldung „Die App konnte nicht gestartet werden" ist nur
der Folgezustand des abgebrochenen Updates.

Nach dem Deinstallieren muss ein **Passkey neu registriert** werden –
Android löscht Passkeys beim Deinstallieren. Das Konto selbst bleibt
erhalten. Details: [docs/SIGNATUR-KEY.md](docs/SIGNATUR-KEY.md).

### Update-Hinweis für alte Builds

Die App kennt ihre Mindestversion selbst: Der Server hält die minimale
Flutter-Build-Nummer in der `app_config`-Tabelle
(`min_app_version_build`, Migration 034/076). Liegt der installierte
Build darunter, zeigt die App beim Start einen Update-Hinweis
(fail-open: bei Netz-/Schema-Fehlern startet die App normal).

Aktuell: `min_app_version_build = 30` (= v0.9.2).
Gesetzt in Migration 132. Migration 130 hatte zuvor auf 29 gehoben
(Support ab v0.9.1); der Sprung auf 30 folgt aus der Alterssperre für
Transit Spark, siehe oben.

## Bugs melden

- **In-App (empfohlen)**: Einstellungen → Bug-Report. Die Meldung
  enthält Version, Geräteinfos und (optional) einen Log-Auszug – das
  beschleunigt die Zuordnung erheblich.
- **GitHub**: [Issues](https://github.com/Toterboy/Thestia/issues)
  anlegen, bitte **Version** (siehe Einstellungen → Info) und
  **Variante** (play/fdroid) angeben.

## Sicherheitslücken

Bitte NICHT als öffentliches Issue melden. Kontaktiere die Maintainer
privat (GitHub-Konto), damit ein Fix vor dem öffentlichen Disclosure
eingespielt werden kann.

## Beta-Hinweis

Thestia ist als Beta klassifiziert (Versionsnummer beginnt mit
`0.`): Schnittstellen und Verhalten können sich jederzeit ändern,
solange die Major-Version 0 ist.
