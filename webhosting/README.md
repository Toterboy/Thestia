# Webhosting: die Apache-Konfiguration fuer Infomaniak

Dieser Ordner gehoert zum **klassischen Webhosting** (Infomaniak,
Schweiz). Dort laeuft Apache; Netlify und Cloudflare Pages lesen
stattdessen die Dateien `_redirects` und `_headers` direkt.

## Was hier liegt

| Datei | Herkunft | Aenderung |
|---|---|---|
| `.htaccess` | **erzeugt** von `tool/web/make_htaccess.py` | niemals von Hand - das naechste Erzeugen ueberschreibt sie |
| `README.md` | diese Datei | ja |

Die `.htaccess` enthaelt die 38 Rewrite-Regeln aus `_redirects` und
die Sicherheits-Header aus `_headers` in Apache-Syntax, dazu die
Besonderheit des Auth-Hosts (`auth.thestia.de` bekommt die gesperrte
`robots.txt` und den Header `X-Robots-Tag: noindex`).

## Wenn sich etwas aendert

```powershell
python tool/web/make_htaccess.py           # die Datei neu erzeugen
python tool/checks/check_publish_folder.py    # prueft, dass alles zusammenpasst
```

Der Publish-Ordner-Gate schlaegt auch dann rot, wenn die `.htaccess`
veraltet ist - also wenn jemand `_headers` oder `_redirects` geaendert
hat, ohne die `.htaccess` neu zu erzeugen.

## Der Upload (nach Infomaniak)

**Das Skript macht das** (es prueft vorher den Publish-Ordner, nimmt
die Netlify-Dateien nicht mit und laedt die `.htaccess` als Letzte):

```powershell
$env:INFORMANIAK_HOST = "web12.infomaniak.com"    # aus dem Panel
$env:INFORMANIAK_USER = "thXXXX"                  # der FTP-Benutzer
$env:INFORMANIAK_PATH = "/home/www/thXXXX/thestia.de/htdocs/"
$env:INFORMANIAK_SSH_KEY = "$HOME\.ssh\id_ed25519"   # optional

python tool/release/deploy_web_informaniak.py --dry-run   # erst ansehen
python tool/release/deploy_web_informaniak.py             # dann hochladen

Remove-Item Env:\INFORMANIAK_HOST, Env:\INFORMANIAK_USER
```

Die Zugangsdaten kommen **nur aus der Umgebung** - nie aus einer Datei,
nie als Parameter (die landen sonst in der Shell-History).

### Mit SFTP (jeder SFTP-Client)

Der Inhalt der Website ist der Ordner `passkey-assets/` (49 Dateien,
2,04 MB). Er kommt **in das Wurzelverzeichnis der Website** (dort, wo
die `index.html` liegt) - zusammen mit der `.htaccess` aus diesem
Ordner.

| | |
|---|---|
| Server | die Adresse aus dem Infomaniak-Panel (Site Creator -> Website -> FTP/SFTP) |
| Benutzer | der Infomaniak-Benutzername |
| Passwort | das FTP-Passwort (im Panel gesetzt) |
| Ziel | das Wurzelverzeichnis der Website (z. B. `/home/www/<benutzer>/<website>/htdocs/`) |

Dabei **nicht** vergessen: die `.htaccess` aus diesem Ordner. Sie
beginnt mit einem Punkt - manche SFTP-Clients zeigen Punkt-Dateien
nicht an ("Versteckte Dateien anzeigen" einschalten).

### Mit rsync (ueber SSH)

