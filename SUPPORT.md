# Support

Danke, dass du WispDating nutzt. Hier steht, welche Versionen unterstützt werden und wie du Feedback/Bug-Reports loswirst.

## Unterstützte Versionen

| Version | Status | Anmerkung |
| --- | --- | --- |
| **v0.9.0 und höher** (Build 28+) | ✅ **Unterstützt** | Bug-Reports willkommen; Security-Fixes |
| **unter v0.9.0** (v0.8.x und älter, Build < 28) | ❌ **End of Support** (seit 24.09.2026) | Keine Bug-/Security-Fixes mehr – bitte aktualisieren |

### Update-Hinweis für alte Builds

Die App kennt ihre Mindestversion selbst: Der Server hält die minimale
Flutter-Build-Nummer in der `app_config`-Tabelle
(`min_app_version_build`, Migration 034/076). Liegt der installierte
Build darunter, zeigt die App beim Start einen Update-Hinweis
(fail-open: bei Netz-/Schema-Fehlern startet die App normal).

Aktuell: `min_app_version_build = 28` (= v0.9.0).

## Bugs melden

- **In-App (empfohlen)**: Einstellungen → Bug-Report. Die Meldung
  enthält Version, Geräteinfos und (optional) einen Log-Auszug – das
  beschleunigt die Zuordnung erheblich.
- **GitHub**: [Issues](https://github.com/Toterboy/Wisp-Datingapp/issues)
  anlegen, bitte **Version** (siehe Einstellungen → Info) und
  **Variante** (play/fdroid) angeben.

## Sicherheitslücken

Bitte NICHT als öffentliches Issue melden. Kontaktiere die Maintainer
privat (GitHub-Konto), damit ein Fix vor dem öffentlichen Disclosure
eingespielt werden kann.

## Beta-Hinweis

WispDating ist als Beta klassifiziert (Versionsnummer beginnt mit
`0.`): Schnittstellen und Verhalten können sich jederzeit ändern,
solange die Major-Version 0 ist.
