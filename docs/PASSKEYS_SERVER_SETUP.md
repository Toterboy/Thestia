# Passkeys: Server-Konfiguration (GoTrue / Supabase)

Symptom, das diese Datei behandelt:

> Beim „Passkey erstellen" läuft der native Android-Dialog durch (Credential
> wird auf dem Gerät angelegt), aber die App zeigt danach
> **„Der Server konnte den Passkey nicht bestätigen"** – GoTrue meldet
> `credential verification failed`.

## Ursache (mit hoher Wahrscheinlichkeit)

GoTrue prüft bei der Registrierung, ob der **Origin** aus der
`clientDataJSON` in der konfigurierten Ursprungs-Liste steht. Auf Android
ist dieser Origin **keine URL**, sondern die Signatur des APKs:

```
android:apk-key-hash:<base64url(SHA-256 des Signaturzertifikats)>
```

Fehlt der Origin des installierten APKs in der Konfiguration, schlägt die
Verifikation IMMER fehl – während der native Dialog trotzdem funktioniert,
denn der prüft nur die `assetlinks.json` auf der RP-Domain (dort stehen bei
Thestia beide Keys drin).

## Die Origins von Thestia

> **Signierer-DN auf `CN=Thestia` umgestellt (Release-Keywechsel).**
> Das alte Release-Zertifikat trug `CN=WispDating`. Ein Zertifikat lässt
> sich nicht umbenennen – der DN liegt im signierten Teil, jede Änderung
> entwertet die Signatur. Weil Thestia zum Zeitpunkt des Wechsels an noch
> keinem Store veröffentlicht war, konnte der Key ohne Key-Rotation
> getauscht werden; ein Rollback wäre jetzt nur noch über den
> Play-Key-Reset möglich.
>
> **Folge:** Fingerabdruck **und** `apk-key-hash`-Origin des
> Release-Keys haben sich geändert. Der alte Eintrag
> `…CZr3S7HvpVXI` muss aus `assetlinks.json` **und** aus der
> Origin-Liste **ersetzt** (nicht ergänzt) werden – sonst laufen
> Release-Builds in `credential verification failed`.
>
> Der alte Keystore `wisp-upload.keystore` bleibt als Datei erhalten,
> wird aber nicht mehr verwendet. Sein Passwort ist mit dem Umschreiben
> von `android/key.properties` verloren, er ist also nur noch als
> Fingerabdruck-Dokumentation nützlich, nicht zum Signieren.
>
> **Achtung Firebase/Google-API-Key:** Ist der API-Key des Projekts
> `thestia-c6855` per Android-App-Signatur eingeschränkt, muss dort der
> **neue** SHA-1 stehen, sonst lehnt Google die Anfragen des
> Release-Builds ab:
> `94:15:FC:F0:04:89:CC:82:0C:AD:D1:AD:2C:6D:EB:4C:63:0E:D0:76`
> (Paketname `com.thestia.app`).
>
> **Achtung Bestand:** Bestehende Passkeys sind an die alte RP-ID
> gebunden und nach der Migration ungültig – Nutzer müssen sie neu
> registrieren (2FA/TOTP oder E-Mail-Login bleibt als Fallback). Da noch
> keine Nutzer existieren, ist das bisher nie aufgefallen.

Berechnet aus dem **tatsächlichen Signatur-Keystore**
(`thestia-upload.keystore`, SHA-256 via keytool verifiziert):

| Schlüssel | SHA-256 | Origin (exakt so übernehmen) |
|---|---|---|
| **Upload-/Release-Key** | 8CBEF7…3E1A | android:apk-key-hash:jL730I-GZlQuHVO5tCbFRq-CR5Ma3-ggYZ4X95E_Pho |
| **Debug-Key** (nur lokal) | 5AB8D0…A979 | android:apk-key-hash:WrjQ1eUdTGnHEeMSAqhA6tqoMFqd6yOINSrNwVwwqXk |
| iOS/Web (Associated Domain) | – | `https://auth.thestia.de` |
| Web-App (falls auf Root-Domain) | – | `https://thestia.de` |

Der **Debug-Key-Hash** steht in der Tabelle, weil `assetlinks.json` ihn
braucht (siehe `passkey-assets/ASSETLINKS_ROOTDOMAIN.md`) — ohne ihn
schlägt die native Prüfung in jedem Debug-Build fehl. Für die
**serverseitige Origin-Liste** ist das eine andere Frage, siehe unten.

### ⚠️ Konkreter Fehlerfall (Stand 05.09.2026 behoben)

