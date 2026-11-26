# Der eigene TURN-Server (Coturn) – Anleitung für den Betreiber

Stand: 16.11.2026. Betreiber-Anleitung, kein Konzeptpapier.

## Worum es geht

**Kurzfassung:** Thestia hat heute **keinen** TURN-Relay-Server und
**keinen** eigenen STUN-Server. Beim Aufbau der Direktverbindung zwischen
zwei Geräten fragt die App die öffentliche IP-Adresse bei **vier
öffentlichen STUN-Servern** ab (nextcloud/Hetzner, miwifi/OVH, voipgate,
voipstunt). Diese Betreiber sehen dabei deine IP-Adresse – mehr nicht.
Inhaltlich kommen sie nie an den Nachrichtentext (Signal-Protokoll).

Mit einem **eigenen** Coturn-Server fällt diese Offenlegung weg: Die
IP-Adresse sieht dann nur noch der Betreiber, der den Server betreibt –
nämlich du. Zusätzlich funktionieren Anrufe und Chats auch dann, wenn
zwei Geräte hinter sehr restriktiven Netzen keine direkte Verbindung
zustande bringen (das ist der eigentliche Zweck von TURN).

**Was sich für den Nutzer ändert:** nichts an der Ende-zu-Ende-
Verschlüsselung. Der Inhalt bleibt Chiffrat. Der Unterschied ist der
Betrachter der Metadaten.

## Was bereits im Code fertig ist

| Baustein | Datei | Status |
|---|---|---|
| TURN-Credentials (kurzlebige HMAC-Credentials nach dem coturn-REST-Verfahren) | `supabase/functions/ice-config/index.ts` | fertig – **aktiv, sobald die zwei Secrets gesetzt sind** |
| Ablauf der Credentials (55 Minuten), Cache-Frist im Client | `lib/services/chat/webrtc_service.dart` (`effectiveTtl`) | fertig |
| Abschaltbare öffentliche STUN-Server | `lib/services/chat/webrtc_service.dart` (`_fallbackIceServers`) | fertig – über `ICE_FALLBACK_URLS` im Build |
| Auftragsverarbeiter-Liste (STUN ist jetzt genannt, TURN ist entfernt) | `lib/screens/privacy/privacy_screen.dart`, `lib/l10n/app_strings.dart` | fertig |
| Datenschutzerklärung (kein TURN, STUN-Betreiber) | `docs/recht/DATENSCHUTZ.md` | fertig |

**Es ist also kein App-Code mehr nötig** – es fehlen nur der Server und
die zwei Secrets.

## Teil 1: Der Server

### Was du brauchst

* Ein kleiner VPS mit **öffentlichem UDP 3478** (und optional TCP 3478
  sowie TLS auf 443). Hetzner Cloud (CX22, ~4 €/Monat) reicht völlig.
* Docker + Docker Compose.
* Eine **Subdomain** mit A-Record auf den Server, z. B.
  `turn.thestia.de` (nur A-Record nötig – kein CNAME, kein Proxy).

> **Rechtlicher Hinweis:** Ein TURN-Server ist ein
> **Auftragsverarbeiter** im Sinne Art. 28 DSGVO – er verarbeitet die
> IP-Adressen der Nutzer. Auch bei einem eigenen Server brauchst du also
> einen Vertrag mit dir selbst als Auftragsverarbeiter (bei
> Einzelunternehmen genügt die Erfüllung der Dokumentationspflichten,
> Art. 28 Abs. 2 und 3). Der Eintrag in der Auftragsverarbeiter-Liste
> der App wird von „Nextcloud, OVH, VoIPGate, VoIPStunt" auf
> „Thestia (eigener Server)" geändert.

### `docker-compose.yml`

```yaml
# coturn: der Relay-Server fuer die Direktverbindung.
#
# WICHTIG: "external-ip" muss die OEFFENTLICHE IP des Servers sein.
# Ohne sie sieht der Client eine private Adresse und der Aufbau
# scheitert hinter NAT.
services:
  coturn:
    image: coturn/coturn:latest
    container_name: thestia-turn
    restart: unless-stopped
    # 3478/udp = STUN und TURN (UDP)
    # 3478/tcp = TURN (TCP) - als Ausweichweg, wenn UDP blockiert ist
    # 5349/tcp = TURN ueber TLS (optional, siehe unten)
    ports:
      - "3478:3478/udp"
      - "3478:3478/tcp"
      - "5349:5349/tcp"
    volumes:
      - ./turnserver.conf:/etc/coturn/turnserver.conf:ro
    # Das Geheimnis kommt aus der Umgebung, NICHT aus der Datei:
    # so steht es in keinem Image und in keinem Backup der Datei.
    environment:
      - TURN_SECRET=${TURN_SECRET:?bitte TURN_SECRET in der .env setzen}
```

