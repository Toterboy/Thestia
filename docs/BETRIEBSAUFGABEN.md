# Betriebsaufgaben: was nur du erledigen kannst

Stand: v0.10.0, 20.10.2026. Diese Schritte brauchen Zugang zu
Konten, die nicht im Repository liegen - Netlify, Play Console, dein
coturn-Server, das Supabase-Dashboard.

Erledigt und verifiziert: **Migration 144** (per `supabase db push` auf
`jftuigjbmmuvrckbchqo` angewendet) und **`verify-account`** (auf v69
deployt, `ACTIVE`). Beides ist live geprueft.

---

## 1. Netlify: Datenschutzerklaerung neu hochladen

**Warum dringend:** Live steht noch **Version 5 (v0.9.2)**. Die
veroeffentlichte Erklaerung behauptet "Koordinaten (einmalig bei
Freigabe)" und "Entfernung in 5-km-Schritten". Die App speichert
seit v0.10.0 nur das Bundesland, rastet auf 5 km und zeigt 10-km-Stufen.
Die veroeffentlichte Fassung beschreibt eine App, die es nicht mehr
gibt - ein Widerspruch zum Data-Safety-Formular im Play Store.

**So geht's:**

1. `passkey-assets/` oeffnen. Enthalten sind `datenschutz.html`,
   `assetlinks.json`, `apple-app-site-association`, `index.html`,
   `_headers`, `_redirects`, `netlify.toml`.
2. Bei Netlify anmelden -> das richtige **Site** (das, auf dem
   `auth.thestia.de` laeuft) -> **Deploys** -> **Add new deploy** ->
   **Deploy manually**.
3. Den **Inhalt von `passkey-assets/`** hochziehen - den Ordner
   selbst, nicht die einzelnen Dateien. Netlify ignoriert Ordner mit
   fuehrendem Punkt (`.well-known`) beim Drag-&-Drop; deshalb liegen
   die Dateien im Root und `netlify.toml` rewritet die Pfade intern.
4. Fertig. Pruefen:

   ```powershell
   python tool\check_privacy_deployment.py
   ```

   Muss `OK  live und Repo sind identisch.` sagen. Der Check laeuft
   jetzt auch in der CI.

**Wichtig:** `assetlinks.json` **nicht** veraendern - dort kommt der
Play-Fingerabdruck noch rein (Abschnitt 3).

---

## 2. TURN-Relay: Optionen ohne eigenes Geraet und ohne Kreditkarte

**Warum ueberhaupt:** Die `ice-config`-Edge-Function ist deployed, liefert
aber **nur STUN**. Ohne TURN kommt hinter symmetrischen NATs (Firmen-
netze, viele Mobilfunknetze) keine Verbindung zustande - Video- und
Sprachanrufe bleiben bei "verbinde..." stehen. Die Datenschutz-
Erklaerung nennt inzwischen die tatsaechlich genutzten STUN-Anbieter
(Abschnitt 6); mit TURN kommt eine Zeile fuer den Relay-Anbieter dazu.

Die Function erzeugt **kurzlebige REST-Credentials** nach dem
Standard-Schema: Benutzername = `Ablaufzeit:User-ID`, Kennwort =
base64(HMAC-SHA1(Geheimnis, Benutzername)). Das Schema ist das, was
coturn mit `use-auth-secret` erwartet - und auch das, was die
managed Anbieter unten nutzen. Es muss also NICHTS am Code geaendert
werden, es braucht nur die passenden zwei Werte.

### Option A (empfohlen): Metered Open Relay

**Kostenlos, ohne Kreditkarte.** Metered betreibt einen oeffentlichen
TURN-Relay mit 20 GB im Monat. Das Konto ist kostenlos und verlangt
**keine** Kreditkarte.

1. Konto anlegen: <https://app.metered.ca> (Free-Tarif, keine Karte)
2. Im Dashboard den **TURN-Relay-Schluessel** (shared secret /
   "auth key") holen. Der Schlüssel ist der zweite Wert fuer
   `TURN_SECRET`.
