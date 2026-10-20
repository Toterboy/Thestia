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

## 2. TURN-Relay: coturn aufsetzen

**Warum:** Die `ice-config`-Edge-Function ist deployed, liefert aber
**nur STUN**. Ohne `TURN_URL` und `TURN_SECRET` faellt sie still auf
vier oeffentliche STUN-Server zurueck. Hinter symmetrischen NATs
(some Firmen, viele Mobilfunknetze) kommt dann keine Verbindung
zustande - Video- und Sprachanrufe brechen ab. Die Datenschutz-
Erklaerung listet TURN bisher als genutzt; sie nennt inzwischen die
tatsaechlich genutzten STUN-Anbieter (Abschnitt 6).

**Schritt 1 - coturn auf einem eigenen Server:**

```bash
# Debian/Ubuntu
sudo apt install coturn
```

`/etc/turnserver.conf` (Auszug, wichtig sind die markierten Zeilen):

```ini
listening-ip=0.0.0.0
listening-port=3478
# WICHTIG: eine IP, KEIN Domainname. coturn loest sonst seine eigene
# IP nicht auf und die Credentials sind unbrauchbar.
external-ip=<DEINE-OEFFENTLICHE-IP>

# use-auth-secret ist Pflicht: die Function kann statische
# Credentials nicht - sie erzeugt kurzlebige REST-Credentials.
use-auth-secret
static-auth-secret=<LANGES-ZUFALLSGEHEIMNIS>
realm=thestia.de

# TLS ist optional, aber fuer manche Netze noetig
# cert=/etc/letsencrypt/live/thestia.de/fullchain.pem
# pkey=/etc/letsencrypt/live/thestia.de/privkey.pem
```

Neustarten:

```bash
sudo systemctl restart coturn
sudo systemctl enable coturn
```

Pruefen:

```bash
sudo ss -lnup | grep 3478
```

**Schritt 2 - Secrets in Supabase setzen:**

```bash
supabase secrets set TURN_URL="turn:<DEINE-IP>:3478?transport=udp" TURN_SECRET="<DAS-GEHEIMNIS-AUS-DER-CONFIG>" TURN_TTL=3600
```

`TURN_URL` **muss eine IP-Adresse enthalten**, kein Hostname.

**Schritt 3 - pruefen:** In der App anrufen und im Logcat nachsehen:

```powershell
adb -s a86fc552 logcat -v time | Select-String "WebRTC"
```

Erwartet: `[WebRTC] ICE-Server geladen: N Eintraege` mit **mehr** als
den STUN-Eintraegen. Bei nur STUN steht dort `urls: stun:...`.

**Schritt 4 - Datenschutz nachziehen:** Steht TURN in der Erklaerung
jetzt wieder als genutzter Anbieter, gehoert eine Zeile "TURN-Relay
(eigener Server)" in die Drittanbieter-Tabelle in `docs/DATENSCHUTZ.md`
(Abschnitt 6). Danach:

```powershell
python tool\make_privacy_policy.py
```

---

## 3. Passkeys: dritter Fingerabdruck in `assetlinks.json`

**Warum:** Von Play installierte Apps tragen **Gogs** Signaturzertifikat,
nicht deins. Die Digital-Asset-Links-Pruefung schlaegt ohne dessen
Fingerabdruck fehl - Passkeys funktionieren dann auf Play-Installationen
nicht, obwohl sie lokal funktionieren.

**So geht's:**

1. Play Console -> deine App -> **Setup** -> **App-Integritaet**.
2. Unter **App-Signatur-Schluessel** steht der **SHA-256** des
   Google-Play-Signaturzertifikats. Kopieren.
3. In `passkey-assets/assetlinks.json` den Wert in
   `sha256_cert_fingerprints` **als dritten Eintrag** ergaenzen
   (Grossbuchstaben, Doppelpunkte).
4. `assetlinks.json` auf Netlify hochladen (Abschnitt 1).
5. Pruefen:

   ```powershell
   (Invoke-WebRequest https://auth.thestia.de/.well-known/assetlinks.json).Content
   ```

Der Debug-Fingerabdruck (`5A:B8:D0:D5:...`) und der Release-Fingerabdruck
(`8C:BE:F7:D0:...`) sind bereits drin - die bleiben, weil lokal
installierte Builds weiterhin funktionieren sollen.

---

## 4. Secrets rotieren

**Warum:** `docs/KOMPROMITIERTE-GEHEIMNISSE.md` nennt drei Secrets aus
der Git-Historie, die dort als **offen** gefuehrt werden. Zwei davon
haben echte Wirkungen:

| Secret | Wirkung, wenn es noch gilt |
|---|---|
| `HOOK_SECRET` | `send-confirmation-email` laeuft mit `verify_jwt = false`. Mit dem Secret kann jeder gefaelschte Auth-Hooks senden - Bestaetigungs- und Reset-Mails an fremde Adressen. |
| `WISP_INTERNAL_SECRET` | `notify-user` erlaubt damit Push ohne Beziehungspruefung an beliebige User-IDs - Push-Phishing. |
| Firebase-API-Key | Nur relevant, falls Firebase-Notifications genutzt werden. |

**Rotation:**

```bash
supabase secrets list          # was ist gesetzt?
supabase secrets set HOOK_SECRET="<NEUER-WERT>" WISP_INTERNAL_SECRET="<NEUER-WERT>"
```

Den neuen Wert danach **in der GoTrue-/Auth-Konfiguration** des Projekts
nachtragen, damit die signierte Webhook-Variante weiter funktioniert -
sonst kommen keine Bestaetigungs-Mails mehr an.

Anschliessend in `docs/KOMPROMITIERTE-GEHEIMNISSE.md` die Rotation mit
Datum bestaetigen. Das Dokument ist die Selbstauskunft; eine Rotation,
die dort nicht steht, ist fuer niemanden nachvollziehbar.

---

## 5. Kurz-Checkliste vor dem Store-Upload

- [x] Migration 144 angewendet - live geprueft
- [x] `verify-account` deployt - v69, ACTIVE
- [x] `profile_to_jsonb` gesperrt - live verifiziert
- [ ] Netlify neu hochgeladen, `check_privacy_deployment.py` sagt "OK"
- [ ] Dritter Fingerabdruck (Play) in `assetlinks.json`
- [ ] `HOOK_SECRET` / `WISP_INTERNAL_SECRET` rotiert und dokumentiert
- [ ] `profiles.is_admin` fuer dein Konto gesetzt
- [ ] TURN laeuft, oder die Erklaerung nennt weiterhin nur STUN
- [ ] Admin-Screen im Admin-APK: Warteschlange zeigt Namen und Alter,
      keine `'?'`
- [ ] Physische Abnahme `docs/RELEASE-ABNAHME.md` (4.12-4.17)