Im Dashboard standen die **SHA-1**-Fingerprints (nur 20 Byte) der Keys –
`android:apk-key-hash` verlangt zwingend **SHA-256** (43
Base64URL-Zeichen, 32 Byte). Damit war der Abgleich nie erfolgreich →
`credential verification failed`. **Richtig (Dashboard-Eintrag komplett
ersetzen, Produktions-Umfang):**

```
https://auth.thestia.de,android:apk-key-hash:jL730I-GZlQuHVO5tCbFRq-CR5Ma3-ggYZ4X95E_Pho
```

**Vor dem ersten Veröffentlichen noch zu entscheiden: Debug-Origin.**
Solange gegen dasselbe Supabase-Projekt entwickelt wird, ist der
Debug-Origin erforderlich, damit `flutter run` überhaupt einen Passkey
registrieren kann. Er gehört damit in eine **Entwicklungs-Konfiguration,
nicht in die Produktionsliste** – und zwar aus einem konkreten Grund:

Der Android-Debug-Keystore ist der Standard-Key aus Android Studio mit dem
Passwort `android`, also praktisch allgemein bekannt. Steht sein Hash in
`RP_ORIGINS`, besteht jeder beliebige selbst signierte Build die
Origin-Prüfung von GoTrue. Zusammen mit einer erlangten Session (z. B.
über einen Phishing-Proxy im OAuth-Code-Flow) kann ein Angreifer damit
einen eigenen Authenticator als Passkey auf dem fremden Konto
registrieren. Die Registrierung ersetzt keine Anmeldung, aber sie
entzieht dem Konto den Passkey-Schutz.

Empfohlene Aufteilung:

| Umgebung | Origins |
|---|---|
| **Produktion** (Supabase, thestia.de) | `https://auth.thestia.de` + Release-Key-Hash + (nach Upload) Play-Key-Hash |
| **Lokal** (eigenes Supabase-Projekt oder self-hosted) | zusätzlich der Debug-Key-Hash |

Wenn es kein separates Entwicklungsprojekt geben soll: Debug-Origin
während der Entwicklung setzen und **vor dem ersten Upload entfernen**.
Kontrolle: `python tool/check_passkey_assetlinks.py --live`

**Play-Store-Verteilung:** Von Play installierte Builds tragen den separaten Play-App-Signing-Key – dessen Hash (Play Console → Setup → App-Integrität) als **dritten** Origin ergänzen. Der ist erst vorhanden, wenn der App-Signing-Key existiert, und Play erzeugt ihn erst beim ersten Upload; er ist also bis dahin nicht eintragbar.

**Achtung:** Wer ein APK mit einem NEUEN Keystore signiert (z. B. neuer
Upload-Key nach Play-Key-Rotation), braucht einen ZUSÄTZLICHEN Origin mit
dem neuen Hash – der native Dialog zeigt den Fehler nicht an! SHA-1- und
SHA-256-Fingerprints sind NICHT austauschbar.

## 🔐 Sicherheitseinordnung: Sind Fingerprints geheim?

**Nein** – und das ist wichtig zu wissen:

- Ein Zertifikats-Fingerprint (SHA-1/SHA-256) ist ein **öffentlicher
  Ableitungswert**: Er steckt in jedem verteilten APK, wird von Google
  Play öffentlich angezeigt und steht ohnehin in der öffentlich
  abrufbaren `https://auth.thestia.de/.well-known/assetlinks.json`
  (dort ist er FUNKTIONAL ERFORDERLICH – ohne ihn verweigert Android den
  Passkey-Dialog).
- Das eigentliche Geheimnis ist der **Keystore selbst samt Passwort**
  (`thestia-upload.keystore`, `android/key.properties`) – beides ist via
  `.gitignore` (`*.keystore`, `android/key.properties`, `*.jks`,
  `*.p12`/`*.pfx`/`*.pem`/`*.key`) ausgeschlossen und war NIE Teil des
  Repositorys (geprüft via `git ls-files`). Dasselbe gilt für den
  Vorgänger-Key `wisp-upload.keystore`.
- Der Debug-Key-Fingerprint ist maschinenspezifisch und nur für lokale
  `flutter run`-Tests relevant; sein Origin gehört deshalb bewusst NICHT
  in diese öffentliche Anleitung und sollte nach lokalem Testen aus der
  Server-Liste entfernt werden, ohne die Release-App zu beeinträchtigen.

Die Fingerprints in `passkey-assets/assetlinks.json` und diesem Dokument
sind demnach **kein Sicherheitsrisiko** und bleiben absichtlich im Repo.

## Konfiguration setzen

GoTrue (Quelle: `internal/conf/configuration.go`) verlangt bei aktivem
WebAuthn/Passkeys zwingend:

