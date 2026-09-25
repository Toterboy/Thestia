# Play Integrity (Video-Verifizierung, v0.9.0)

Play-Builds attestieren bei der Video-Verifizierung App + Gerät:
Ein modifizierter Client (umgepacktes APK, Emulator, gerootetes Gerät
ohne Device-Integrität) besteht das Google-Verdict nicht und landet
in der manuellen Prüfung – das Auto-Badge gibt es nur für echte,
unveränderte Play-Installationen auf integeren Geräten.

## Verhalten

- Nur `action: "auto"` in `verify-account` prüft; `submit` (manuelle
  Queue) ist unberührt.
- Token MITgeschickt + Verdict schlecht → `422` (manuelle Prüfung,
  fail-closed dorthin, kein harter Fehler).
- KEIN Token (F-Droid, iOS, alte Builds, Play-Dienste-Fehler) →
  bisheriger Pfad; die Stichprobe (Migration 120) bleibt das Netz.
- `PLAY_INTEGRITY_SA_JSON` fehlt → Auto mit Token wird abgelehnt
  (laut Function-Log), manuelle Queue greift. Kein stilles Fail-open.

Gefordert: `appRecognitionVerdict == PLAY_RECOGNIZED` UND
`MEETS_DEVICE_INTEGRITY` oder `MEETS_STRONG_INTEGRITY` (reines
`MEETS_BASIC_INTEGRITY` reicht nicht), Package
`com.thestia.app`, Nonce-Gleichheit, Token-Alter < 10 Minuten.

## Wichtig: Ohne Play-Eintrag bleibt das Feature stumm

Stand heute liegt die App **nur auf GitHub, nicht bei Google Play**.
Play Integrity attestiert nur Apps, die Play kennt:

- Solange KEIN Play-Eintrag existiert (kein Track, auch nicht
  intern), schlagen Token-Anfragen fehl bzw. Verdicts negativ aus –
  alles fällt sicher auf die manuelle Queue zurück. Nichts stürzt
  ab, nichts wird blockiert, es gibt nur kein Auto-Badge per
  Verdict. By design, kein Bug.
- Scharf wird das Feature mit dem **ersten Play-Upload** (interner
  Testtrack reicht): Play-Build von dort installieren → echte
  Verdicts → Auto-Badge bei 2-Jahre-Regel + bestandenem Verdict.
- Auch serverseitig geht ohne verlinktes Cloud-Projekt nichts
  (Decode-API) – ebenfalls erst mit Play-Eintrag einrichtbar.

## Einrichtung (Betreiber, einmalig – erst mit Play-Eintrag möglich)

0. App in der **Play Console anlegen** (mindestens interner
   Testtrack mit Upload) – ohne Play-Eintrag siehe Abschnitt oben.
1. **Play Console** → betroffene App → *App-Integrität* → dort
   verlinktes Google-Cloud-Projekt notieren (ggf. neu verknüpfen).
2. **Google Cloud Console** (desselben Projekts) → *IAM &
   Admin* → *Dienstkonten* → neues Dienstkonto (keine zusätzliche
   IAM-Rolle nötig) → *Schlüssel* → JSON-Key erstellen + lokal
   speichern (niemals committen).
3. Secret setzen + Function neu deployen:
   ```bash
   supabase secrets set PLAY_INTEGRITY_SA_JSON='<Inhalt der JSON-Datei>'
   supabase functions deploy verify-account
   ```
4. Migration 120 (`supabase db push`) nicht vergessen – sie ist das
   Netz für alle Fälle ohne Token.

## Test

- Play-Build aus dem **internen Testtrack** installieren: Echte
  Verifizierung mit 2-Jahre-Abweichung → Badge sofort (Server-Log
  zeigt keine integrity-Fehler).
- Lokal gebautes (`flutter run`) oder umsigniertes APK: Integrity
  liefert Fehler → Token fehlt → bisheriger Pfad (manuell oder
  Auto ohne Verdict, je nach Abweichung). By design, kein Bug.
- Verdict absichtlich brechen (Test): Function-Log
  (`integrity: app/device verdict …`) + `422` im Client.
