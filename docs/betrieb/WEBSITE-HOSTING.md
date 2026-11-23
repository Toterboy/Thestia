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

**BEIDE TEILEN SICH HEUTE EIN PROJEKT** (Stand 23.11.2026): beide
Adressen zeigen per CNAME auf `chic-tapioca-1e7c68.netlify.app` und
liefern dieselben Dateien. Die Seite entscheidet per Hostname, ob sie
den Sicherheitscheck oder die Landing-Seite zeigt. Bei Infomaniak
werden die beiden **getrennt** (zwei Websites, zwei Verzeichnisse) -
die Hintergruende stehen in Schritt 2.

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

### Was es in der EU gibt (Preise live geprueft am 08.11.2026)

| Anbieter | Land | Preis | Was man dafuer in Kauf nimmt |
|---|---|---|---|
| **netcup Webhosting** | DE (Hetzner-Gruppe, Nuernberg/Falkenstein) | ab **2,69 EUR/Monat** (inkl. 19 % MwSt) | Klassisches Webhosting mit Plesk: zwei vhosts (einer je Domain, der Auth-Host bekommt damit eine eigene `robots.txt` ohne Sonderregel), Let's Encrypt. **Die DNS bleibt bei Spaceship - kein Nameserver-Wechsel, die Mail ruehrt sich nicht.** Die `_redirects`/`_headers` werden in eine `.htaccess` uebersetzt (das ist generierbar). |
| **Hetzner Cloud (VPS + Caddy)** | DE | ca. **4,49-5,99 EUR/Monat** (CX22/CX23) | Volle Kontrolle, Daten in Deutschland, Zertifikat automatisch. Dafuer: Server pflegen (Updates, Firewall), Regeln in einer Caddyfile statt in `_headers`. |
| **all-inkl, Contabo, IONOS, Infomaniak (CH)** | DE / CH | 1-5 EUR/Monat | dieselbe Klasse wie netcup |
| **KeyCDN (dogado, Dortmund)** | DE | ab **4 USD/Monat** Mindestumsatz, EU-Traffic 0,03 USD/GB, TLS gratis, Mindestzahlung 49 USD | **Kein Hoster, sondern ein CDN** - es braucht eine Quelle, also wieder einen Hoster. Als reine CDN-Stufe vor einem Hoster sinnvoll, als Ersatz nicht. |
| **Cloudflare Pages** | US-Firma, EU-Knoten (Frankfurt) | 0 EUR | Der einzige mit Drag&Drop ohne Build. Fuer **diese** Website datenschutzrechtlich unkritisch: sie verarbeitet keine personenbezogenen Daten (statische Dateien, keine Formulare, keine Nutzer-Logs). Die DSGVO-Frage stellt die App (Supabase), nicht die Website. |
| **Vercel Hobby** | US | 0 EUR | Laut eigener FAQ nur "persoenlich, nicht kommerziell" - fuer eine Dating-App mit Nutzern nicht erlaubt; Pro 20 USD/Monat. |

**Die ehrliche Abwaegung:** Wenn die EU-Rechenschaft das Hauptargument
ist, ist **netcup** die beste Wahl (2,69 EUR, deutsche Firma, DNS und
Mail bleiben unangetastet). Wenn der Deploy-Aufwand das Hauptargument
ist, ist **Cloudflare Pages** die beste Wahl (0 EUR, kein Build, kein
Server). Beides geht - und der Publish-Ordner ist fuer beide Wege
vorbereitet.

## Die sieben Schritte

### 1. Konto und Zone anlegen

Bei Cloudflare kostenlos anmelden, dann **thestia.de** als Zone
hinzufuegen (Free-Plan). Cloudflare nennt zwei Nameserver.

### 2. Pages-Projekt anlegen (ohne Git!)

`Workers & Pages` -> `Create` -> **Upload assets**. **Kein Git
verbinden** - dann gibt es keinen Build und keine Build-Minuten.

Die Datei zum Hochladen erzeugt das Projekt:

```powershell
python tool/release/pack_publish.py
```

