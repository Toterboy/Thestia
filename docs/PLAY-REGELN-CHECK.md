# Google-Play-Vorgaben: Prüfstand v0.9.2 (versionCode 30)

Geprüft am 02.10.2026 gegen das tatsächlich gebaute Artefakt
(`releases/v0.9.2/Thestia-v0.9.2-play.apk` und `.aab`), nicht gegen die
Konfiguration allein. Grund: `targetSdk` steht nicht im Buildskript,
sondern kommt von Flutter - nur das Artefakt sagt, was tatsächlich
drinsteht.

Kurzfassung: **technisch publishbar, administrativ noch nicht.** Es gibt
drei Punkte, an denen die Play-Prüfung scheitern kann, und eine
Voraussetzung, die gar nicht im Repository liegt (öffentliche
Datenschutz-URL).

---

## 1. Erfüllt

| Punkt | Befund |
|---|---|
| applicationId | `com.thestia.app` — endgültig, keine `.test`/`.debug` |
| versionCode / versionName | 30 / 0.9.2 — Changelog für 30 vorhanden |
| `targetSdkVersion` | **36** — erfüllt Googles aktuelle Anforderung |
| `minSdkVersion` | 28 — unkritisch |
| App-Bundle | `Thestia-v0.9.2-play.aab`, 203 MB, `BUNDLE-METADATA` + `base` vorhanden |
| 64-Bit | `arm64-v8a` enthalten — Pflicht seit 2019 erfüllt |
| Release-Signatur | Build bricht ohne `android/key.properties` hart ab, kein stiller Debug-Fallback |
| Admin-Abgrenzung | `check_release_artifacts.py`: OK, 11 Artefakte, Signatur und Admin-Trennung stimmen; kein Admin-Build im öffentlichen Ablageort |
| Store-Icon | `icon.png` 512×512, 222 KB — Vorgabe erfüllt |
| Feature Graphic | `featureGraphic.png` 1024×500, 106 KB — Vorgabe erfüllt |
| Screenshots | 5 Stück 1080×1920 im Fastlane-Ordner |
| Titel | `Thestia`, 7 Zeichen (Limit 30) |
| Kurzbeschreibung | 78 Zeichen (Limit 80) |
| Vollbeschreibung | 1486 Zeichen (Limit 4000) |
| Kontolöschung | `auth_provider.deleteAccount()` plus UI in Einstellungen und Datenschutz |
| Datenschutzerklärung | `docs/DATENSCHUTZ.md`, Stand September 2026, Version 4 |
| DSFA | `docs/DSFA.md` + `docs/DSFA-FRAGEN.md` liegen vor |
| Keine In-App-Käufe | kein Billing-Plugin — keine Play-Billing-Pflicht |
| `allowBackup=false` | Profil-PII und Caches gelangen nicht in Cloud-Backup |
| `usesCleartextTraffic=false` | kein Klartext-HTTP |
| BLE-Berechtigungen | Legacy-Permissions per `maxSdkVersion="30"` begrenzt, `BLUETOOTH_SCAN` mit `neverForLocation` |

---

## 2. Blocker (ungeprueft nach dem Umbau)

Dieser Abschnitt beschreibt den Ausgangszustand. Was seither behoben
wurde, steht in Abschnitt 6.

### 2.1 Mikrofon ohne prominente Offenlegung — Play-Richtlinie

`RECORD_AUDIO` ist im Manifest deklariert und wird von `record` für
Sprachnachrichten und Anrufe genutzt. In `chat_detail_screen.dart:1292`
prüft die App aber nur:

```dart
final hasPermission = await _audioRecorder.hasPermission();
if (!hasPermission) { /* SnackBar "Mikrofon verweigert" */ return; }
```

Es gibt **keine prominente Offenlegung in der App, bevor der
Systemdialog erscheint**, und die App fordert die Berechtigung nicht
selbst an. Google verlangt für `RECORD_AUDIO` beides: eine in der App
sichtbare Erklärung *vor* der Anfrage und die Berechtigung im
Kontext der Funktion. Zusätzlich muss im Play Console das
Mikrofon-Formular ausgefüllt werden.

Dieselbe Lücke hat `CAMERA` (aus dem `camera`-Plugin, für Videoanrufe).

### 2.2 `ACCESS_FINE_LOCATION` ohne Kernfunktions-Nachweis

Beide Standortberechtigungen sind deklariert; angefragt wird über
`Permission.locationWhenInUse` in `transit_ble_service.dart:80` und
`location_verification_service.dart:29`. Für die Entfernungsberechnung
verlangt Play in aller Regel **keinen** genauen Standort — die
ungefähre Berechtigung genügt. `ACCESS_FINE_LOCATION` muss im
Deklarationsformular begründet werden, und die Begründung
„Entfernungsanzeige" ist genau der Fall, bei dem Google ablehnt.

`minSdk = 28` heißt: Geräte mit Android 9/10 bekommen den
Standortdialog von Google in der feineren Form. Das ist keine
Verletzung, aber ein Grund, `FINE` zu prüfen.

