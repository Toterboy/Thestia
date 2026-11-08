# Webhosting: die Apache-Konfiguration fuer Infomaniak

Dieser Ordner gehoert zum **klassischen Webhosting** (Infomaniak,
Schweiz). Dort laeuft Apache; Netlify und Cloudflare Pages lesen
stattdessen die Dateien `_redirects` und `_headers` direkt.

## Was hier liegt

| Datei | Herkunft | Aenderung |
|---|---|---|
| `.htaccess` | **erzeugt** von `tool/make_htaccess.py` | niemals von Hand - das naechste Erzeugen ueberschreibt sie |
| `README.md` | diese Datei | ja |

Die `.htaccess` enthaelt die 38 Rewrite-Regeln aus `_redirects` und
die Sicherheits-Header aus `_headers` in Apache-Syntax, dazu die
Besonderheit des Auth-Hosts (`auth.thestia.de` bekommt die gesperrte
`robots.txt` und den Header `X-Robots-Tag: noindex`).

## Wenn sich etwas aendert

```powershell
python tool/make_htaccess.py           # die Datei neu erzeugen
python tool/check_publish_folder.py    # prueft, dass alles zusammenpasst
```

Der Publish-Ordner-Gate schlaegt auch dann rot, wenn die `.htaccess`
veraltet ist - also wenn jemand `_headers` oder `_redirects` geaendert
hat, ohne die `.htaccess` neu zu erzeugen.

## Der Upload (nach Infomaniak)

Der Inhalt der Website ist der Ordner `passkey-assets/` (49 Dateien,
2,04 MB). Er kommt **in das Wurzelverzeichnis der Website** (dort, wo
die `index.html` liegt) - zusammen mit der `.htaccess` aus diesem
Ordner.

### Mit SFTP (jeder SFTP-Client)

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

Der Auth-Host und die oeffentliche Seite liefern **denselben Inhalt**
(beide Domains zeigen auf dasselbe Projekt). Es gibt zwei Wege:

1. **Eine Website + Alias-Domain** (empfohlen): `auth.thestia.de` wird
   als zweite Domain der Website eingetragen. Beide teilen sich das
   Wurzelverzeichnis - und die `.htaccess` unterscheidet die Hosts
   ueber `RewriteCond %{HTTP_HOST}` und `SetEnvIf Host`.
2. **Zwei Websites** mit zwei Verzeichnissen: dann kommt der Inhalt
   zweimal hoch, und im Verzeichnis des Auth-Hosts muss `robots-auth.txt`
   als `robots.txt` abgelegt werden (dort ist die Sperre dann schon
   drin, die Host-Bedingungen in der `.htaccess` schaden aber nicht).

## Nach dem Upload pruefen

```powershell
python tool/check_websites_live.py --host https://thestia.de
python tool/check_passkey_assetlinks.py --live
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
python tool/update_assetlinks.py           # Kette live lesen, Datei schreiben
python tool/check_passkey_assetlinks.py --live
```

und den Publish-Ordner noch einmal hochladen.

## Fuer die Web-Version der App (v0.12.0)

Die Web-App kommt in ein **eigenes** Verzeichnis (nicht in das der
Website) - sie ist eine eigene Anwendung mit eigenem Build. In ihrer
`.htaccess` kommt der SPA-Fallback dazu (unbekannte Adressen liefern
`index.html`); die Zeile steht schon als Kommentar am Ende der
erzeugten Datei.
