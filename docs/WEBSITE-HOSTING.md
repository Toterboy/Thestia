# Website-Hosting: der Wechsel von Netlify zu Cloudflare Pages

Stand: 08.11.2026. Betreiber-Anleitung, kein Konzeptpapier.

## Worum es geht

Die Website von Thestia ist winzig: **49 Dateien, 2,04 MB**, reines
HTML/CSS/JS. Kein Server, keine Datenbank, kein PHP. Zwei Adressen
zeigen auf **dasselbe** Projekt:

| Adresse | Inhalt | Heute |
|---|---|---|
| `thestia.de` | die oeffentlichen Seiten (Impressum, Datenschutz, Kinderschutz, Nutzungsbedingungen, Elternbereich, ...) | Netlify |
| `auth.thestia.de` | die CAPTCHA-Seite, die die App beim Registrieren laedt | Netlify |

**Die E-Mail gehoert nicht dazu.** Die MX-Records zeigen auf
`mx1.efwd.spaceship.net` / `mx2.efwd.spaceship.net` - die Mail laeuft
ueber Spaceship, unabhaengig vom Webhosting. Wird die Website umgezogen,
aendert sich daran zuerst gar nichts. (Erst wenn die Nameserver
umgestellt werden, muss die Mail neu eingetragen werden - siehe unten.)

## Warum ueberhaupt wechseln

Netlify Free hat **300 Credits pro Monat**. Nach der aktuellen
Preisliste kostet ein **Production-Deploy 15 Credits** - 20 Deploys im
Monat sind also das Limit, egal ob mit oder ohne Build. Dazu kommen
Bandbreite (20 Credits je GB) und Web-Requests (2 Credits je 10.000
Requests). Der Betreiber will oefter deployen, und genau daran stoesst
er.

Ein Wechsel loest das nur, wenn der neue Hoster **gar keinen Build
braucht**:

| | Netlify (jetzt) | Cloudflare Pages |
|---|---|---|
| Preis | 0 EUR, aber 300 Credits/Monat | 0 EUR |
| Ein Deploy | **15 Credits** (also 20 im Monat) | **Ordner hochladen - kein Build, keine Credits** |
| Bandbreite | 20 Credits je GB (15 GB/Monat frei) | keine Pages-Grenze (Fair Use) |
| Requests | 2 Credits je 10.000 | keine Pages-Grenze (Fair Use) |
| Dateien je Projekt | - | 20.000 (hier 49) |
| Custom Domains je Projekt | - | 100 (hier 2) |
| Zertifikat | automatisch | automatisch (Universal SSL) |
| Startseite (44 KB) | **gemessen: 49-160 ms** TTFB, 15 ms Verbindungsaufbau | Server liefert dieselbe Datei |

Die Website selbst wird von **jedem** Hoster gleich schnell ausgeliefert
(2 MB statisches HTML, gemessen 49 ms bis zur ersten Byte, sobald der
Rand-Cache warm ist). Es gibt keinen Leistungsunterschied - der
einzige echte Unterschied ist der Build-Verbrauch.

### Was die 300 Credits konkret bedeuten

Aus den Preisen errechnet (Netlify-Preisliste, 08.11.2026) und aus den
gemessenen Dateigroessen:

| | Grenze bei 300 Credits | In der Praxis |
|---|---|---|
| Production-Deploys | 15 Credits je Deploy | **20 Deploys im Monat** |
| Bandbreite | 20 Credits je GB | 15 GB - das sind rund **19.000 volle Seitenaufrufe** (die Startseite laedt 0,8 MB Bilder) |
| Web-Requests | 2 Credits je 10.000 | 1,5 Mio - rund 115.000 Seitenaufrufe |

Der wahrscheinlichste Engpass ist also der **Deploy** (20 im Monat),
nicht die Bandbreite. Wer haeufiger deployed, laeuft in die
Deploy-Grenze - unabhaengig davon, wie viele Besucher die Seite hat.

## Die sieben Schritte

### 1. Konto und Zone anlegen

Bei Cloudflare kostenlos anmelden, dann **thestia.de** als Zone
hinzufuegen (Free-Plan). Cloudflare nennt zwei Nameserver.

### 2. Pages-Projekt anlegen (ohne Git!)

`Workers & Pages` -> `Create` -> **Upload assets**. **Kein Git
verbinden** - dann gibt es keinen Build und keine Build-Minuten.

Die Datei zum Hochladen erzeugt das Projekt:

```powershell
python tool/pack_publish.py
```

