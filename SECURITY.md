# Sicherheitsrichtlinie

## Unterstützte Versionen

| Version | Support |
| ------- | ------- |
| 0.9.2 und höher (Build 30+) | ✅ |
| unter 0.9.2 (Build < 30, inkl. aller WispDating-Builds) | ❌ (End of Support – bitte Thestia neu installieren) |

Ältere Builds erhalten beim Start einen Update-Hinweis (serverseitiges
Mindest-Build-Gate: `app_config.min_app_version_build = 30`,
Migration 132). Details: [SUPPORT.md](SUPPORT.md).

Der Support-Zustieg auf v0.9.2 folgt aus der Alterssperre für Transit
Spark (Migration 131): Ältere Builds kennen die Beschränkung auf
Volljährige nicht und können sie umgehen. Details in
[SUPPORT.md](SUPPORT.md#warum-der-support-erst-ab-v092-beginnt).

## Schwachstellen melden

**Bitte keine Sicherheitsprobleme als öffentliches Issue erstellen!**

Melde sie stattdessen vertraulich an: **security@thestia.de**

Bitte gib an:

- Betroffene Komponente (App / Edge Function / Datenbank-Migration)
- Reproduktionsschritte oder Proof-of-Concept
- Deine Einschätzung der Auswirkung

**Zur Bearbeitung:** Thestia ist ein kleines, nebenberuflich betriebenes
Projekt. Eine Sicherheitsmeldung wird zeitnah bestätigt, ein Fix für
bestätigte Probleme folgt so bald wie möglich. Wir nennen bewusst **keine
Frist**: eine Zusage, die nicht gehalten werden kann, ist schlechter als
keine Zusage – sie beschädigt genau das Vertrauen, um das es hier geht.
Wenn dir eine konkrete Frist wichtig ist, frag danach; wenn keine Antwort
kommt, ist das auch eine Information und wird nicht gegen dich verwendet.

**Was wir nicht versprechen:** sofortige Reaktion rund um die Uhr. Für
ein Projekt dieser Größe wäre das eine leere Zusage.

## Angriffsbild

Das dokumentierte Bedrohungsmodell liegt öffentlich in
[docs/THREAT-MODEL.md](docs/THREAT-MODEL.md). Es benennt die
Angriffsflächen, die Maßnahmen und – ausdrücklich – die Restrisiken.
Fehlt dort eine Angriffsfläche, ist das ein wirksamer Hinweis und wird
mit Priorität bearbeitet.

Der Ablauf für gemeldete Vorgänge steht in
[docs/INCIDENT-RESPONSE.md](docs/INCIDENT-RESPONSE.md), die
Abschätzung der Risiken nach Art. 35 DSGVO in
[docs/DSFA.md](docs/DSFA.md).

**Zu den Fristen:** Die 72 Stunden aus Art. 33 DSGVO betreffen die
Meldung einer **Datenpanne an die Aufsichtsbehörde**, nicht die Antwort
an einen Hinweisgeber. Diese Antwort ist freiwillig und in
`SECURITY.md` bewusst ohne Frist zugesagt. Wenn es zu einer bestätigten
Datenpanne kommt, gilt die gesetzliche Frist unverändert – dafür steht
der Ablauf in `docs/INCIDENT-RESPONSE.md`.

## Scope

**In Scope:** dieser Quellcode (Flutter-App, `supabase/functions/`,
`supabase/migrations/`), die bereitgestellten Endpunkte unter
`*.thestia.de`.

**Out of Scope:** automatisiertes Scanning ohne Rücksprache, Spam/Sozial-
Engineering gegenüber Nutzer:innen, fehlende Features, Brute-Force gegen
echte Accounts.

## Hinweis für Finder

Das Projekt verarbeitet besonders sensible Daten (Dating). Ein
verantwortungsvoller Umgang mit gefundenen Daten ist Bedingung für jede
Anerkennung – lösche gefundene Daten umgehend und dokumentiere nur das
Minimum zur Demonstration.

---

## Security-Audit 2026-08: Umsetzung & Operator-Actions

Die Findings aus dem Audit (K-1, H-1…H-9, M-1…M-23, N-1…N-21) wurden in den
Migrationen **056–062**, den Edge Functions und der Flutter-App umgesetzt.
Einige Punkte erfordern BETREIBER-Seitige Aktionen bzw. Entscheidungen:

### Pflicht nach dem Deployment der Migrationen

1. **Invite-System entfernt (H-5, Betreiber-Entscheidung).** Migration 057
   löscht die Tabelle `invite_codes` samt RPCs; die Registrierung ist jetzt
   OFFEN (geschützt durch CAPTCHA im Dashboard + serverseitige
   Rate-Limits). **CAPTCHA-Aktivierung im Dashboard ist damit PFLICHT.**
2. **Rate-Limits kalibrieren.** Neu aktiv: Likes 30/h + 100/d (auch
   `like_user`), Standort-Updates 5/Tag, `get_nearby_profiles` 60/h,
   Distanzabfragen 5/h pro Paar, Reports 5/h + 24-h-Dedup, Dating-Hour-
   Entscheidungen 30/h, `process-location-check` 10/h, `prekeys` DB-limitiert.
3. **Quiz-Fragen ersetzen (M-6).** Die Platzhalter-Fragen haben jetzt
   verteilte `correct_index`-Werte UND werden pro Match gemischt - echte
   Fragen sollten zeitnah eingesetzt werden.
4. **TURN bereitstellen (M-10, optional aber empfohlen).** `ice-config`
   liefert bei gesetzten Secrets kurzlebige TURN-REST-Credentials
   (coturn `use-auth-secret`):
   ```bash
   supabase secrets set TURN_URL="turn:turn.example.com:3478?transport=udp"
   supabase secrets set TURN_SECRET="<coturn shared secret>"
   supabase secrets set TURN_TTL=3600
   ```
   Ohne TURN bleibt es beim bisherigen Verhalten (nur STUN; Peer-IPs
   sichtbar).
5. **Realtime Private Channels (M-10/W-3).** Migration 062 legt die RLS-
   Policy auf `realtime.messages`. Der Client abonniert Signaling-Kanäle
   mit `private: true` (webrtc_service.dart). Ältere App-Versionen mit
   öffentlichem Broadcast funktionieren weiter, sind aber nicht geschützt -
   daher zügig ausrollen.

### Zu bestätigen (aus dem Audit)

- [ ] Leaf-Zertifikats-Pins vor Ablauf aktualisieren:
      `dart run tool/rotate_cert_pins.dart`.

### Bekannte Restriktionen

- Koordinaten werden serverseitig auf ~1 km gerundet "at rest" gespeichert;
  exakte GPS-Werte liegen nie in der DB.
- Der Server liefert an Match-Partner nur noch das Alter, nicht das
  Geburtsdatum (M-3).
- Chat-Nachrichten werden bewusst NIE lokal persistiert (N-8: die
  Persistenz-API wurde entfernt).
- Account-Löschung entfernt jetzt zusätzlich Storage-Objekte (Avatare,
  Intro-Audios, Verifizierungs-Videos) und alle lokalen Schlüssel/Daten
  (M-1, M-17, H-8). Fehlschläge werden dem Nutzer angezeigt (M-12).