Das Ergebnis liegt in `releases/publish-<zeit>.zip` (1,42 MB, 49
Dateien). **Alle Dateien liegen im Wurzelverzeichnis des Zips** - das
ist wichtig: mit einem Ordner `passkey-assets/` im Zip wuerde der
Hoster die Seite unterhalb davon ablegen und die Website waere
kaputt.

Das Projekt bekommt eine Adresse wie `https://thestia.pages.dev`.

### 3. Pruefen, BEVOR irgendetwas umgestellt wird

```powershell
python tool/checks/check_websites_live.py --host https://thestia.pages.dev
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
python tool/scripts/update_assetlinks.py            # liest die Kette live, schreibt die Datei
python tool/checks/check_passkey_assetlinks.py --live
```

Der Ordner `passkey-assets` danach erneut hochladen.

### 7. Endpruefung

```powershell
python tool/checks/check_websites_live.py
python tool/checks/check_passkey_assetlinks.py --live
python tool/checks/check_privacy_deployment.py
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
`tool/checks/check_publish_folder.py` geprueft.

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

## Der Infomaniak-Weg (Schweiz, im Studentenprogramm kostenlos)

**ENTSCHEIDUNG (23.11.2026, Betreiber):** Die Website zieht auf
**Infomaniak** um. **Netlify bleibt als Fallback bestehen** - das
Netlify-Projekt wird nicht geloescht, der Publish-Ordner traegt die
Netlify-Dateien weiterhin, und der Upload dorthin bleibt ein Drag &
Drop. Zurueckwechseln heisst: im DNS die A-Records wieder auf Netlify
setzen (siehe Schritt 5 und den Abschnitt "Der Rollback").

Das ist der Weg, wenn der Betreiber noch einen Schulausweis vorlegen
kann: **1 Webhosting (250 GB, 20 Websites) + 1 Mail-Service kostenlos**
fuer die Dauer des Studiums (maximal vier Jahre, jaehrlich mit den
gleichen Unterlagen zu verlaengern). Die Produkte sind identisch mit
den bezahlten, nur die Rechnung entfaellt.

**Und der entscheidende Vorteil gegenueber Cloudflare: die DNS bleibt
bei Spaceship.** Kein Nameserver-Wechsel, keine Mail-Records neu, kein
Risiko fuer `datenschutz@thestia.de` - es aendert sich nur ein
A-Record und ein CNAME.

### 1. Konto und Studentenprogramm

Bei Infomaniak (Schweiz) kostenlos anmelden, dann im Konto das
**Education programme** beitreten. Unterlagen:

* Studentenausweis oder Schulbescheinigung (aktuell, mit Schule, dem
  laufenden Schuljahr und dem Namen)
* Personalausweis (vor und beidseitig)
* die **offizielle Schueler-Mail-Adresse** der Schule

Die Pruefung dauert laut Infomaniak hoechstens 24 Stunden. Danach sind
das Webhosting (250 GB, 20 Websites) und der Mail-Service kostenlos.
Die Domain ist nicht dabei - **die eigene (`thestia.de`) darf verwendet
werden**. Let's Encrypt ist bei jedem Hosting enthalten.

### 2. Die Website anlegen - zwei getrennte oder eine mit Alias?

**BEFUND (23.11.2026):** Bei Netlify sind die beiden Adressen **ein
Projekt**. `thestia.de` und `auth.thestia.de` zeigen beide auf
`chic-tapioca-1e7c68.netlify.app` und liefern dieselben Dateien; die
Seite entscheidet per Hostname, ob sie den Sicherheitscheck oder die
Landing-Seite zeigt (`passkey-assets/index.html`).

Bei Infomaniak kann der Betreiber die beiden **trennen** - das ist der
Weg, den die Entscheidung vom 23.11.2026 geht. Zwei Varianten:

| | eine Website + Alias | zwei Websites (getrennt) |
|---|---|---|
| Verzeichnisse | eines | zwei (`sites/thestia.de`, `sites/auth.thestia.de`) |
| Zertifikate | eines (mit beiden Namen) | je eines |
| Inhalt | einmal hochgeladen | zweimal hochgeladen (dieselben Dateien) |
| `robots.txt` | pro Host (Regel in der `.htaccess`) | pro Verzeichnis |
| Pflege | eine Stelle | zwei Stellen (gleicher Inhalt) |

Das Upload-Skript kann beides: ohne Schalter fuellt es ein
Verzeichnis, mit `--getrennt` zwei.

**IM PANEL:** Fuer `auth.thestia.de` als eigene Website braucht es
eine Domain, die nicht bei Infomaniak liegt - dafuer gibt es im Panel
den Weg "Domain hinzufuegen, die woanders verwaltet wird" (die
Nameserver bleiben dann bei Spaceship, es wird nur ein A-Record bzw.
CNAME eingetragen). Ob Infomaniak die Subdomain dabei als eigene
Website mit eigenem Verzeichnis anlegt oder als Alias, zeigt das
Panel. **Beides geht:** die `.htaccess` trennt die Hosts auch dann
ueber `RewriteCond %{HTTP_HOST}`, wenn beide im selben Verzeichnis
liegen.

**WICHTIG - warum der Auth-Host die oeffentlichen Seiten braucht:**
Die App verlinkt die Rechtsseiten ueber `auth.thestia.de`:
`https://auth.thestia.de/impressum`, `/kinderschutz`,
`/konto-loeschen`, `/threat-model.md` und `/datenschutz`. Das steht so
im Datenschutztext der App (`lib/generated/privacy_policy_de.dart`) und
im Store-Eintrag; die Loesch-URL ist im Play Console Pflicht. Faellt
der Auth-Host auf "nur der Sicherheitscheck" zurueck, sind diese Links
tot - und mit ihnen der Pflichtnachweis im Store.