### `turnserver.conf`

```ini
# Coturn-Konfiguration fuer Thestia.
#
# Pflichtangaben (siehe turnserver.md im coturn-Image):
#   lt-cred-mech, realm, use-auth-secret, static-auth-secret,
#   cert und pkey (TLS) - ohne die letzten beiden laeuft der
#   Server nur ueber UDP/TCP, nicht ueber TLS.

listening-port=3478
tls-listening-port=5349

# NUR die oeffentliche Adresse dieses Servers. Mit einem Eintrag
# versteht coturn, welche Adresse er nach aussen meldet.
external-ip=<DIE-OEFFENTLICHE-IP-DES-SERVERS>

# Der Bereich der Ports, ueber die der Relay laeuft. Jeder Port
# wird pro Sitzung belegt - das ist der Grund fuer die Auswahl.
min-port=49160
max-port=49200

# Der Realm: der Benutzername, den die App mitsendet.
realm=thestia.de

# REST-API-Verfahren: die Credentials werden nach dem Muster
# "<Ablaufzeit>:<Kennung>" erzeugt und mit HMAC-SHA1 signiert.
# Genau das macht die Edge Function ice-config (siehe dort
# _turnCredential). Nur damit passen die Credentials.
use-auth-secret
static-auth-secret=${TURN_SECRET}

# TLS (optional, aber empfohlen: dann laeuft der Datenverkehr
# des Relays verschluesselt - der Betreiber sieht dann nicht einmal
# die Videodaten, nur die Paketgroessen).
cert=/etc/coturn/certs/turn.crt
pkey=/etc/coturn/certs/turn.key

# Nur die Adressen, die der Server als Relay benutzen darf.
# Ohne das könnte jemand den Server als offenes Relay missbrauchen.
# Die IPs der Supabase-Server (Datenbank) sind hier NICHT gemeint -
# gemeint sind die Geraete der Nutzer, also: alles ausser
# reservierten Bereichen.
no-multicast-peers
no-cli
no-tlsv1
no-tlsv1_1
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
```

> **Hinweis zu `static-auth-secret`:** Coturn ersetzt `${TURN_SECRET}`
> in der Konfigurationsdatei aus der Umgebung des Containers. Damit steht
> das Geheimnis **nicht** in `turnserver.conf` und damit in keinem
> Git-Repository und in keinem Kopien-Backup der Datei.

### Zertifikat für TLS

```bash
# Auf dem Server (mit Certbot oder dns-01):
sudo certbot certonly --standalone -d turn.thestia.de
sudo mkdir -p /opt/thestia-turn/certs
sudo cp /etc/letsencrypt/live/turn.thestia.de/fullchain.pem /opt/thestia-turn/certs/turn.crt
sudo cp /etc/letsencrypt/live/turn.thestia.de/privkey.pem /opt/thestia-turn/certs/turn.key
sudo chmod 600 /opt/thestia-turn/certs/turn.key
```

### `.env` auf dem Server

```bash
# neben der docker-compose.yml
TURN_SECRET=<ein zufaelliges Geheimnis, mindestens 32 Zeichen>
# Erzeugen z. B. mit: openssl rand -base64 48
```

### Starten und prüfen

```bash
cd /opt/thestia-turn
docker compose up -d
docker compose logs -f coturn
```

Test von einem beliebigen Rechner:

```bash
# STUN-Test (ohne TURN) - sollte die oeffentliche IP zurueckgeben:
turnutils_stunclient turn.thestia.de -p 3478
```

## Teil 2: Die zwei Secrets in Supabase

```powershell
# IM PROJEKTVERZEICHNIS (der Supabase-CLI ist im Projekt eingerichtet):
supabase secrets set TURN_SHARED_SECRET="<DAS GEHEIMNIS>" `
                     TURN_URLS="turn:turn.thestia.de:3478?transport=udp,turn:turn.thestia.de:3478?transport=tcp"

# Danach die Edge Function neu deployen (die Secrets werden beim
# Start der Function gelesen):
supabase functions deploy ice-config
```

**Prüfen, ob es angekommen ist:**

```powershell
# Ohne JWT antwortet die Function mit 401 - das beweist nur, dass sie
# läuft. Die ICE-Liste selbst ist nur mit Sitzung abrufbar.
curl.exe -X POST "https://jftuigjbmmuvrckbchqo.supabase.co/functions/v1/ice-config" `
  -H "Authorization: Bearer <JWT>" -H "Content-Type: application/json" -d "{}"
```