3. Relay-Adresse aus dem Dashboard uebernehmen. Open Relay laeuft
   bewusst ueber **Port 80 und 443** - damit kommen die Verbindungen
   auch durch strenge Firmen-Firewalls. Beide URLs setzen:

   ```bash
   supabase secrets set \
     TURN_URL="turn:openrelay.metered.ca:80?transport=tcp" \
     TURN_SECRET="<der TURN-Schluessel aus dem Dashboard>"
   ```

   Optional zusaetzlich ueber 443 (TLS):

   ```bash
   supabase secrets set TURN_URL="turn:openrelay.metered.ca:80?transport=tcp,turns:openrelay.metered.ca:443?transport=tcp"
   ```

4. Pruefen, ob die Function jetzt TURN liefert:

   ```bash
   supabase functions logs ice-config
   ```

   Erwartet wird ein Eintrag mit "ICE-Server geladen: 5 Eintraege"
   (4 STUN + 1 TURN). Bleibt es bei 4, ist eines der beiden Secrets
   nicht gesetzt.

**Grenzen:** 20 GB pro Monat. Jede weitergeleitete Minute zaehlt
doppelt (ein- und ausgehend). Fuer eine App mit wenigen gleichzeitigen
Anrufen reicht das; bei vielen Videocalls laeuft das Volumen schnell
voll. Ausserdem: der Anbieter sieht die IP-Adressen der Nutzer - das
ist in der Erklaerung zu nennen.

### Option B: ein gemieteter Server (nicht "bei mir zu Hause")

Wenn dir 20 GB nicht reichen: ein kleiner VPS mit coturn. Das ist ein
fremder Server, kein Geraet von dir, aber mit Abo.

- **Ein Server mit eigener IPv4** ist Pflicht. NAT-Plaene akzeptieren
  von aussen nur SSH - TURN lebt aber genau von eingehenden
  Verbindungen auf vielen Ports.
- **coturn ab Version 4.13.0.** Darunter gibt es zwei gemeldete
  Luecken: eine Loopback-Umgehung, ueber die ein angemeldeter TURN-
  Nutzer Dienste freilegen kann, die nur auf dem Host an localhost
  gebunden sind (CVE-2026-53450), und eine Format-String-Injektion
  ueber den TURN-Benutzernamen in den Redis-Befehl (CVE-2026-68522).
  Beide sind mit 4.13.0 behoben.
- Konfiguration wie in der urspruenglichen Fassung dieser Datei:
  `use-auth-secret`, `static-auth-secret`, `external-ip` als **IP**
  (kein Domainname - sonst loest coturn seine eigene IP nicht auf),
  Ports 3478 (UDP/TCP) und 49152-65535 (UDP) freigeben.

Beispiel einer Anbieter-Auswahl ohne Kreditkartenpflicht und ohne
Kontoerfassung: EQVPS rechnet in Krypto, ohne KYC, ab rund 8 EUR pro
Monat fuer einen Plan mit eigener IP.

### Option C: Xirsys

Kostenloser TURN-Account mit festem Limit. **Pruefen, ob statische
Credentials** angeboten werden - die Function kann nur kurzlebige
REST-Credentials. Falls statisch angeboten wird, braucht es eine
Aenderung an der Function (einen zusaetzlichen Secret-Pfad fuer
`username`/`credential` statt HMAC).

### Nicht passend

| Anbieter | Warum nicht |
|---|---|
| Cloudflare TURN | Du willst keine Kreditkarte hinterlegen. Ausserdem ist Cloudflare fuer TURN ueber Cloudflare Calls gebunden. |
| ngTurn | Kein kostenloser Tarif, und jeder Tarif startet mit einer Kartenpruefung. |
| Twilio TURN | STUN ist kostenlos, TURN kostet pro GB. Das Konto laesst sich ohne Karte anlegen, der TURN-Preis aber nicht umgehen. |

## 3. Google Play Console: App anlegen und den Fingerabdruck holen