Infomaniak bietet fuer das Webhosting SSH an ("Connect via SSH and
use command-line tools", Doku vom 08.11.2026). Damit:

```powershell
# Der Inhalt (ohne die Konfigurationsdateien, die Netlify liest)
rsync -avz --delete `
  --exclude "_headers" --exclude "_redirects" --exclude "netlify.toml" `
  passkey-assets/ <benutzer>@<server>:/home/www/<benutzer>/<website>/htdocs/

# Die .htaccess danach (die Datei ist ein Punkt - manche Clients
# schlucken Punkt-Dateien beim rsync deshalb gesondert)
rsync -avz webhosting/.htaccess <benutzer>@<server>:/home/www/<benutzer>/<website>/htdocs/.htaccess
```

**Achtung bei `--delete`:** Der Aufruf loescht im Ziel alles, was
nicht im Quellordner liegt. Vor dem ersten Mal mit `--dry-run` testen
(`rsync -avzn --delete ...`).

### Zwei Websites oder eine mit Alias?

**ENTSCHEIDUNG (23.11.2026):** zwei Websites, also zwei Verzeichnisse
(`thestia.de/htdocs` und `auth.thestia.de/htdocs`). Bei Netlify sind
beide Adressen ein Projekt; bei Infomaniak trennt der Betreiber sie.

Der Auth-Host und die oeffentliche Seite liefern **denselben Inhalt**
(beide Domains zeigen auf dasselbe Projekt). Der Grund ist nicht
Bequemlichkeit: die **App verlinkt die Rechtsseiten ueber
`auth.thestia.de`** (`/impressum`, `/kinderschutz`, `/konto-loeschen`,
`/threat-model.md`, `/datenschutz`) - im Datenschutztext der App, im
Store-Eintrag und als Pflichtangabe im Play Console. Diese Links
muessen weiter funktionieren.

| | eine Website + Alias | zwei Websites (der gewaehlte Weg) |
|---|---|---|
| Verzeichnisse | eines | zwei |
| Zertifikate | eines | je eines |
| Inhalt | einmal hochgeladen | zweimal (dieselben Dateien) |
| `robots.txt` | pro Host (Regel in der `.htaccess`) | pro Verzeichnis |

1. **Zwei Websites** (gewählt): je ein Verzeichnis, je ein Zertifikat.
   Im Verzeichnis des Auth-Hosts liegt die gesperrte `robots.txt`
   (die Datei `robots-auth.txt` aus dem Publish-Ordner als `robots.txt`).
2. **Eine Website + Alias-Domain**: beide teilen sich das
   Wurzelverzeichnis - und die `.htaccess` unterscheidet die Hosts
   ueber `RewriteCond %{HTTP_HOST}` und `SetEnvIf Host`.

Das Upload-Skript macht die getrennte Variante mit `--getrennt`:

```powershell
$env:INFORMANIAK_AUTH_PATH = "/home/www/thXXXX/auth.thestia.de/htdocs/"

python tool/release/deploy_web_informaniak.py --getrennt --dry-run
python tool/release/deploy_web_informaniak.py --getrennt
```

## Nach dem Upload pruefen

```powershell
python tool/checks/check_websites_live.py --host https://thestia.de
python tool/checks/check_passkey_assetlinks.py --live
```

Der erste Befehl prueft alle Adressen, die Sicherheits-Header (an der
Antwort des Servers, nicht an der Datei) und ob die live ausgelieferte
`assetlinks.json` mit dem Publish-Ordner uebereinstimmt. Der zweite
prueft, ob die Fingerabdruecke zur echten Zertifikatskette passen -
das ist die Bedingung dafuer, dass die Passkeys auf Android
funktionieren.

## Was beim Zertifikat passiert

Infomaniak stellt pro Website ein Let's-Encrypt-Zertifikat aus. Das
Zertifikat ist **anders** als das von Netlify - und damit aendern
sich die Fingerabdruecke, gegen die Android die Kette prueft. Nach
dem Aktivieren des Zertifikats:

```powershell
python tool/scripts/update_assetlinks.py           # Kette live lesen, Datei schreiben
python tool/checks/check_passkey_assetlinks.py --live
```

und den Publish-Ordner noch einmal hochladen.

## Fuer die Web-Version der App (v0.12.0)

Die Web-App kommt in ein **eigenes** Verzeichnis (nicht in das der
Website) - sie ist eine eigene Anwendung mit eigenem Build. In ihrer
`.htaccess` kommt der SPA-Fallback dazu (unbekannte Adressen liefern
`index.html`); die Zeile steht schon als Kommentar am Ende der
erzeugten Datei.