Deshalb traegt das Verzeichnis des Auth-Hosts **dieselben Dateien**:
Die Trennung ist organisatorisch (eigenes Verzeichnis, eigenes
Zertifikat, eigene `robots.txt`), nicht inhaltlich. Die
CAPTCHA-Seite erkennt sich weiterhin am Hostnamen - am Inhalt muss
nichts geaendert werden.

Soll der Auth-Host spaeter wirklich nur noch der Sicherheitscheck
sein, muessen die Links der App auf `thestia.de` umgestellt werden.
Das ist eine Aenderung an `lib/` (und damit eine neue Fassung) - sie
gehoert nicht in den Hosting-Umzug.

### 3. Das Zertifikat

Pro Website ein Let's-Encrypt-Zertifikat im Panel aktivieren. Das
Zertifikat ist **anders** als das von Netlify - die Fingerabdruecke in
`assetlinks.json` muessen danach neu geschrieben werden (Schritt 6).

### 4. Hochladen

Der Inhalt ist der Ordner `passkey-assets/` (49 Dateien, 2,04 MB) plus
die `.htaccess` aus `webhosting/`.

**DER WEG (23.11.2026, Betreiber):** Der Betreiber laedt selbst
hoch - im Infomaniak-Panel per Drag & Drop. Das Skript
`tool/release/bereite_upload_infomaniak.py` legt ihm dafuer die
fertigen Ordner samt ZIP an:

```powershell
python tool/release/bereite_upload_infomaniak.py
```

Das Ergebnis liegt in `build/informaniak/`:

| Datei | Fuer |
|---|---|
| `thestia.de.zip` | die Website **thestia.de** (die oeffentlichen Seiten) |
| `auth.thestia.de.zip` | die Website **auth.thestia.de** (der Sicherheitscheck) |

Beide enthalten denselben Inhalt (der Sicherheitscheck entscheidet
per Hostname) plus die `.htaccess`. **Nur die `robots.txt` unterscheidet
sich:** im Auth-Ordner ist die gesperrte Fassung (die Datei
`robots-auth.txt` aus dem Publish-Ordner) - dort sollen die Maschinen
nicht herumlaufen.

Der Upload geht dann im Panel: **Website -> Dateien verwalten -> das
ZIP in das Wurzelverzeichnis** (dort, wo die `index.html` liegt).
Achtung: die `.htaccess` beginnt mit einem Punkt - manche
Upload-Werkzeuge ueberspringen Punkt-Dateien. Im Zweifel ueber
SFTP/FTP hochladen oder im Panel die Anzeige der versteckten Dateien
einschalten.

