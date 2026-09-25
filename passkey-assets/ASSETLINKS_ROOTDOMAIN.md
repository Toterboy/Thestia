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
        "37:AA:4F:6C:C1:DE:B8:F5:95:74:5E:AC:0A:CE:0A:19:C9:54:72:80:FC:74:8F:02:66:BD:D2:EC:7B:E9:55:72",
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