Das Ergebnis liegt in `releases/publish-<zeit>.zip` (1,42 MB, 49
Dateien). **Alle Dateien liegen im Wurzelverzeichnis des Zips** - das
ist wichtig: mit einem Ordner `passkey-assets/` im Zip wuerde der
Hoster die Seite unterhalb davon ablegen und die Website waere
kaputt.

Das Projekt bekommt eine Adresse wie `https://thestia.pages.dev`.

### 3. Pruefen, BEVOR irgendetwas umgestellt wird

```powershell
python tool/check_websites_live.py --host https://thestia.pages.dev
```

Der Pruefer meldet: alle Adressen erreichbar, die
Sicherheits-Header (CSP, HSTS, X-Frame-Options) vorhanden, die
Passkey-Datei `/.well-known/assetlinks.json` **identisch** mit dem
Publish-Ordner. Solange das rot ist, wird **nichts** umgestellt -
`thestia.de` laeuft dann weiter ueber Netlify.

Der Aufruf prueft ausserdem die beiden bisherigen Domains. Die beiden
roten Punkte, die dort erscheinen (die live ausgelieferte
`assetlinks.json` ist aelter als der Publish-Ordner, und dem
Auth-Host fehlt der `X-Robots-Tag`), verschwinden mit dem naechsten
Deploy auf den neuen Hoster.

### 4. Custom Domains eintragen

Im Pages-Projekt: `Custom domains` -> `Set up a domain` -> einmal
`thestia.de`, einmal `auth.thestia.de`. Ohne diesen Schritt gibt es
laut Cloudflare-Doku einen 522-Fehler.

### 5. Nameserver umstellen (nur fuer thestia.de noetig)

Die **Apex-Domain** (`thestia.de`) geht bei Cloudflare Pages nur mit
Cloudflare-DNS: Cloudflare legt den CNAME auf das Pages-Projekt selbst
an, sobald die Nameserver zeigen. Bei Spaceship auf die beiden
Cloudflare-Nameserver umstellen.

**Wichtig: die DNS-Eintraege wandern mit.** Bei Cloudflare neu
anlegen (die Werte sind live gemessen, Stand 08.11.2026):

