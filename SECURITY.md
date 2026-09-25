# Sicherheitsrichtlinie

## Unterstützte Versionen

| Version | Support |
| ------- | ------- |
| 0.9.0 und höher (Build 28+) | ✅ |
| unter 0.9.0 (Build < 28) | ❌ (End of Support seit 24.09.2026) |

Ältere Builds erhalten beim Start einen Update-Hinweis (serverseitiges
Mindest-Build-Gate: `app_config.min_app_version_build = 28`,
Migration 034/076). Details: [SUPPORT.md](SUPPORT.md).

## Schwachstellen melden

**Bitte keine Sicherheitsprobleme als öffentliches Issue erstellen!**

Melde sie stattdessen vertraulich an: **security@thestia.de**

Bitte gib an:

- Betroffene Komponente (App / Edge Function / Datenbank-Migration)
- Reproduktionsschritte oder Proof-of-Concept
- Deine Einschätzung der Auswirkung

Du erhältst innerhalb von **72 Stunden** eine Eingangsbestätigung und
regelmäßige Statusupdates, bis das Problem behoben ist. Eine öffentliche
Bekanntmachung erfolgt erst nach Veröffentlichung eines Fixes – gerne mit
Danksagung an dich (opt-in).

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
