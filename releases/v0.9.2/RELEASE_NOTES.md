# Thestia v0.9.2 - Release Notes

Build 30. Veroeffentlicht noch nicht - dieses Dokument beschreibt den
Stand, der mit `tool/build_release.ps1` gebaut wird.

## operator: Vor dem Hochladen

1. `supabase db push` (Migrationen 123-130)
2. `supabase functions deploy` fuer `verify-account`,
   `cancel-registration`, `request-unban`, `send-bug-report`, `prekeys`,
   `delete-account`, `report-image`, `match-media`
3. Store-Changelogs: `fastlane/metadata/android/{de-DE,en-US}/changelogs/30.txt`
   (liegen im Repo)
4. APK bauen: `tool/build_release.ps1` (bricht bewusst ab, wenn
   `SUPABASE_URL` oder `CAPTCHA_SITEKEY` fehlen)

### Signatur: neues Release-Zertifikat (CN=Thestia)

Das Release-Zertifikat trug vorher `CN=WispDating` und wurde durch
`CN=Thestia` ersetzt. Ein Zertifikat laesst sich nicht umbenennen, und da
Thestia noch nirgends veroeffentlicht war, war das der einzige Moment fuer
einen Key-Wechsel ohne Play-Key-Reset. Sonst waere der alte Key
unangetastet geblieben.

| | Wert |
|---|---|
| Keystore | `C:/Users/Thoralf/thestia-upload.keystore` (Alias `upload`) |
| Signierer-DN | `CN=Thestia, OU=Unknown, O=Thestia, L=Unknown, ST=DE, C=DE` |
| SHA-256 | `8C:BE:F7:D0:8F:86:66:54:2E:1D:53:B9:B4:26:C5:46:AF:82:47:93:1A:DF:E8:20:61:9E:17:F7:91:3F:3E:1A` |
| SHA-1 | `94:15:FC:F0:04:89:CC:82:0C:AD:D1:AD:2C:6D:EB:4C:63:0E:D0:76` |
| `apk-key-hash` | `android:apk-key-hash:jL730I-GZlQuHVO5tCbFRq-CR5Ma3-ggYZ4X95E_Pho` |

Die zehn Artefakte in diesem Verzeichnis sind alle mit diesem Zertifikat
neu gebaut und einzeln geprueft (`apksigner`: `Verifies`, Scheme v2,
Fingerabdruck identisch). Der alte Fingerabdruck kommt in keinem davon vor.

**Drei Stellen von Hand nachziehen, sonst geht etwas schief:**

1. **Supabase-Dashboard** → Authentication → Passkeys → Origins auf
   `https://auth.thestia.de,android:apk-key-hash:jL730I-GZlQuHVO5tCbFRq-CR5Ma3-ggYZ4X95E_Pho`
   umstellen. Der alte Origin muss **ersetzt** werden, nicht ergaenzt.
2. **Firebase-API-Key** des Projekts `thestia-c6855`: falls er per
   Android-App-Signatur eingeschraenkt ist, dort den neuen SHA-1 eintragen
   (Paket `com.thestia.app`). Sonst weist Google die Anfragen des
   Release-Builds zurueck. Der vorige Wert `78:20:59:86:...` gehoert
   raus.
3. **`assetlinks.json`** ist im Repo bereits aktualisiert, muss aber noch
   auf thestia.de deployed werden. Ohne das schlaegt die native
   Passkey-Pruefung im Release-Build fehl.

Nach dem **ersten** Play-Upload kommt ein vierter Punkt: den
App-Signing-Fingerprint von Play (Play Console → Setup → App Signing) in
`assetlinks.json` und als Origin in Supabase ergaenzen. Von Play
installierte Builds tragen den Play-Key, nicht den Upload-Key.

## Fuer Nutzer sichtbar

- **Rotierende Vorstellungs-Prompts**: 4 Themen mit je drei offenen
  Fragen. Wer die App oft oeffnet, tippt nicht mehr dieselben vier
  Fragen an
- **E-Mail-Bestaetigung ist jetzt Pflicht** fuer Funken, Daumen und
  Nachrichten. Wer seine Adresse nicht bestaetigt hat, sieht einen
  Hinweis und kann das in den Einstellungen nachholen
- **Sicherheitsnummer im Chat erzwingbar**: unter "Sicherheit" im Chat
  laesst sich festlegen, dass erst nach dem Vergleich der Nummern
  gesendet wird
- **Naehefunk sendet unregelmaessig** statt im festen Takt und hoert nur
  noch Thestia-Signale (vorher jedes Bluetooth-Signal in der Umgebung)
- **Standortdaten werden nach 30 Tagen automatisch geloescht**
- **Weniger unerwartete Profile**: Distanz, Alter, Pause und
  Reziprozitaet werden jetzt serverseitig in einer gemeinsamen Regel
  geprueft

## Sicherheit

Der groesste Teil dieser Arbeit ist unsichtbar. Siehe
[CHANGELOG.md](../../CHANGELOG.md) fuer die vollstaendige Liste.

Die drei Punkte, die man dem Nutzer communication-schaerf erlaeslichen
muss:

1. **Antwortschluessel-Exploit geschlossen.** `quiz_shuffle_for_match`
   war fuer die Rolle `anon` aufrufbar; ueber 24 Permutationen liess sich
   der korrekte Quiz-Antwortindex ermitteln und damit der
   AES-Schluessel scharfer Profilfotos. Ursache war kein fehlendes
   `REVOKE`, sondern ein unvollstaendiges: Rechte werden ueber die
   Pseudo-Rolle `PUBLIC` vererbt, ein `REVOKE ... FROM anon` greift
   darum nicht.
2. **Jugendschutz und Blockier-Pruefung** fuer Zufallschat und Dating
   Hour waren durch spaetere Migrationen verloren gegangen. Wieder da,
   diesmal zusätzlich als Tabellen-Trigger.
3. **Rate-Limits und MFA-Pruefungen** waren bei Fehlern *offen* statt
   *geschlossen* - ein Datenbankfehler umging sie vollstaendig.

## Wichtig fuer den Betrieb

- **Migration 130 setzt `min_app_version_build = 29`.** Das war in den
  0.9.1-Release-Notes angekuendigt, aber nie ausgefuehrt worden
  (Migration 076 legte 9 fest). 0.9.1 bleibt unterstuetzt, aeltere
  Builds werden zum Update gezeigt.
- **BLE-Geraetetest steht aus** (siehe
  [docs/BLE-GERAETEST.md](../../docs/BLE-GERAETETEST.md)). Ohne zwei
  echte Geraete verschiedener Hersteller gilt Transit Spark laut
  ROADMAP als **nicht stabil** und darf nicht als stabil beworben
  werden. Drei Kriterien, je beide Richtungen.

## Unterstuetzte Versionen

**v0.9.1 (Build 29) und hoeher** werden unterstuetzt
(`app_config.min_app_version_build = 29`, Migration 130).

## Dateien

- App-Name: **Thestia**
- Paketname: `com.thestia.app`
- Supabase-Projekt: siehe `supabase/config.toml`
- Store-Changelogs: `fastlane/metadata/android/*/changelogs/30.txt`
