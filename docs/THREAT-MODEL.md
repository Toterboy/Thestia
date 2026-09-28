# Threat Model – Thestia

Öffentlich. Stand 2026-09-28, zu `com.thestia.app` (Build 30 / v0.9.2).

Dieses Dokument beschreibt, **wor** Thestia angreifbar ist und welche
Maßnahmen greifen. Zweck ist nicht Vollständigkeit um ihrer selbst
willen, sondern die Belastbarkeit der Zusage in
[SECURITY.md](SECURITY.md): Ein Meldeweg ohne dokumentiertes
Angriffsbild ist eine Zusage ohne Verfahren.

**Kein Versuch der Vollständigkeit.** Es werden die Angriffsflächen
benannt, die aus der Implementierung hervorgehen. Eine Lücke in diesem
Dokument ist kein Freifahrtschein – siehe [Melden](#sicherheitslücken-melden).

## 1. Was Thestia ist

Eine Dating-App im öffentlichen Raum: Menschen finden einander im
Nahbereich (BLE), per Zufall, im Gespräch bei einer Veranstaltung oder
über QR-Code. Nachrichten sind Ende-zu-Ende verschlüsselt, Chats
entstehen aus beidseitigem Signal. Der Betrieb läuft auf Supabase
(Auth, Datenbank, Edge Functions, Realtime, Storage) mit Firebase für
Push und Netlify/Codeberg für statische Dateien.

Diese Mischung ist die eigentliche Angriffsfläche: Ein Nutzer trägt
**E2E-Schutz für Nachrichten** und ist gleichzeitig Teil eines Systems,
das Standort, Nähe, Alter, Verhaltensmuster und Verknüpfungen sichtbar
macht. Der Schutz gilt dem einen, nicht dem anderen.

## 2. Vertrauensgrenzen

| Grenze | Was sie schützt | Was sie *nicht* schützt |
|---|---|---|
| Ende-zu-Ende-Verschlüsselung (Signal-Protokoll) | Nachrichteninhalte vor Betreiber und Server | Metadaten: wer schreibt wem, wann, wie lange |
| Server-Relais | – | Der Server sieht, **wer** mit wem chattet, auch wenn er den Inhalt nicht sieht |
| RLS + `SECURITY DEFINER`-RPCs | Zeilen gegen Fremdzugriff | Logikfehler in den Funktionen selbst |
| Cert-Pinning | Verbindung gegen MITM | Kompromittierter Auslieferungsweg (Play, Netlify) |
| Bildklassifikation on-device | Bild verlässt das Gerät bei Treffer nicht | Bilder, die die Schwelle passieren, gehen zur Moderation |

## 3. Angriffsflächen

### 3.1 Datenbank: `SECURITY DEFINER` und `PUBLIC EXECUTE`

Die gefährlichste Klasse. In Supabase hat jede Funktion per Default
`EXECUTE`-Rechte für die Rolle `anon`. Eine `SECURITY DEFINER`-Funktion
läuft mit den Rechten des Erstellers und **umgeht RLS** – wird sie
falsch parametrisiert, ist jede Zeile der Datenbank les- oder
schreibbar.

Konkretes Fehlerrisiko: `search_path` wird von GoTrue-JWT-Präfixen
beeinflusst, die der Angreifer kontrolliert. Deshalb setzen alle
Sicherheitsfunktionen `SET search_path = public, pg_temp`.

**Maßnahmen**
- Alle sicherheitsrelevanten Funktionen als `SECURITY DEFINER` mit
  explizitem `search_path`, `REVOKE EXECUTE … FROM PUBLIC` und
  gezieltem `GRANT` an `anon` oder `authenticated`
- Interne Hilfsfunktionen ohne Grant – das ist der Grund für die
  `security_invoker`-Umstellung
- Harte Invarianten prüft `tool/check_security_invariants.py`
  (58 Regeln), läuft in CI
- **Restrisiko:** Eine neue Funktion ohne `REVOKE` ist sofort
  weltweit aufrufbar. Kein automatisches Werkzeug verhindert das –
  nur der Review.

### 3.2 Jugendschutz

`age_compatible` und Geschlechtsfilter werden serverseitig geprüft, in
RPCs und in Views. Das ist richtig, weil ein Client-Filter nichts
wert wäre.

**Angriff:** Altersangaben aus dem Profil, Alters-Triage mit
manueller Queue, und die Altersspanne als Suchparameter.
**Maßnahmen:** Serverprüfung in jeder matchenden RPC, nicht nur in der
UI; Altersband-Unschärfe wird nicht automatisch aufgelöst, sondern
queue-t.
**Offen:** kein verbindliches Mindestalter, kein Widerspruchsverfahren,
keine Aufbewahrungsregel für Verifizierungsmedien. Siehe
[ROADMAP](ROADMAP.md).

### 3.3 BLE-Nahbereich

Transit Spark registriert ephemere Tokens und cacht Begegnungen lokal
(45 Minuten). Der Server sieht **zwei** Tokens pro Funke, keine
Geräte-IDs, keine MAC-Adressen.

**Angriffe**
- *Passiver Sniffer:* Advertising-Pakete sind lesbar. Rotierende
  Tokens verhindern, dass ein Token wiedererkannt wird; die Zeiten
  zwischen den Sendungen vergeben allerdings ein Muster.
- *Long-/Cross-Session-Tracking:* nur möglich, wenn ein Finger über
  mehrere Sitzungen stabil bleibt. Resolvable Private Addresses
  rotieren als **Plattformverhalten**; die App kann das für eigenes
  Advertising nicht erzwingen.
- *Jamming / Einspielen:* Ein Angreifer kann Tokens senden und so
  Begegnungen vortäuschen. Kein Treffer entsteht daraus ohne das
  beidseitige Signal.

**Maßnahmen:** Token-Rotation, Jitter der Intervalle, gepulstes
Scanning, Herstellerfilter, serverseitige Gegenprüfung mit
Jugendschutz- und Blockierlogik.
**Restrisiko:** Funk-Metadaten sind nie vollständig unsichtbar. Wer im
Umfeld nur verfolgt werden will, braucht aktive Geräte in Reichweite.
Wir behaupten keine Funk-Unsichtbarkeit.

### 3.4 Standort

Grobe Koordinaten (5-km-Rundung), automatisches Löschen nach 30 Tagen.
Für die Verbindung wird der Standort benötigt.

**Angriffe:** Wiedererkennbare Muster (Wohnung, Arbeitsweg, Haus),
trotz Rundung; Ableitung des Arbeitsplatzes über Zeit.
**Maßnahmen:** Rundung vor dem Speichern, TTL, kein dauerhaft
mitlesbarer Feed.
**Geplant und ungeprüft:** 0.11.0 sieht BSSID- und
Geschwindigkeitsabgleich vor, um „gleicher Zug" zu erkennen. Das wäre
kontinuierliche präzise Standorterfassung und widerspricht der
Zusage im Date-Safety-Check-in. Vor der Umsetzung zu entscheiden, nicht
danach.

### 3.5 Ende-zu-Ende-Verschlüsselung: der wahrscheinlichste Irrtum

Die Verschlüsselung schützt Inhalte. Sie schützt **nicht**:
- wer mit wem und wann kommuniziert
- Bild- und Sprachnachrichten als solche
- die Tatsache, dass überhaupt ein Kontakt besteht

Der Server sieht das Kommunikationsmuster. Wer „lokal" mit „privat"
verwechselt, täuscht sich.

**Maßnahme:** Dokumentation so gefasst (Datenschutzerklärung,
Store-Texte), dass der Relay-Fall benannt ist und keine Funk-
Unsichtbarkeit behauptet wird.

### 3.6 Lieferkette

- **Kompromittierte Abhängigkeit** – eine bösartige Version einer
  transitiven Paket-Abhängigkeit erreicht die App. 16 direkte
  sicherheitsrelevante Pakete sind exakt gepinnt, CVE-Prüfung und SBOM
  laufen je Pipeline-Lauf.
- **Kompromittierter Build-Rechner** – wer den Signing-Key besitzt,
  liefert beliebigen Code. Der Schlüssel liegt nicht im Repository.
- **Firebase-API-Key im Verlauf** – ist historisch passiert: ein
  `google-services.json` lag im Initial-Commit und ist im öffentlichen
  Verlauf sichtbar. Betroffen war das Projekt des Vorgängers, nicht das
  aktuelle. Grundsätzlich: Ein Firebase-API-Key ist ein
  Client-Identifier, kein Geheimnis – aber unbeschränkt ist er ein
  Missbrauchsvektor (Quota, kostenpflichtige APIs). **Nicht
  einschränkbar ohne Zugriff auf die Google Cloud Console.**

### 3.7 Moderation und Drittlandtransfers

Gemeldete Bilder gehen zur Sichtprüfung an ein Team. Dafür werden
serverseitige Zugriffe genutzt.

**Angriffe:** Umgehung der Moderation, Missbrauch des Meldewegs zur
Belästigung, Weitergabe von Bildern an Dritte.
**Maßnahmen:** Reporter-Pseudonymisierung, manuelle Prüfung,
Nachweis-Pflicht, NSFW-Vorprüfung on-device.
**Offen:** Auftragsverarbeitungsverträge je Anbieter (Brevo,
Cloudflare, Firebase) sind nicht im Repository dokumentiert, ebenso
wen die Drittlandübermittlung konkret trägt.

### 3.8 Konten und Authentifizierung

Passkeys, 2FA/TOTP, E-Mail-Bestätigung, CAPTCHA.

**Angriffe:** Account-Übernahme, Passkey-Origin-Verwechslung,
CAPTCHA-Umgehung.
**Maßnahmen:** `apk-key-hash`-Origin-Prüfung serverseitig *und*
Digital-Asset-Links clientseitig, Step-up vor sensiblen Aktionen,
CAPTCHA per Default aktiv. Bekannter Fehlerfall dokumentiert: SHA-1
statt SHA-256 im Origin führt zu `credential verification failed`.
**Betriebsgrenze:** CAPTCHAs greifen nur bei aktivierter
Dashboard-Konfiguration. Ohne sie sendet der Client ein Token, das der
Server ignoriert – der Bot-Schutz ist dann still aus.

## 4. Was wir bewusst nicht tun

- Kein Profilfoto-Katalog im Nahbereich
- Keine Funk-Unsichtbarkeitsversprechen
- Keine Meldung von Inhalten, die der Betreiber nicht lesen kann
- Keine Weitergabe von Zeiträumen, in denen jemand angreifbar war
- Keine Reflexions- oder KI-Features ohne lokalen Betrieb

## 5. Sicherheitslücken melden

`security@thestia.de` – siehe [SECURITY.md](SECURITY.md) für Fristen
und den gewünschten Umfang. Eingangsbestätigung binnen 72 Stunden.

Für dieses Dokument gilt: Fehlt eine Angriffsfläche, ist das ein
wirksamer Hinweis und wird mit Priorität bearbeitet.