**WO DER UPLOAD IM PANEL STECKT (BEFUND 23.11.2026, Infomaniak-FAQ
1130 "Schnell auf den Server zugreifen (Web-FTP)"):** Es gibt dort
keinen Knopf "Dateien hochladen" auf der Website-Seite selbst. Der Weg
ist:

1. `https://manager.infomaniak.com/v3/ng/products/web/hosting`
   (**Hostings & Websites**).
2. Auf den **Namen des Hostings** klicken (nicht auf den der Website).
3. Im **linken Menü auf `FTP / SSH`** klicken.
4. Die Schaltfläche **`Web FTP`** klicken (braucht kein FTP-Konto - das
   Infomaniak-Passwort genuegt).
5. Im Web-FTP (BEFUND 23.11.2026, Screenshot): Das Startverzeichnis
   ist `/home/clients/<Client-ID>/`. Die Websites liegen unter
   **`sites/`**, und zwar direkt in einem Ordner je Website -
   **`sites/thestia.de/`** und **`sites/auth.thestia.de/`**. Es gibt
   **kein `htdocs`** darunter; der Website-Ordner selbst ist das
   Wurzelverzeichnis (dort liegt schon die Platzhalter-`index.html`).
   Also:
   - `sites/thestia.de/` ← `thestia.de.zip` entpacken
   - `sites/auth.thestia.de/` ← `auth.thestia.de.zip` entpacken

   Vorher liegen dort nur `index.html` (4,4 KB - die Platzhalterseite),
   `.user.ini`, `.infomaniak-maintenance.html` und eine kleine
   `.htaccess` (803 B - der Infomaniak-Standard). Beim Entpacken oder
   Drag & Drop das **Ueberschreiben bestaetigen**. Die Dateien
   `.user.ini` und `.infomaniak-maintenance.html` bleiben unangetastet
   (die braucht Infomaniak).
6. Dateien per **Drag & Drop** aus Windows in das Web-FTP-Fenster
   hineinziehen - oder das ZIP hochladen und im Web-FTP **entpacken**
   (beides wird unterstuetzt, unsere ZIPs sind rund 2,2 MB - Grenze
   50 MB). Die `.htaccess` ist eine Punkt-Datei: falls sie beim
   Drag & Drop fehlt, im Web-FTP einzeln hochladen (dort sind
   versteckte Dateien sichtbar).

**Der Weg per Skript** (falls doch mit Zugangsdaten - die kommen dann
nur aus der Umgebung, nie aus einer Datei und nie als Parameter):

```powershell
$env:INFORMANIAK_HOST = "web12.infomaniak.com"    # aus dem Panel
$env:INFORMANIAK_USER = "thXXXX"                  # der FTP-Benutzer
$env:INFORMANIAK_PATH = "/home/clients/<ID>/sites/thestia.de/"
$env:INFORMANIAK_SSH_KEY = "$HOME\.ssh\id_ed25519"   # optional

python tool/release/deploy_web_informaniak.py --dry-run   # erst ansehen
python tool/release/deploy_web_informaniak.py             # dann hochladen
python tool/release/deploy_web_informaniak.py --pruefen   # mit Live-Pruefung

Remove-Item Env:\INFORMANIAK_HOST, Env:\INFORMANIAK_USER
```

**Zwei Verzeichnisse (die getrennten Websites):** dann kommt der
zweite Pfad dazu, und der Aufruf bekommt `--getrennt`:

```powershell
$env:INFORMANIAK_AUTH_PATH = "/home/clients/<ID>/sites/auth.thestia.de/"

python tool/release/deploy_web_informaniak.py --getrennt --dry-run
python tool/release/deploy_web_informaniak.py --getrennt
```

Die Zugangsdaten kommen **nur aus der Umgebung** - nie aus einer
Datei, nie als Parameter (die landen sonst in der Shell-History). Das
Skript nutzt `rsync`, wenn es da ist, sonst `sftp` (Stapeldatei).

### 5. DNS bei Spaceship

Nur zwei Eintraege aendern sich - **die MX- und TXT-Records bleiben,
wie sie sind**:

| Typ | Name | Inhalt |
|---|---|---|
| A | `@` | die IP-Adresse der Infomaniak-Website (steht im Panel) |
| CNAME | `auth` | der Hostname der Infomaniak-Website (steht im Panel) |