| Typ | Name | Inhalt |
|---|---|---|
| MX | `@` | `mx1.efwd.spaceship.net` (Prioritaet 0) |
| MX | `@` | `mx2.efwd.spaceship.net` (Prioritaet 0) |
| TXT | `@` | `v=spf1 include:spf.efwd.spaceship.net ~all` |
| TXT | `@` | `brevo-code:afb542ac4b247a285c3b503c4315581b` |
| TXT | `@` | `google-site-verification=DyDH0klLBn3Q6KJamml4Do-Tm89zOpCkuquFxHoqc7Y` |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com` |
| CNAME | `auth` | `<projekt>.pages.dev` (legt Cloudflare selbst an) |

Den alten A-Eintrag **nicht** mitnehmen: `75.2.60.5` und
`99.83.231.61` sind Netlify-Adressen.

**DKIM:** Ein `_domainkey`-Eintrag wurde bei den ueblichen Selektoren
(`brevo`, `default`, `selector1`, `selector2`, `k1`) **nicht**
gefunden. Falls Brevo einen DKIM-Schluessel eingerichtet hat, steht
der Selektor im Brevo-Konto - dann gehoert der Eintrag ebenfalls nach
Cloudflare. Die SPF-Liste enthaelt nur Spaceships Weiterleitung, nicht
Brevo: fuer den Versand aus der App wird also ohnehin kein Brevo
genutzt.

**Vor dem Umstellen gegenpruefen:** Der Mail-Empfang ist an die
MX-Eintraege gebunden. Nach der Umstellung eine Mail an
`datenschutz@thestia.de` schicken und im Postfach kontrollieren, dass
sie ankommt (nicht nur gesendet wird).

`auth.thestia.de` ist eine Subdomain - dafuer genuegt ein CNAME auf
`<projekt>.pages.dev`. Wird die Nameserver-Umstellung gemacht, muss
der CNAME bei Cloudflare sein, nicht bei Spaceship.

### 6. Zertifikat abwarten und die Passkeys nachziehen

Cloudflare stellt das Zertifikat automatisch aus (das dauert
Minuten). **Damit aendern sich die Fingerabdruecke in
`assetlinks.json`** - Android prueft die Zertifikatskette des Webservers
gegen genau diese Liste. Ohne Anpassung funktionieren die Passkeys auf
Android nicht mehr.

```powershell
python tool/update_assetlinks.py            # liest die Kette live, schreibt die Datei
python tool/check_passkey_assetlinks.py --live
```

Der Ordner `passkey-assets` danach erneut hochladen.

### 7. Endpruefung

```powershell
python tool/check_websites_live.py
python tool/check_passkey_assetlinks.py --live
python tool/check_privacy_deployment.py
```

Alles gruen? Dann ist der Wechsel fertig. Netlify kann man danach
abschalten (das Projekt laesst sich loeschen, das Abo mit).

## Was sich aendert - und was nicht

**Der Auth-Host.** Bei Netlify bekommt `auth.thestia.de` per
domain-bezogener Regel in `_redirects` eine eigene `robots.txt`, die
alles sperrt. Cloudflare Pages kann **keine** domain-bezogenen Regeln
(Doku: "Domain-level redirects: nicht unterstuetzt"). Dort uebernimmt
der Header `X-Robots-Tag: noindex` in `_headers` die Sperre - er gilt
nur fuer `auth.thestia.de`, `thestia.de` bleibt indexierbar. Beides
ist im Publish-Ordner vorbereitet und wird von
`tool/check_publish_folder.py` geprueft.

**Die `_redirects`.** Die Regeln tragen kein Netlify-Ausrufezeichen
mehr (Cloudflare wuerde die ganze Regel ignorieren). Fuer Netlify
aendert das nichts, weil an diesen Quelladressen keine Datei liegt.

**Die `_headers`.** Unveraendert. Cloudflare wertet dieselbe Datei aus
(absolute URLs mit Host sind dort belegt). Sollte Cloudflare die
Einrueckung nicht akzeptieren, meldet es der Pruefer in Schritt 3
fehlende Header (`content-security-policy fehlt`) - dann die Werte in
`_headers` mit Tabulator statt Leerzeichen einruecken.

**Der Publish-Ordner bleibt bei beiden Hostern derselbe.** Es gibt
kein zweites Verzeichnis, das auseinanderlaufen kann.

## Wenn es nicht passt

Der Netlify-Stand laeuft weiter, solange nichts umgestellt wurde. Nach
Schritt 5 (Nameserver) ist der alte Stand nicht mehr per DNS
erreichbar - dann laeuft der Rollback ueber die Nameserver: bei
Spaceship wieder `launch1/launch2.spaceship.net` eintragen und die
alten A-Eintraege zuruecksetzen. Deshalb werden die Nameserver erst
umgestellt, **nachdem** Schritt 3 gruen war.

## Nacharbeiten nach dem Wechsel

- **Die `robots.txt` im Publish-Ordner beschreibt noch Netlify.** Die
  Kommentare dort erklaeren den Host-Rewrite aus `netlify.toml`. Nach
  dem Wechsel stimmt das nicht mehr - die Sperre des Auth-Hosts
  kommt dann aus dem `X-Robots-Tag`-Header. Der Text ist nur ein
  Kommentar (Robots.txt wird an Maschinen gelesen, nicht an
  Menschen), sollte aber nicht falsch sein.
- **Die `pages.dev`-Adresse** ist waehrend der Testphase oeffentlich
  erreichbar und theoretisch indexierbar. Sie verlinken und nach dem
  Umstellen nicht mehr bewerben; falls sie im Index landet, in der
  Search Console die Entfernung beantragen.
- **Netlify abschalten**, wenn der neue Stand laeuft: das Projekt
  loeschen und das Abo beenden. Bis dahin laeuft es weiter und
  verbraucht Credits - also die Deploys dort einstellen.
- **`tool/update_assetlinks.py` laeuft nicht von allein.** Nach jedem
  Wechsel des Zertifikats (das kann auch eine Erneuerung sein) die
  Kette neu lesen und die Datei neu schreiben.

## Was NICHT noetig ist

- **Kein Build-Skript, kein Node, kein CI-Deploy.** Der Ordner wird
  hochgeladen, fertig. Das ist der ganze Unterschied zu Netlify.
- **Kein Hosting-Paket kaufen.** Spaceship Webhosting (ab 25,90 EUR/2
  Jahre) und Netcup braeuchten eine eigene `.htaccess`/`vhost`-Pflege
  und ein Zertifikat je Domain - Aufwand ohne Gegenwert fuer eine
  Website dieser Groesse.
- **Keine Aenderung an der App.** Die App laedt die CAPTCHA-Seite von
  `https://auth.thestia.de/` - dieselbe Adresse wie heute. Das
  Zertifikat der Website ist **nicht** gepinnt: `lib/utils/
  cert_pinning.dart` pinnt nur Supabase und den Hugging-Face-Router.
  Die einzige Kopplung ist die Passkey-Verknuepfung ueber die
  RP-ID `auth.thestia.de` - die laeuft ueber die `assetlinks.json` und
  ist damit in Schritt 6 erledigt.
