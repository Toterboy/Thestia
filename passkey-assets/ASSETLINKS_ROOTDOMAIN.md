# App Links für thestia.de (Passwort-Reset sicher stellen)

Damit Android die HTTPS-App-Links verifiziert, muss unter

```
https://thestia.de/.well-known/assetlinks.json
```

(Content-Type `application/json`, ohne Redirect auf HTML) exakt diese Datei
erreichbar sein. Der SHA-256-Fingerprint ist der des **Upload-Keystores**
(`android/key.properties` → storeFile). Nach Play-App-Signing zusätzlich den
Play-Fingerprint ergänzen (Play Console → Setup → App Signing).

```json
[
  {
    "relation": [
      "delegate_permission/common.handle_all_urls",
      "delegate_permission/common.get_login_creds"
    ],
    "target": {
      "namespace": "android_app",
      "package_name": "com.thestia.app",
      "sha256_cert_fingerprints": [
        "8C:BE:F7:D0:8F:86:66:54:2E:1D:53:B9:B4:26:C5:46:AF:82:47:93:1A:DF:E8:20:61:9E:17:F7:91:3F:3E:1A",
        "5A:B8:D0:D5:E5:1D:4C:69:C7:11:E3:12:02:A8:40:EA:DA:A8:30:5A:9D:EB:23:88:35:2A:CD:C1:5C:30:A9:79"
      ]
    }
  }
]
```

Der zweite Fingerprint ist der DEBUG-Keystore (`%USERPROFILE%\\.android\\debug.keystore`,
Standard-Passwort `android`) - OHNE ihn schlaegt die Passkey-Einrichtung in
jedem `flutter run`-Debug-Build mit
`CreatePublicKeyCredentialDomException` fehl, weil Credential Manager die
App-Signatur nicht gegen assetlinks.json verifizieren kann. Nach dem
Hinterlegen der Datei: Geraet neu starten bzw.
`adb shell pm reset-app-links com.thestia.app` und die App neu oeffnen.

## Schritte

1. Datei beim Hoster der Root-Domain (thestia.de) hinterlegen — Pfad
   `/.well-known/assetlinks.json`, erreichbar OHNE Auth und ohne Redirect.
2. Prüfen: `curl -i https://thestia.de/.well-known/assetlinks.json`
3. App installieren, dann verifizieren:
   `adb shell pm get-app-links com.thestia.app` (Erwartung: `verified`).
   Alternativ in den Geräteeinstellungen: Apps → Thestia → Standard öffnen.
4. Supabase Dashboard → Auth → URL Configuration / Redirect URLs: den
   HTTPS-Redirect (`https://thestia.de/reset-password`) statt bzw.
   zusätzlich zu `thestia://reset-password` eintragen, damit Recovery-Mails
   die sichere Variante nutzen.

Bleibt Schritt 2 aus, funktioniert der Reset weiterhin über das
`thestia://`-Schema (Fallback im Manifest) - nur ohne Abfangen-Schutz.

iOS entspricht dem: Associated Domain `applinks:thestia.de` im
Entitlements-File + `/.well-known/apple-app-site-association` auf der Domain.

## `apple-app-site-association`: Vorlage ist noch nicht ausgefüllt

`passkey-assets/apple-app-site-association` enthält aktuell

```json
{ "webcredentials": { "apps": ["REPLACE_WITH_APPLE_TEAM_ID.com.thestia.app"] } }
```

**Damit sind iOS-Passkeys wirkungslos.** Apple prüft den Team-Identifier
streng; `REPLACE_WITH_APPLE_TEAM_ID` ist kein gültiger Wert, also wird die
Domain-Bindung nie bestätigt. Die Datei wird zwar mit HTTP 200 und
`Content-Type: application/json` ausgeliefert, was den Defekt
unsichtbar macht — es gibt schlicht kein `webcredentials`-Match.

Vor dem ersten iOS-Build ersetzen:

1. Apple Developer → Membership → Team-ID (10 Zeichen, z. B. `ABCDE12345`).
2. In der Datei `REPLACE_WITH_APPLE_TEAM_ID` durch die Team-ID ersetzen.
   Bundle-ID `com.thestia.app` bleibt (steht so in `ios/Runner.xcodeproj`).
3. Prüfen: `curl -i https://auth.thestia.de/.well-known/apple-app-site-association`
   — die Antwort darf keine Zeichenkette `REPLACE_` enthalten.

`tool/check_passkey_assetlinks.py` schlägt bei diesem Punkt an, solange die
Vorlage steht.

## Warum die Datei genau zwei Zertifikate enthält

`assetlinks.json` listete jedes Zertifikat doppelt: einmal als
colon-getrennter Hex in Großbuchstaben und einmal als kompakter Hex in
Kleinbuchstaben. Android vergleicht Zertifikatsbytes, nicht die
Schreibweise, deshalb war die Doppelung wirkungsloser Ballast — sie hat
nur Diff-Vergleiche unlesbar gemacht und echte Abweichungen zwischen
Live- und Repo-Datei kaschiert. Beide Formate sind jetzt auf den
kanonischen colon-getrennten Eintrag zusammengeführt.

Der Debug-Fingerprint gehört hier ausdrücklich **dazu**: ohne ihn schlägt
die Passkey-Einrichtung in jedem `flutter run`-Debug-Build mit
`CreatePublicKeyCredentialDomException` fehl, weil Credential Manager die
App-Signatur sonst nicht gegen `assetlinks.json` prüfen kann. Für die
*serverseitige* Origin-Liste ist das eine andere Frage — siehe
`docs/PASSKEYS_SERVER_SETUP.md`.

## Nach dem ersten Play-Upload nachpflegen

Der Fingerprint des Play-App-Signing-Keys **fehlt hier bewusst**, weil er
erst beim ersten Upload entsteht: Play erzeugt den App-Signing-Key beim
Anlegen der App, nicht vorher. Ihn zu raten oder vorzutragen wäre
falsch. Sobald der erste Upload durch ist:

1. Play Console → Setup → App Signing → *App signing key certificate*
   → SHA-256-Fingerabdruck kopieren.
2. Als dritten Eintrag in `sha256_cert_fingerprints` aufnehmen.
3. Den zugehörigen `android:apk-key-hash:`-Origin ebenfalls in Supabase
   ergänzen (Auth → Sign In / Providers → Passkeys → Origins).
4. `python tool/check_passkey_assetlinks.py --live` muss danach grün sein.

Grund: Von Play installierte Builds tragen den Play-Key, nicht den
Upload-Key. Ohne diesen Eintrag läuft die native Passkey-Dialog-Prüfung
im Play-Build ins Leere, während sie im Debug- und Sideload-Build
funktioniert.