| Env/Setting | Wert für Thestia |
|---|---|
| `GOTRUE_WEBAUTHN_RP_ID` | `auth.thestia.de` |
| `GOTRUE_WEBAUTHN_RP_DISPLAY_NAME` | z. B. `Thestia` |
| `GOTRUE_WEBAUTHN_RP_ORIGINS` | kommaseparierte Liste – MUSS den `android:apk-key-hash:`-Origin des Release-Keys, `https://auth.thestia.de` und ggf. `https://thestia.de` enthalten (Debug-Hash nur lokal, nicht in Produktion) |

**Supabase (Hosted):** Dashboard → **Authentication → Sign In / Providers →
Passkeys (Beta)** → dort **RP ID**, **Display Name** und **Origins** pflegen.
Nach dem Speichern sofort wirksam (kein Redeploy nötig).

**Self-Hosted:** die drei `GOTRUE_WEBAUTHN_*`-Variablen setzen und den
Auth-Dienst neu starten.

## Verifikation (was sendet das Gerät wirklich?)

1. Debug-Build installieren (`flutter run --flavor play`).
2. „Passkey erstellen" antippen.
3. Logcat/Console zeigt jetzt:
   ```
   [Passkey] clientDataJSON: type=webauthn.create origin=android:apk-key-hash:XXXX
   ```
4. Dieser exakte Origin-String muss 1:1 in `RP_ORIGINS` stehen.

Neue Keystore-Fingerprint → Origin-String selbst berechnen:

```bash
keytool -list -v -keystore <keystore> | grep "SHA256:"
# Hex (ohne Doppelpunkte) → bytes → base64url ohne Padding:
python -c "import base64;print('android:apk-key-hash:'+base64.urlsafe_b64encode(bytes.fromhex('HEXOHNEDD')).decode().rstrip('='))"
```

## Weitere Prüfpunkte (falls Origins korrekt sind)

| Symptom | Ursache | Lösung |
|---|---|---|
| `credential verification failed` bei JEDER Registrierung | Origin fehlt (siehe oben) | Origins ergänzen |
| `credential verification failed` nur manchmal | Challenge abgelaufen/doppelt gestartet | Einmal sauber wiederholen |
| `aal2 required` / 403 | 2FA aktiv, Session nur AAL1 | 2FA-Bestätigung im Flow (automatisch) |
| `User enrollments disabled` | Passkeys im Dashboard nicht aktiviert | Dashboard → Passkeys aktivieren |
| Native Dialog lehnt ab (`SecurityError`) | assetlinks.json passt nicht | Hash in `auth.thestia.de/.well-known/assetlinks.json` ergänzen |
| Passkey in Google-Passwortmanager sichtbar, aber Login schlägt fehl | Credential auf Gerät, nie serverseitig registriert (Verifikation schlug fehl) | Eintrag im Passwortmanager löschen; nach Origin-Fix neu anlegen |

## Warum der Client kein AAL2 erzwingen kann (v0.9.3)

Bei der Durchsicht kam die Frage auf, ob die Passkey-Registrierung im
Client auf AAL2 gehärtet werden müsste — also ob man `userVerification:
required` und `authenticatorAttachment: platform` selbst setzen kann.

**Nein, und der Grund ist nicht nachvollziehbar-lösbar auf der
Client-Seite.** Der Request an das Gerät entsteht aus den Optionen, die
der Server schickt:

```dart
// supabase_flutter/lib/src/supabase_passkey.dart
final registration = await passkey.startRegistration();
final response = await authenticator.register(
  passkeyRegisterRequestFromOptions(registration.options),
);
```

`RegisterRequestType` (passkeys_platform_interface) hat **kein** Feld für
`userVerification` oder `authenticatorAttachment`. Der Client kann die
Anforderung also nicht verschärfen, nur abschwächen — und das wäre ohne
Nutzen, weil GoTrue die Ceremonie abschließend prüft.

AAL2 kommt damit wie in der Tabelle oben beschrieben über die 2FA des
Accounts. Wer AAL2 erzwingen will, muss die betroffene Aktion auf einen
AAL2-geprüften RPC legen (`aal2` im Funktionsnamen oder
`auth.jwt()->>'aal'` prüfen) — nicht auf die Registrierung selbst.

Als Client-seitiges Gegenstück gibt es seit v0.9.3
`PasskeyAuth.hasRegisteredPasskey()`: die Einrichtung prüft vor der
Registrierung, ob bereits ein Passkey auf dem Konto liegt. Vorher lief
sie blind und bekam auf einem Gerät mit vorhandenem Passkey einen zweiten
nativen Dialog mit anschließender Fehlermeldung — die Meldung war falsch,
es war nichts kaputt. Der Check fängt Fehler beim Lesen der Liste als
„unbekannt" auf: Verlangt das Lesen selbst AAL2, darf die Einrichtung
deshalb **nicht** abbrechen.