### 2.3 Keine öffentliche Datenschutz-URL

`docs/DATENSCHUTZ.md` ist eine Datei im Repository. Die Play Console
verlangt eine **öffentlich erreichbare URL**, die ein Nutzer ohne Konto
abrufen kann. Im Repository ist keine hinterlegt — weder in den
Fastlane-Metadaten noch in den Dokumenten.

Solange die Erklärung nicht unter einer URL liegt, ist die
Veröffentlichung blockiert. Das ist die einzige Lücke, die nicht im
Code behoben werden kann.

---

## 3. Risiken, die kein Block sind

**`READ_EXTERNAL_STORAGE` ohne `maxSdkVersion`.** Wird von
`image_picker` gemergt, gilt seit Android 13 als wirkungslos. Play
weist in der Vorabprüfung auf ungenutzte Berechtigungen hin. Gegenmass-
nahme: `android:maxSdkVersion="32"` per Manifest-Merge.

**`WRITE_EXTERNAL_STORAGE` mit `maxSdkVersion="28"`** ist technisch
korrekt begrenzt, gehört aber zur alten Generation und taucht in der
Vorabprüfung auf.

**`targetSdk` ist nicht festgeschrieben.** `build.gradle.kts:62` setzt
`targetSdk = flutter.targetSdkVersion`. Heute löst das zu 36 auf — also
richtig. Aber der Wert ändert sich still mit jedem Flutter-Upgrade.
Genau darin ist die Anforderung schon einmal gerutscht. Fest auf 36
setzen und die Zahl dann mit Googgles Vorgaben zusammen aktualisieren.

**BOM in den Fastlane-Textdateien.** `title.txt` und
`short_description.txt` beginnen mit U+FEFF. Bei 78 von 80 erlaubten
Zeichen kann das unsichtbare Zeichen über die Grenze gehen oder im Store
sichtbar werden. `full_description.txt` und `changelogs/30.txt` sind
sauber — dieselbe Datei-Klasse wird also unterschiedlich behandelt.

---

## 4. Muss im Play Console gesetzt werden

Diese Punkte kann kein Code im Repository erfüllen:

1. **Datenschutz-URL** — öffentlich erreichbar (siehe 2.3).
2. **Data-Safety-Formular** — Vorlage: `docs/DSFA.md`. Zu deklarieren
   sind mindestens E-Mail, Profil, Standort, Fotos, Chatinhalt,
   Altersangaben; Verschlüsselung im Transit ist gegeben, das
   Datenlösch-Formular ebenfalls (`auth_provider.deleteAccount()`).
3. **Inhaltsbewertung** (IARC) — Fragebogen; Sexual-/Dating-Inhalt
   ist relevant.
4. **Zielgruppe und Familiendienst** — die App hat ein serverseitiges
   18+-Gate (`supabase/migrations/131`), die Zielgruppe ist damit
   eindeutig. Bei Kind-directed Inhalten wäre das verboten.
5. **Kategorie** — Dating.
6. **Anzeigen** — keine, also „keine Anzeigen" ankreuzen.
7. **App-Zugriff** — alle Nutzer, falls die Superskription ausläuft.
8. **Preisrichtlinie / Billing** — entfällt, keine digitalen Güter.

---

## 5. Empfohlene Reihenfolge

1. Datenschutz-URL bereitstellen und in die Fastlane-Metadaten
   aufnehmen — ohne das gibt es keine Veröffentlichung.
2. `ACCESS_FINE_LOCATION` prüfen: Wenn die Entfernungsanzeige die
   einzige Nutzung ist, auf `COARSE` reduzieren. Das entfernt eine
   sensibele Berechtigung und einen Deklarationspunkt.
3. Prominente Offenlegung vor Mikrofon- und Kameraanfrage ergänzen.
4. `targetSdk` fest auf 36 pinnen.
5. `READ_EXTERNAL_STORAGE` per Manifest-Merge begrenzen.
6. BOM aus `title.txt` und `short_description.txt` entfernen.
7. Data-Safety-, Inhaltsbewertungs- und Zielgruppenformular anhand
   `docs/DSFA.md` ausfüllen.

---

## 6. Nachtrag: was umgesetzt wurde

Alles gegen das **gemergte Manifest** geprueft, nicht gegen die
 Quelldatei. Der Nachweis:

    :app:processPlayReleaseManifest
    -> build/app/intermediates/merged_manifests/playRelease/
       processPlayReleaseManifest/AndroidManifest.xml

### Mikrofon-Offenlegung: erledigt

`chat_detail_screen.dart` zeigt vor der ersten Aufnahme einen Dialog
(`chat.micDisclosureTitle/Body/Accept`) und fragt die Berechtigung erst
nach dessen Bestaetigung an. Bestaetigt wird in `AppSettings`
(`micDisclosureAccepted`, geraete-lokal, nicht in `ui_prefs`).