**Warum:** Von Play installierte Apps tragen **Gogs** Signaturzertifikat,
nicht deins. Die Digital-Asset-Links-Pruefung fuer Passkeys schlaegt ohne
dessen Fingerabdruck fehl - Passkeys funktionieren dann auf
Play-Installationen nicht, obwohl sie lokal funktionieren. Und solange
es die App in der Console nicht gibt, kann es auch keine
Play-Signatur geben.

Die beiden Fingerabdruecke im Bild sind verschiedene Dinge:

| Zertifikat | Wessen Fingerabdruck | Wo in der Console |
|---|---|---|
| **Upload key certificate** | Dein eigener Release-/Upload-Schluessel | Setup -> App-Integritaet (nur sichtbar, wenn der eigene Schluessel hochgeladen wurde) |
| **App signing key certificate** | **Gogs** Schluessel, mit dem Play die App umsigniert | Setup -> App-Integritaet -> "App-Signatur-Schluessel" |

**In die `assetlinks.json` gehoert der zweite** - der von Google. Mit dem
Upload-Key-Fingerabdruck funktionieren die Passkeys auf Play-Builds
nicht.

### 3.1 App in der Console anlegen

1. <https://play.google.com/console> anmelden (Google-Konto).
2. **App erstellen**.
   - **App-Name:** Thestia
   - **Standardsprache:** Deutsch
   - **App oder Spiel:** App
   - **Kostenlos oder bezahlt:** Kostenlos
   - Die vier Deklarationen (Datenschutz, Datenschutzrichtlinie,
     Werbung, Zielgruppe) beantworten. Auf die Datenschutzrichtlinie
     kommt die URL der veroeffentlichten Erklaerung - siehe Abschnitt 1.
3. Nach dem Anlegen bist du in der **App-Uebersicht**. Es geht direkt
   weiter mit 3.2, auch wenn die App noch nicht fertig konfiguriert
   ist - der Fingerabdruck ist unabhaengig davon verfuegbar.

### 3.2 Fingerabdruck holen

1. **Setup** (in der linken Leiste) -> **App-Integritaet**.
2. Unter **App-Signatur-Schluessel** steht eine Zeile
   "App-Signatur-Schluessel-Zertifikat" mit dem **SHA-256**-Fingerabdruck
   (Format `AA:BB:CC:...`).
   - Ist der Abschnitt leer, hat Play das Signieren noch nicht
     eingerichtet. Das passiert beim ersten Hochladen einer AAB - dann
     zuerst hochladen und danach wiederkommen.
3. Den Fingerabdruck in `passkey-assets/assetlinks.json` als
   **dritten Eintrag** in `sha256_cert_fingerprints` eintragen
   (Grossbuchstaben, Doppelpunkte, gleiche Formatierung wie die
   beiden anderen).
4. `assetlinks.json` auf Netlify hochladen (Abschnitt 1).

### 3.3 Was sonst noch in der Console konfiguriert werden muss

Das ist der Teil, der beim Upload auffaellt - der Fingerabdruck
allein reicht nicht:

- **Store-Eintrag** mit Text, Bildern (Icon 512x512, Feature Graphic
  1024x500, Screenshots je Formfaktor) und der
  **Datenschutzrichtlinien-URL**.
- **App-Inhalte**: Altersfreigabe. Hier wird die Altersgrenze eingetragen
  - die App hat ein 16+-System, Transit Spark zusaetzlich 18+.
- **Zielgruppe und Inhalt**: Altersgruppen, keine Werbung, keine
  Datenerhebung durch Dritte ausser den in der Erklaerung genannten.
- **Daten sicherheit** (Data Safety): Hier ankreuzen, welche Daten
  erhoben werden. Das muss mit der Datenschutzerklaerung uebereinstimmen
  - **die Erklaerung nennt "Land", "Geraetekennung", "Bild-Pruefhash",
  "Standort-Zeitstempel" und das Kontomerkzeichen**; die vergessenen
  Punkte sind im Audit als B10 notiert und sollten hier mit angegeben
  werden, sonst widersprechen sich die beiden Formulare.