**BEFUND (23.11.2026, live gemessen):** `auth.thestia.de` zeigt auf
`185.176.225.58` (Netlify). Fuer `thestia.de` gibt es **weder einen A-
noch einen AAAA-Record** - die Apex-Domain loest derzeit nicht auf
(die Nameserver von Spaceship antworten "kein A-Record"; vorhanden sind
nur die MX- und TXT-Records). Die oeffentliche Seite ist damit im DNS
gerade nicht erreichbar; der Inhalt liegt unveraendert auf Netlify
(`chic-tapioca-1e7c68.netlify.app` liefert die Startseite mit HTTP
200). Beim Umzug wird der A-Record fuer `@` also neu angelegt - das
ist keine Aenderung, sondern eine Reparatur.

Die alten Netlify-Eintraege (`75.2.60.5`, `99.83.231.61` und der
CNAME auf `chic-tapioca-1e7c68.netlify.app`) werden dadurch ersetzt.
Die Mail laeuft unberuehrt weiter ueber `mx1.efwd.spaceship.net`.

**STAND 23.11.2026, 20 Uhr (nach der DNS-Umstellung des Betreibers):**

| Adresse | Zeigt auf | Zertifikat | Inhalt |
|---|---|---|---|
| `thestia.de` | 185.176.225.58 (Infomaniak) | Let's Encrypt, gilt fuer `thestia.de` **und** `www.thestia.de` | noch die Infomaniak-Platzhalterseite |
| `www.thestia.de` | 185.176.225.58 | dasselbe Zertifikat | noch die Platzhalterseite |
| `auth.thestia.de` | 185.176.225.58 | Let's Encrypt, eigener Host | noch die Platzhalterseite |

**ES FEHLT NUR NOCH DER UPLOAD** (Schritt 4). Die Zertifikate sind
da, die DNS stimmt - die Seiten liefern nur noch die
Infomaniak-Platzhalterseite ("Diese Website ist zurzeit in Bearbeitung").

**`www.thestia.de` wird auf `thestia.de` umgeleitet** (301): eine
Adresse, ein Inhalt. Die Regel steht in `_redirects` (Netlify) und in
der `.htaccess` (Apache) - beide werden aus derselben Quelle erzeugt.

### 6. Passkeys nachziehen und pruefen

```powershell
python tool/scripts/update_assetlinks.py                  # Kette lesen, Datei schreiben
python tool/checks/check_websites_live.py --host https://thestia.de
python tool/checks/check_passkey_assetlinks.py --live
```

**Die Reihenfolge ist wichtig:** `update_assetlinks.py` liest die
Zertifikatskette von **beiden** Hosts (`thestia.de` und
`auth.thestia.de`). Der A-Record fuer `@` muss also schon stehen,
sonst liess das Skript die Kette nicht und bricht ab. Das Skript
schreibt die **stabilen** Glieder der Kette (Root und Zwischen-
zertifikate) in die Datei - das Leaf fehlt bewusst, weil es alle
90 Tage erneuert wird. Beide Hosts bekommen bei Infomaniak ein eigenes
Let's-Encrypt-Zertifikat, aber dieselbe Kette darunter: die Datei
muss deshalb nicht geaendert werden, wenn die Kette gleich bleibt.

Nach dem Schreiben den Publish-Ordner **noch einmal** hochladen (die
`assetlinks.json` ist Teil davon).

## Der Rollback: Netlify bleibt als Fallback

**Der Netlify-Stand bleibt unangetastet.** Das heisst konkret:

* Das Netlify-Projekt wird **nicht** geloescht und das Abo nicht
  gekuendigt - die Deploys dort werden nur eingestellt (die Credits
  laufen sonst auf).
* Der Publish-Ordner traegt weiterhin `netlify.toml`, `_headers` und
  `_redirects` (das Deploy-Skript nimmt sie beim Infomaniak-Upload
  bewusst NICHT mit). Der Upload nach Netlify bleibt damit ein
  Drag & Drop des Ordners `passkey-assets/`.
* **Zurueckwechseln dauert eine Minute:** im DNS (Spaceship) die
  A-Records wieder auf `75.2.60.5` und `99.83.231.61` setzen und den
  CNAME `auth` wieder auf `chic-tapioca-1e7c68.netlify.app`. Fertig -
  die Dateien liegen dort nach wie vor.

