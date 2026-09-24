# WispDating v0.7.0 – Release Notes

> **⚠️ End of Support (seit 24.09.2026):** Diese Version wird **nicht mehr unterstützt** (Bug- und Security-Fixes eingestellt). Bitte auf **v0.9.0 oder neuer** aktualisieren – siehe [SUPPORT.md](../../SUPPORT.md).


Das Sicherheits-Update ist da! Unter der Haube hat sich einiges getan –
damit das Funken sicher bleibt. Bitte aktualisiert zügig, damit alle vom
neuen Schutz profitieren.

## Neu

**Schlüsselwechsel-Warnung** Ändert sich der Verschlüsselungsschlüssel
deines Gegenübers (z. B. nach einer Neuinstallation), zeigt dir die App
das jetzt klar an – mit der Möglichkeit, die Sicherheitsnummer zu prüfen,
bevor ihr weiterchattet.

**Jugendschutz doppelt gesichert** Die Altersregeln (16–17 nur
untereinander, stufenweise Sichtbarkeit ab 18) gelten jetzt direkt auf dem
Server – für Profile, Likes, Matches, Random Chat und die Dating Hour.

## Geändert

- Registrierung jetzt endgültig ohne Einladungscode – das Codesystem wurde
  komplett vom Server entfernt (den Zugang schützt stattdessen CAPTCHA)
- Nach einem Passwort-Reset wirst du auf allen Geräten abgemeldet und
  meldest dich einfach mit dem neuen Passwort neu an
- Dein Geburtsdatum bleibt ab jetzt so, wie du es bei der Registrierung
  angegeben hast – dein Match sieht übrigens nur dein Alter, nie das
  genaue Datum
- Sprachnachrichten verschwinden nach dem Anhören automatisch von deinem
  Gerät
- Bilder werden vor dem Senden von unsichtbaren Metadaten befreit (z. B.
  GPS-Daten) – gilt für Avatare, Chat-Bilder und Screenshots für
  Bug-Reports
- Auf dem Sperrbildschirm stehen keine Nachrichteninhalte mehr
- Dein Standort wird nur noch grob (~1 km) gespeichert; angezeigt wird
  eine Region statt Koordinaten
- „Konto löschen" räumt jetzt wirklich überall auf – auch Avatare,
  Verifizierungs-Videos auf dem Server sowie Verschlüsselungs-Schlüssel
  und temporäre Dateien auf deinem Gerät
- Wenn beim Konto-Löschen etwas schiefläuft, bekommst du das klar
  angezeigt – statt dass dein Account heimlich doch noch existiert

## Für die Technik-Interessierten

- Sessions liegen jetzt im Android Keystore bzw. iOS Keychain statt im
  Klartext-Speicher
- Signal-Protocol-Rework: PreKeys überleben Neustarts, rotieren
  automatisch und Bundles werden selbstständig veröffentlicht – der
  E2E-Aufbau funktioniert damit endlich zuverlässig
- Persistenter Identity-Trust: ein unterschobener Schlüssel wird blockiert
  statt still akzeptiert
- WebRTC-Signaling läuft über autorisierte Realtime-Private-Channels;
  optional ist jetzt ein TURN-Relay (kurzlebige Credentials) anbindbar
- Anti-Trilateration: max. 5 Standort-Änderungen/Tag,
  Speed-Plausibilitätsprüfung serverseitig, Entfernung weiterhin nur in
  5-km-Schritten
- Rate-Limits fast überall: Likes (30/h), Meldungen (5/h + 24-h-Dedup),
  Dating-Hour-Entscheidungen, Standort-Updates, Distanzabfragen – und der
  direkte DB-Pfad für Likes ist geschlossen
- Quiz-Antwortoptionen werden pro Match gemischt (kein „immer Antwort 1"
  mehr)
- Zertifikat-Pinning: Rotation-Fallback akzeptiert nur noch das exakt
  gepinnte Intermediate
- UnifiedPush-Endpunkte werden serverseitig validiert (SSRF-Schutz);
  konstante Zeitvergleiche, persistente Rate-Limits in Edge Functions,
  180-Tage-Retention für Meldungen
- Datenbank-Migrationen 056–062 + Updates für sechs Edge Functions

## Bekannte Einschränkungen

- Ohne konfigurierten TURN-Server klappt die direkte P2P-Verbindung hinter
  sehr strengen Firewalls (z. B. Firmennetze) ggf. weiterhin nicht
- Die Quiz-Fragen sind noch Platzhalter (werden jetzt aber wenigstens pro
  Match gemischt)
- Wer auf einer alten Version bleibt, umgeht den neuen Signaling-Schutz –
  bitte alle zeitnah aktualisieren

Feedback? Wie immer über den Bug-Report in den Einstellungen. Bleibt
sicher – und funkt weiter!