Vorher stand dort nur `hasPermission()`; das Plugin fragte an, ohne
dass die App vorher etwas gesagt hatte. Das Mikrofon-Formular im Play
Console muss trotzdem ausgefuellt werden - das ist eine Formular-
angabe und kein Code.

### ACCESS_FINE_LOCATION: entfernt

`tools:node="remove"` im Manifest; im gemergten Manifest **nicht mehr
vorhanden**. Die Begruendung fuer Play steht als Kommentar im Manifest:
Entfernungsanzeige, Standortverifikation und Transit Spark kommen
alle mit ungefaehrer Genauigkeit aus.

Dazu passend `LocationAccuracy.high` -> `medium` in
`location_verification_service.dart`. `high` liefert ohne GPS-Signal
gar keine Position, die Standortverifikation waere also nicht
moeglich gewesen - sie ist mit `medium` stabiler, nicht schwaecher.

### Legacy-Speicherzugriffe: begrenzt

`READ_EXTERNAL_STORAGE` traegt jetzt `maxSdkVersion="32"`,
`WRITE_EXTERNAL_STORAGE` `maxSdkVersion="28"` - im gemergten Manifest
nachgewiesen.

### targetSdk: fest verdrahtet

`build.gradle.kts`: `targetSdk = 36` statt `flutter.targetSdkVersion`.
Im gemergten Manifest steht `android:targetSdkVersion="36"`.

### BOM: entfernt

`title.txt` und `short_description.txt` sind jetzt BOM-frei, Zeilenenden
vereinheitlicht.

### Verwaiste Dateien: werden entfernt

`make_store_screenshots.py` loescht PNGs in den Ausgabeordnern, die zu
keinem Screen mehr gehoeren, und meldet jeden Loeschvorgang. Vorher
blieb `02_anmelden.png` im Fastlane-Ordner liegen und waere beim
Upload mitgegangen.

### Rechteck-Dateien: keine Namenskollision mehr

Die Dateien heissen `rects_<voller Screen-Name>.json`. Vorher teilten
sich `02_anmelden` und `02_chat` eine Datei `rects_02.json`: die
Rechtecke des Anmelde-Screens wurden auf das Chat-Bild angewendet und
zerschnitten es. Ein umbenannter Screen erzeugte damit ein sichtbar
falsches Bild.

### Drei echte Fehler im Chat, gefunden beim Rendern

1. `initState` schrieb Provider-State (`activeChatIdProvider`,
   `hydrateHistory`). Riverpod verbietet das in Lebenszyklus-Phasen und
   nennt `initState` in der Fehlermeldung. Der Start liegt jetzt im
   ersten `addPostFrameCallback`.
2. `dispose()` las `ref` nach der Freigabe des Consumer-States.
3. `EncryptionService.dispose()` griff auf Hive-Boxen zu, die nie
   initialisiert waren, wenn `initialize()` scheiterte - der
   Folgefehler kam beim Abbau und verdeckte die eigentliche Ursache.

### Kamera-Offenlegung: erledigt

`VerificationVideoScreen` holte die Kameraliste in `initState` - der
Nutzer sah den Systemdialog, ohne vorher zu erfahren, warum die App
filmt. Jetzt steht davor `verify.cameraDisclosure*`, und die Kamera
oeffnet erst nach der Bestaetigung. Bestaetigung in
`AppSettings.cameraDisclosureAccepted`.

Wichtig und leicht uebersehen: die Aufnahme laeuft mit
`enableAudio: true`, und die Challenge `speakNumber` verlangt eine
gesprochene Zahl. Die App nutzt hier also **beide** Berechtigungen.
Ein Text, der nur die Kamera nennt, laesst `RECORD_AUDIO` unangezeigt -
das waere eine unvollstaendige Offenlegung. Der Dialog nennt deshalb
beides und setzt beide Einwilligungen.

Damit ist der Kamera-Teil erledigt. Was bleibt, ist ausserhalb des
Codes:

- **Datenschutz-URL.** Datei im Repository, keine oeffentliche
  Adresse. Ohne sie keine Veroeffentlichung. Laesst sich nur ausserhalb
  des Codes erledigen.
- **Play-Console-Formulare:** Data Safety, IARC-Inhaltsbewertung,
  Zielgruppe, Kategorie Dating, keine Anzeigen.
- **Mikrofon- und Kamera-Formular** in der Abfrage. Die Bedienoberflaeche
  ist jetzt vorbereitet, die Formularangaben nicht.

### Dritter Dispose-Fehler derselben Art

Beim Bauen des Kamera-Tests fiel auf: `VerificationService.dispose()`
ruft `_box.close()` auf einem `late`-Feld ohne Absicherung. Wurde der
Dienst abgebaut, bevor `initialize()` durchlief, war das ein
`LateInitializationError` - und zwar beim Abbau, nicht beim Fehler,
der eigentlich die Ursache war. Derselbe Fehlertyp wie in
`EncryptionService.dispose()`, jetzt mit derselben Absicherung.