Deshalb wird der DNS **erst** umgestellt, wenn der Infomaniak-Stand
geprueft ist (Schritt 6) - und der Publish-Ordner bleibt fuer beide
Hoster derselbe: es gibt kein zweites Verzeichnis, das auseinanderlaufen
kann. (Bei der getrennten Variante kommen zwei Verzeichnisse auf dem
Infomaniak-Server dazu - die sind aber Kopien voneinander, nicht
zwei Versionen der Website.)

### Infomaniak oder Cloudflare Pages?

| | Infomaniak (CH) | Cloudflare Pages |
|---|---|---|
| Preis | 0 EUR (Student) | 0 EUR |
| Daten | eigene Rechenzentren in Genf und Zuerich | US-Firma, EU-Knoten |
| DNS | **bleibt bei Spaceship** | Nameserver-Umstellung noetig (Apex-Domain) |
| Mail | unberuehrt | Records wandern mit (MX, SPF, DMARC) |
| Deploy | SFTP/rsync (`deploy_web_informaniak.py`) | Drag & Drop |
| Server | einer, den man selbst pflegt | keiner |

**Entschieden: Infomaniak** (23.11.2026). Cloudflare Pages bleibt nur
als Notiz im Kopf - die DNS-Umstellung faellt damit weg, und damit auch
das Risiko fuer `datenschutz@thestia.de`.

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
- **`tool/scripts/update_assetlinks.py` laeuft nicht von allein.** Nach jedem
  Wechsel des Zertifikats (das kann auch eine Erneuerung sein) die
  Kette neu lesen und die Datei neu schreiben.

## Die Web-Version der App (v0.12.0) - was sie beim Hosting kostet