Erwartet: eine Liste mit `stun:`-Einträgen **und** einem `turn:`-Eintrag,
der `username` und `credential` trägt.

> **Ohne die Secrets bleibt alles wie bisher** (nur STUN). Die Function
> läuft dann ohne TURN weiter – kein Fehler, kein Ausfall.

## Teil 3: Die öffentlichen STUN-Server abschalten

Sind die eigenen TURN-Credentials aktiv, sollen die vier fremden STUN-
Server **nicht mehr angefragt werden** (sonst sehen sie die IP weiterhin).
Das steuert ein Build-Wert:

```bash
# In der .env des Projekts (lokale .env, wird NICHT eingecheckt):
ICE_FALLBACK_URLS=
```

Der Wert ist eine Komma-Liste. **Leer = keine öffentlichen STUN-Server im
Rückfall.** Die Liste greift nur, wenn die Edge Function `ice-config`
nicht erreichbar ist (ohne Netz, Ausfall der Supabase-Instanz).

> **Der Build-Wert wirkt erst nach einem neuen Release.** Zwischen
> `supabase secrets set` und dem neuen Release laufen beide Wege
> parallel (die eigenen TURN-Credentials UND die öffentlichen STUN-
> Server). Das ist unkritisch – die öffentlichen STUN-Server sehen dann
> nur die IP, die auch sonst sichtbar ist.

Der Wert muss im Release-Skript durchgereicht werden. Das ist bereits
vorbereitet: `tool/release/build_release.ps1` liest die erlaubten Schlüssel aus
der `.env` – dort ist `ICE_FALLBACK_URLS` als **einer** der
durchgereichten Werte eingetragen (die Liste der erlaubten Schlüssel
steht in `tool/release/build_release.ps1`).

## Teil 4: Die Datenschutzerklärung anpassen

Sind die eigenen TURN-Credentials aktiv, ändert sich an zwei Stellen
etwas:

1. **Abschnitt 6 (Auftragsverarbeiter):** Die Zeile
   „STUN-Server (nextcloud/Hetzner, miwifi/OVH, voipgate, voipstunt)" wird
   ersetzt durch den eigenen Server (Beispiel):
   > | Thestia (eigener TURN-Server, turn.thestia.de) | Deine IP-Adresse |
   >   Relay für die Direktverbindung, wenn sie nicht zustande kommt; der
   >   Inhalt bleibt Ende-zu-Ende verschlüsselt | Global |
2. **Abschnitt 3 (Ende-zu-Ende-Verschlüsselung):** Der Absatz
   „Es gibt derzeit keinen TURN-Relay-Server" wird angepasst.

Danach:

```powershell
# Die Erklaerung neu erzeugen (Quelltext: docs/recht/DATENSCHUTZ.md):
python tool\make_privacy_policy.py
# Und die beiden Gates:
python tool\check_umlauts.py
python tool\check_web_pages.py
```

Zusätzlich in der **App** (Auftragsverarbeiter-Liste in
`lib/screens/privacy/privacy_screen.dart` und `lib/l10n/app_strings.dart`):
der Eintrag `privacy.processorStun` wird auf den eigenen Server geändert
und `privacy.noTurnTitle`/`privacy.noTurnSub` entfallen.

## Teil 5: Der Test auf dem Gerät

1. Zwei Geräte, beide mit dem neuen Release.
2. In einem Chat eine Sprachnachricht schicken und den anderenTon abspielen.
3. **Auf dem Server prüfen, ob überhaupt Daten über den Relay laufen:**

   ```bash
   docker compose logs -f coturn | grep -i "session"
   ```

   Ohne TURN im Spiel (Gleiches WLAN oder offenes Netz) darf dort nichts
   kommen – die Verbindung entsteht direkt.
4. Gegenprobe „fremder STUN": Im Log des eigenen Coturn darf nichts
   stehen, was auf die vier öffentlichen Server hindeutet. Der
   öffentliche STUN-Aufruf kommt aus dem Gerät, nicht vom Server – die
   Gegenprobe ist: In den **App-Logs** (Logcat) darf kein
   `stun.nextcloud.com` o. Ä. mehr auftauchen.

## Was das kostet

| | |
|---|---|
| Server | ca. 4 €/Monat (Hetzner CX22) – oder 0 €, wenn du einen ohnehin hast |
| Datentransfer | nur, wenn der Relay tatsächlich genutzt wird (also selten) |
| Aufwand | ~1 Stunde für Server + Zertifikat, danach die zwei Secrets |
| Risiko | gering – ohne die Secrets bleibt alles unverändert |
