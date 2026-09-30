# Signier-Key und Updates

Kurzfassung: **v0.9.2 lässt sich nicht über eine installierte v0.9.0/0.9.1
aktualisieren.** Die App muss vorher deinstalliert werden. Grund ist der
Keywechsel vom 27.09.2026 – nicht Android, nicht ein Fehler im Build.

## Warum

Android erlaubt ein Update nur, wenn die neue APK mit **demselben
Zertifikat** signiert ist wie die installierte. Sonst bricht die
Installation mit `INSTALL_FAILED_UPDATE_INCOMPATIBLE` ab. Prüft wird
der SHA-256-Fingerabdruck des Signier-Zertifikats, nicht der Name.

Beim Release-Keywechsel (Commit `67524c7`) wurde das Zertifikat
getauscht:

| Version | Zertifikat-DN | SHA-256 (Anfang) |
| --- | --- | --- |
| v0.9.0, v0.9.1 | `CN=WispDating, O=WispDating` | `37AA4F6CC1DEB8F5…` |
| v0.9.2 und später | `CN=Thestia, OU=Unknown, O=Thestia` | `8CBEF7D08F866654…` |

Ein X.509-Zertifikat lässt sich nicht umschreiben: der Distinguished
Name liegt im signierten Teil, jedes geänderte Zeichen bricht die
Signatur. Ein Namenswechsel erfordert zwingend ein neues Zertifikat und
damit eine neue Signaturidentität.

Der Zeitpunkt war Absicht: die App war an keinem Store veröffentlicht,
also kostete der Wechsel nur einen Neubau. **Ab dem ersten Store-Upload
wäre er nur noch über einen Play-Key-Reset möglich gewesen**, und ein
Key-Reset löscht alle installierten Kopien der App.

## Was auf dem Gerät passiert

1. Update über v0.9.1: Play Store oder Sideload lehnt ab
   (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Angezeigt wird das als
   fehlgeschlagenes Update.
2. Danach erscheint oft „Die App konnte nicht gestartet werden. Bitte
   schließe die App komplett und versuche es erneut." Das ist **nicht
   der eigentliche Fehler**, sondern der Folgezustand: die alte App
   hängt nach dem abgebrochenen Update fest. Sie lässt sich nicht
   starten, weil die Installation nicht sauber abgeschlossen wurde.
3. Nachvollziehen lässt sich das so:

   ```powershell
   adb shell pm list packages | findstr thestia
   # App muss deinstalliert sein, bevor die neue installiert wird:
   adb uninstall com.thestia.app
   ```

## Was beim Deinstallieren verloren geht

- **Lokale Daten**: Secure-Storage, Einstellungen, Chat-Entwürfe im
  lokalen Cache. Das Konto selbst liegt in Supabase und bleibt
  erhalten – Anmeldung funktioniert danach wieder.
- **Passkeys**: Android löscht Passkeys beim Deinstallieren, weil sie
  an den App-AndroidKeystore gebunden sind. Nach der Neuinstallation
  muss ein Passkey neu registriert werden. Das ist der teuerste Punkt
  und der Grund, warum ein Keywechsel nach dem ersten Upload teuer ist.
- **Biometrisch gebundene Anmeldung** (Fingerprint/Face): die
  Anmeldung ist danach wieder möglich, das Gerät ist aber neu zu
  bestätigen.

## Ab jetzt

Der Key `C:\Users\Thoralf\thestia-upload.keystore` ist ab sofort der
einzige gültige. Regeln:

1. **Passwort sofort sichern.** Nicht im Repository, nicht in
   `key.properties` im Git. In einen Passwortmanager und offline
   ablegen. Der alte `wisp-upload.keystore` liegt zwar noch auf der
   Platte, aber ohne Passwort ist er wertlos – er wurde bereits
   unwiederbringlich unbrauchbar gemacht.
2. **Keine further Keystore-Änderung** ohne Play-Key-Reset.
3. `android/key.properties` ist gitignoriert. Prüfen, dass dort der
   Pfad auf `thestia-upload.keystore` zeigt, nicht auf die alte Datei.
4. Bei einer künftigen Signatur-Abweichung gilt: erst Fingerabdruck
   vergleichen, dann Android-Version, dann Build. Die Reihenfolge
   spart Fehlersuche – der Keywechsel ist deutlich häufiger als ein
   Android-spezifischer Startfehler.

## Prüfkommando

Fingerabdruck der ausgelieferten APK:

```powershell
$bt = (Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory |
       Sort-Object Name -Descending | Select-Object -First 1).FullName
& (Join-Path $bt "apksigner.bat") verify --print-certs `
    releases\v0.9.2\Thestia-v0.9.2-play.apk |
  Select-String "certificate DN|SHA-256"
```

Erwartet: `CN=Thestia` und `8CBEF7D08F866654…`.