Die Roadmap (v0.12.0, "Web-Bridge, Transit-Reachability & Zero-Install
Gast-Verbindungen") nennt **Flutter Web auf Codeberg Pages**. Das ist
richtig - aber die Web-App stellt andere Anforderungen als die
2-MB-Website, und die sind deutlich schaerfer:

| | Die Website heute | Die Flutter-Web-App |
|---|---|---|
| Groesse | 49 Dateien, 2,04 MB | `main.dart.js` (2-6 MB) + CanvasKit/WASM (rund 8 MB) + Fonts |
| Erster Aufruf | 0,8 MB | **10-20 MB** (danach cached) |
| Bandbreite | 15 GB/Monat bei Netlify = 19.000 Aufrufe | dieselbe Grenze = **etwa 1.000 Aufrufe** |
| Tiefe Links | 40 Rewrite-Regeln | **SPA-Fallback** (unbekannte URL -> index.html) |

**Damit faellt Netlify Free fuer die Web-App weg:** 20 Credits je GB
bedeuten 300 Credits = 15 GB = rund 1.000 Erstaufrufe im Monat. Fuer
die Web-App ist Netlify also keine Option - dort muss ein Hoster her,
der Traffic nicht einzeln abrechnet (Hetzner-VPS: 20 TB inklusive,
netcup/Infomaniak: flache Tarife) oder gar keine Grenze kennt
(Cloudflare, Codeberg).

**Ein sinnvoller Split:** Die **Rechtsseiten** (49 Dateien, 2 MB) bleiben
auf Netlify - die kosten fast keine Credits. Die **Web-App** kommt auf
den EU-Hoster unter `web.thestia.de` (eine CNAME-Zeile bei Spaceship,
kein Nameserver-Wechsel, keine Mail-Risiken). Damit bleibt die
Domain `thestia.de` unangetastet und die Passkey-Verknuepfung
(`assetlinks.json` auf `auth.thestia.de`) zeigt weiter auf die
Netlify-Kette.

### Die Kandidaten fuer die Web-App

| | Codeberg Pages | netcup Cloud Web Hosting | Hetzner Cloud + Caddy | Cloudflare Pages |
|---|---|---|---|---|
| Land | DE (Codeberg e.V., Berlin; eigener Text: "Hosted in Europe") | DE (Hetzner-Gruppe) | DE | US-Firma, EU-Knoten (Frankfurt) |
| Preis | 0 EUR | ab **2,17 EUR/Monat** (SSH, Let's Encrypt) | **4,49-5,99 EUR/Monat**, 20 TB Traffic inklusive | 0 EUR |
| Deploy | Forgejo Actions: die CI baut den Flutter-Web-Build | rsync aus der bestehenden GitHub-CI | rsync aus der bestehenden GitHub-CI | Drag & Drop |
| Eigene Domain mit HTTPS | ja (CNAME/ALIAS, Zertifikat automatisch) | ja | ja | ja (die Apex-Domain braucht Cloudflare-DNS) |
| SPA-Fallback | ja (eigene 404-Seite) | `.htaccess` | Caddyfile | `_redirects` |
| Nacharbeit | Flutter-SDK in der CI (grosser Download); das Repository muss oeffentlich sein | `.htaccess` + zwei vhosts | Server pflegen (Updates, Firewall) | keine |

**Details zu Codeberg Pages** (Doku vom 08.11.2026): eigene Domains
gehen (Schritt 1 CNAME/ALIAS, Schritt 2 Autorisierung, Schritt 3
Deploy-Ziel), Zertifikate werden automatisch bezogen, und es gibt
"custom 404 pages, redirects, and rewrites" - damit laesst sich der
SPA-Fallback bauen. Zwei Stolpersteine: die alte Pages-v2 ist fuer
Neuzugaenge gesperrt (nur git-pages), und **wenn die DNS spaeter bei
Cloudflare liegt, muessen die Codeberg-Records auf "DNS only"
(graue Wolke) stehen** - sonst kann Codeberg die Zertifikate und
Umleitungen nicht bedienen.

### Studenten-Rabatte (alle Angaben live geprueft am 08.11.2026)

**Infomaniak (Schweiz) hat ein echtes Studentenprogramm:** **1
Webhosting (250 GB, 20 Websites) + 1 Mail-Service kostenlos** fuer die
Dauer des Studiums - maximal vier Jahre, danach jaehrlich mit den
gleichen Unterlagen zu verlaengern. Die Produkte sind identisch mit
den bezahlten, nur die Rechnung entfaellt.

Bedingungen: Studentenausweis oder Schulbescheinigung (aktuell, mit
Schule, laufendem Schuljahr und Namen), Personalausweis (vor und
beidseitig) und die **offizielle Schueler-E-Mail-Adresse** der
Schule. Die Pruefung dauert laut Infomaniak hoechstens 24 Stunden.
Die Domain ist **nicht** enthalten - man darf aber die **eigene**
(also `thestia.de`) fuer die freien Produkte verwenden. Let's Encrypt
ist bei jedem Hosting enthalten.

| Anbieter | Studentenrabatt |
|---|---|
| **Infomaniak (CH)** | **Webhosting + Mail kostenlos** (bis 4 Jahre, jaehrlich erneuern) |
| **netcup (DE)** | kein Studentenprogramm, aber dauerhafte Gutscheine (6 EUR Gutschein -> 30 % auf die Webhosting-Tarife, 1 Monat gratis auf einen vServer) |
| **Hetzner (DE)** | kein Studentenprogramm; 20 EUR Startguthaben bei Aktionscodes; Einstieg 4,49-5,99 EUR/Monat |
| **IONOS (DE)** | Studentenrabatt ueber **UNiDAYS** (Partnerprogramm) plus Aktionsgutscheine (in den Coupon-Listen bis 94 % im ersten Jahr) |
| **all-inkl (DE)** | kein Studentenrabatt gefunden; 10 Domains, 250 GB, SSH-Zugang |
| **Codeberg (DE)** | 0 EUR fuer alle - dafuer braucht es keinen Rabatt |

**Wichtig:** Ob die Programme greifen, haengt daran, ob noch ein
Schul-/Studentenausweis vorgelegt werden kann. UNiDAYS
(myunidays.com) ist die Sammelstelle fuer die meisten Studentenrabatte;
der GitHub Student Developer Pack bringt bei studentischer Mail-Adresse
zusaetzlich Copilot/Codespaces - fuer das Hosting aber nichts.

## Nebenbei: das alte Vercel-Projekt (7,77 von 10 GB belegt)

BEFUND (08.11.2026, bei der Suche nach dem Credit-Problem): Es gibt
ein Vercel-Projekt `blind-date-app` (verknuepft am 24.07.2026, die
Verknuepfung liegt in `.vercel/project.json`, das ist nicht im
Repository). Es liefert unter `https://blind-date-app.vercel.app` eine
**alte Landingpage** ("Blind Date | Real Conversations") aus - ein
React-Build aus der Zeit vor der Umbenennung.

**Die alte Domain zeigt ebenfalls darauf:** `theblinddate.in` hat
Nameserver von Vercel (`ns1/ns2.vercel-dns.com`) und leitet auf
`www.theblinddate.in` weiter (307). Die Seite hat
`<meta name="robots" content="index, follow">` - sie ist also
**indexierbar**. Zwei Dinge sind damit offen:

1. Eine alte, indexierbare Dating-Seite unter der alten Marke.
2. Der **Deployment-Speicher** von 7,77 GB (Hobby: 10 GB inklusive).
   Jedes Deployment eines verbundenen Repositories zaehlt mit - wird
   die Grenze erreicht, bricht der Deploy ab.

**Was geprueft wurde und was nicht:** Live gemessen liefert das
Projekt ausser `index.html`, `manifest.json` und den Icons die
index.html als Ersatz (SPA-Fallback) - **die APKs, der
Datenbank-Backup-Dump und der `releases/`-Ordner sind NICHT oeffentlich
abrufbar**. Das ist geprueft, nicht vermutet.

**Aufraeumen (zwei Wege):**

*Alles loeschen* (empfohlen, wenn die alte Marke nichts mehr bedeutet):

```powershell
vercel login                      # einmalig, Device-Flow im Browser
vercel project remove blind-date-app
Remove-Item .vercel -Recurse -Force   # die lokale Verknuepfung
```

*Aufraeumen, die alte Domain aber behalten*:

```powershell
vercel login
vercel ls blind-date-app          # die Deployments ansehen
vercel remove <deploymentId>      # die alten Deployments einzeln loeschen
```

Danach im Dashboard unter `Settings -> Git` pruefen, ob das GitHub-
Repository verbunden ist: **das Verbindung trennen**, sonst legt jeder
Push ein neues Deployment an und der Speicher fuellt sich wieder.

**Die alte Domain weiterleiten statt loeschen:** Wenn
`theblinddate.in` auf `thestia.de` zeigen soll, braucht es eine
Domain-Weiterleitung. Bei Vercel geht das ueber `Settings -> Domains
-> Redirects` (301 auf `https://thestia.de`) - das setzt voraus, dass
das Projekt bleibt. Alternativ beim Registrar eine Weiterleitung
einrichten. **Wichtig:** Die Weiterleitung muss mit **301** erfolgen
(keine 302), sonst bleibt die alte Adresse in den Suchergebnissen
stehen.

## Was NICHT noetig ist

- **Kein Build-Skript, kein Node, kein CI-Deploy.** Der Ordner wird
  hochgeladen, fertig. Das ist der ganze Unterschied zu Netlify.
- **Kein Hosting-Paket kaufen.** Spaceship Webhosting (ab 25,90 EUR/2
  Jahre) und Netcup braeuchten eine eigene `.htaccess`/`vhost`-Pflege
  und ein Zertifikat je Domain - Aufwand ohne Gegenwert fuer eine
  Website dieser Groesse. (Wer es trotzdem will: die `.htaccess` laesst
  sich aus `_redirects` und `_headers` GENERIEREN - das ist eine
  Sache von einer Stunde Arbeit, kein Grund, einen Hoster zu
  wechseln.)
- **Keine Aenderung an der App.** Die App laedt die CAPTCHA-Seite von
  `https://auth.thestia.de/` - dieselbe Adresse wie heute. Das
  Zertifikat der Website ist **nicht** gepinnt: `lib/utils/
  cert_pinning.dart` pinnt nur Supabase und den Hugging-Face-Router.
  Die einzige Kopplung ist die Passkey-Verknuepfung ueber die
  RP-ID `auth.thestia.de` - die laeuft ueber die `assetlinks.json` und
  ist damit in Schritt 6 erledigt.