- **Datenschutzrichtlinie**: URL der veroeffentlichten Erklaerung.
- **Konto loeschen**: eine URL, auf der ein Konto geloescht werden
  kann. Die App hat die Funktion bereits im Datenschutz-Bereich - die
  Play-Konfiguration verlangt aber eine oeffentlich erreichbare Seite,
  nicht nur einen Screen in der App.

## 4. Secrets rotieren

**Erledigt:** `THESTIA_INTERNAL_SECRET` ist umbenannt **und rotiert**
(20.10.2026). Verifiziert: Vault und Function-Secret haben denselben
SHA-256-Hash, das alte `WISP_INTERNAL_SECRET` ist aus beiden Stores
entfernt.

Die Umbenennung war noetig, weil "wisp" ein Fremdname aus einem
anderen Projekt war - und sie musste **vor** der Rotation passieren,
sonst haette die Function in der Zwischenzeit ohne Secret
dagestanden (fail-closed, also kein Push). Migration 146 macht den
Umbenennen im Vault und im Trigger, Migration 146 ist live.

**Offen: `HOOK_SECRET`.** Das kann **nicht** von hier aus gedreht
werden: GoTrue vergleicht den Hook-Signatur-Wert gegen seine eigene
Konfiguration (`GOTRUE_HOOK_SECRET`), und die verwalte nur das
Supabase-Dashboard. Ein blindes Drehen des Function-Secrets wuerde
alle Bestaetigungs- und Reset-Mails sofort zerstoeren.

**Deshalb hier, in dieser Reihenfolge:**

1. **Dashboard:** Supabase -> **Project Settings** -> **Authentication**
   -> **Hooks** (bzw. *Email Auth Hooks*) -> dort den geheimen Wert
   erneuern. Einen neuen, zufaelligen Wert erzeugen:

   ```powershell
   python -c "import secrets; print(secrets.token_hex(32))"
   ```

2. **Derselbe Wert** als Function-Secret setzen:

   ```bash
   supabase secrets set HOOK_SECRET="<DER WERT AUS SCHRITT 1>"
   ```

   Die Reihenfolge ist egal, beide muessen innerhalb weniger Minuten
   gesetzt sein - dazwischen sind die Hooks unbenutzbar.

3. **Pruefen:** Eine Registrierung ausloesen und pruefen, ob die
   Bestaetigungs-Mail ankommt. Der Versand laeuft ueber den Auth-Hook,
   nicht ueber die App - eine kaputte Konfiguration faellt erst dort
   auf.

4. **Dokumentieren:** In `docs/KOMPROMITIERTE-GEHEIMNISSE.md` die
   Rotation mit Datum bestaetigen. Das Dokument ist die Selbstauskunft;
   eine Rotation, die dort nicht steht, ist fuer niemanden
   nachvollziehbar.

**Firebase-API-Key:** Nur relevant, falls Firebase-Notifications
genutzt werden. Im Projekt laeuft der Push ueber den eigenen
UnifiedPush-/FCM-Weg; der Key ist damit kein Zugriffsschluessel auf
Nutzertaten, sollte aber aus den KOMPROMITIERTEN-Listen-Eintraegen
herausrotiert werden, wenn Firebase tatsaechlich genutzt wird.

---

## 5. Kurz-Checkliste vor dem Store-Upload

- [x] Migration 144 angewendet - live geprueft
- [x] `verify-account` deployt - v69, ACTIVE
- [x] `profile_to_jsonb` gesperrt - live verifiziert
- [ ] Netlify neu hochgeladen, `check_privacy_deployment.py` sagt "OK"
- [ ] Dritter Fingerabdruck (Play) in `assetlinks.json`
- [x] `THESTIA_INTERNAL_SECRET` umbenannt und rotiert - verifiziert
- [ ] `HOOK_SECRET` rotiert (Dashboard zuerst, siehe Abschnitt 4)
- [ ] `profiles.is_admin` fuer dein Konto gesetzt
- [ ] TURN laeuft, oder die Erklaerung nennt weiterhin nur STUN
- [ ] Admin-Screen im Admin-APK: Warteschlange zeigt Namen und Alter,
      keine `'?'`
- [ ] Physische Abnahme `docs/RELEASE-ABNAHME.md` (4.12-4.17)
