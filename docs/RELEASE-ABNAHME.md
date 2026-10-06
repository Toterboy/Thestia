# Release-Abnahme (Pruefliste)

Diese Liste wird vor **jedem** Release durchlaufen. Sie ist eine Liste, kein
Fließtext: jede Zeile hat einen Pruefbefehl, ein erwartetes Ergebnis und eine
Anweisung fuer den Fall der Abweichung.

**Anlass fuer dieses Dokument:** Bei v0.9.2 war die App in *jedem*
Release-Build nicht startfaehig. Vier Fehler fielen ausschliesslich auf einem
echten Geraet mit Release-APK auf - kein Debug-Build und kein Simulator hat sie
gezeigt. Sie stehen in [Nur im Release pruefen](#nur-im-release-pruefen).

## Regeln fuer diese Abnahme

- Ein Haken wird nur gesetzt, wenn das **erwartete Ergebnis** eingetreten ist.
  "Sieht gut aus" ist kein Ergebnis.
- Ein Punkt, der fehlschlaegt, blockiert das Release. Kein "wird nachgezogen".
- Wer einen Punkt ueberspringt, notiert hier unten **was** und **warum**.
- Diese Pruefung ist **Handarbeit auf echten Geraeten**. Sie ist nicht
  automatisierbar, und genau darin liegt ihr Wert.

## 0. Ausgangslage

| Feld | Wert |
| --- | --- |
| Version (`pubspec.yaml`) | `0.9.2+30` |
| Commit | `0b1888a` |
| Branch | `main` |
| Geraet(e) | `a86fc552` |
| Zweitgeraet fuer Transit Spark | siehe [BLE-GERAETETEST.md](BLE-GERAETETEST.md) |
| Datum der Abnahme | ____________ |
| Abgenommen von | ____________ |

---

## 1. Automatische Pruefungen (Commit-Stand)

Alle laufen aus dem Repo-Wurzelverzeichnis, kein Setup ausser `.env`.

| # | Pruefbefehl | Erwartetes Ergebnis | Bei Abweichung |
| --- | --- | --- | --- |
| 1.1 | `git status --short` | **leer** (nur `??` fuer bewusst neue Dateien) | Nicht abnehmen. Unbeabsichtigte Aenderung zuruecksetzen oder den neuen Commit erstellen und erneut abnehmen. |
| 1.2 | `flutter analyze --fatal-infos` | `No issues found!` | Release stoppen. Hinweis-Ausgabe (`info`) zaehlt genauso wie Fehler, deshalb das Flag. |
| 1.3 | `flutter test` | `All tests passed!` | Release stoppen. Siehe unten zur Screenshot-Falle. |
| 1.4 | `python tool\check_push_readiness.py` | Exitcode `0` | Release stoppen. Meldung im Terminal ist die Begruendung. |
| 1.5 | `python tool\check_migrations_sql.py` | Exitcode `0` | Release stoppen. SQL-Fehler in einer Migration. |
| 1.6 | `python tool\check_migration_safety.py` | Exitcode `0` | Release stoppen. Ungesichere Operation in einer Migration. |
| 1.7 | `python tool\check_security_invariants.py` | Exitcode `0` | Release stoppen. RLS-/SECURITY-DEFINER-Invariante verletzt. |
| 1.8 | `python tool\check_keys.py` | Exitcode `0` | Release stoppen. Ein Geheimnis liegt im Repo (siehe [ADMIN-UUID.md](ADMIN-UUID.md)). |
| 1.9 | `python tool\check_mojibake.py --skip-known` | Exitcode `0` | Release stoppen. UTF-8 in einem String zerstoert (Umlaut als `?`). |

## 2. Release bauen

| # | Pruefbefehl | Erwartetes Ergebnis | Bei Abweichung |
| --- | --- | --- | --- |
| 2.1 | `powershell -NoProfile -ExecutionPolicy Bypass -File ".\tool\build_release.ps1" -Flavor both -UniversalApk -SplitPerAbi -Aab` | „Fertig" **und** 9 Dateien in `releases\<version>\` | **Alle drei Schalter sind Pflicht.** Ohne einen davon baut das Skript nichts und meldet trotzdem „Fertig". Das ist zweimal passiert. Bei leerem Ablageort: Schalter pruefen, nicht das Skript. |
| 2.2 | `Get-ChildItem "releases\v0.9.2" -Filter *.apk` | 8 APKs + 1 AAB (`play`, `fdroid`, jeweils universal + armv7/arm64/x86_64) | Fehlende Datei: der jeweilige `--split-per-abi`-Lauf fehlte. Neu bauen. |
| 2.3 | `python tool\check_release_consistency.py` | `OK  9 Artefakte: ein Build, Berechtigungen, Versionen, Screenshots stimmen.` und Exitcode `0` | Release stoppen. Der Befund nennt, ob ein Build, eine Berechtigung, eine Version oder ein Screenshot falsch ist. |
| 2.4 | `python tool\check_release_artifacts.py` | `OK  11 Artefakte: Signatur und Admin-Trennung stimmen.` | Release stoppen. Besonders `Kein Admin-Build im oeffentlichen Ablageort` ist ein Blocker. |

### 2.5 Gegen das Binaer-Manifest pruefen, nicht gegen die Quelle

Der Merge-Report und die Quelldatei koennen beide recht haben und trotzdem
nicht das Artefakt beschreiben. **Massgeblich ist das, was im APK steht:**

```powershell
$aapt = (Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory |
         Sort-Object Name -Descending | Select-Object -First 1).FullName + "\aapt2.exe"
& $aapt dump permissions releases\v0.9.2\Thestia-v0.9.2-play.apk
```

| # | Erwartetes Ergebnis | Bei Abweichung |
| --- | --- | --- |
| 2.5.1 | `package: com.thestia.app` | Falscher Namespace: falscher Flavor gebaut. |
| 2.5.2 | `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `CAMERA`, `POST_NOTIFICATIONS`, `RECORD_AUDIO` vorhanden | Fehlende Berechtigung: Transit Spark oder Kamera funktioniert im Release nicht. Manifest korrigieren, neu bauen. |
| 2.5.3 | **keine** `.env`-Datei im APK | Release laedt die Konfiguration aus den Defines. |
| 2.5.4 | `INTERNET`, `ACCESS_NETWORK_STATE` vorhanden | Ohne Netz kein Login. |
| 2.5.6 | versionCode der Split-APKs: armv7 `1030`, arm64 `2030`, x86_64 `4030` (Basis `30`) | **Das ist korrekt und darf nicht als „gemischter Ordner" gemeldet werden.** Der ABI-Zusatz ist beabsichtigt. |

## 3. Nur im Release pruefen

**Dieser Abschnitt ist der Grund fuer dieses Dokument.** Ein Debug-Build kann
diese Punkte nicht finden - nicht weil sie unauffaellig sind, sondern weil sie
dort nicht auftreten. Bei v0.9.2 waren alle vier gleichzeitig vorhanden und die
App startete in jedem Release nicht.

| # | Was pruefen | Pruefbefehl / Vorgehen | Erwartetes Ergebnis | Wenn es fehlschlaegt |
| --- | --- | --- | --- | --- |
| 3.1 | `.env` wird in Release absichtlich **nicht** gebuendelt, `dotenv.env` **wirft** dann. `main.dart` las dort unbedingt. | Release-APK installieren und starten (siehe 4.1). | App startet, Initialisierung meldet keinen Fehler. | Jeder Zugriff auf `dotenv.env` braucht `dotenv.isInitialized` als Wache, sonst Default. Siehe `lib\main.dart:404`. |
| 3.2 | `debugPrint` stand in `if (kDebugMode)` - im Release wurden **Startschritt und Serverfehler der Registrierung verworfen**. | `logcat` waehrend des Starts und waehrend eines Registrierungsversuchs. | Startschritt- und Fehlermeldungen erscheinen auch im Release. | Kanal nicht auf `kDebugMode` conditionieren. |
| 3.3 | `String.fromEnvironment(key)` mit **Laufzeitvariable** liefert `""`. Nur Compile-Zeit-Konstanten funktionieren. | Defines gegen `const`-Konstanten pruefen: `Select-String -Path lib\**\*.dart -Pattern "fromEnvironment\("`. | Jeder Schlüssel steht als String-Literal im Aufruf, nicht als Variable. | Das war der eigene Repair, der die Supabase-Defines geleert hatte. Bei Abweichung Defines korrigieren und **neu bauen**. |
| 3.4 | `auth.register()` ohne Timeout kehrt auf einem Geraet ohne erreichbaren Server nie zurueck. **Nebenbefund dabei gefunden:** der Timeout existierte, hatte aber keinen eigenen Fehlerzweig - er landete in `error.generic` und war von einem CAPTCHA-Fehler nicht zu unterscheiden. Behoben, siehe 4.11. | Siehe 4.3. | Innerhalb von 20 s ein Fehler, nicht endloses Drehen. Und: der Text nennt die Ursache, nicht „irgendetwas". | Timeout fehlt: `login_screen.dart`, `authTimeout`. Generischer Text trotz Timeout: der `TimeoutException`-Zweig im `catch` fehlt oder steht nach dem generischen `else`. |
| 3.5 | Obfuskierung laeuft mit `--obfuscate`, Symbole liegen unter `build\symbols\`. | `Test-Path build\symbols\play` **und** `build\symbols\fdroid`. | Beide Ordner existieren nach dem Build. | Ohne Symbole sind Release-Stacks nicht deobfuskierbar. Admin: zusaetzlich `build\symbols\admin-<flavor>`. |

**Merksatz fuer den naechsten Build:** Wenn ein Release nicht startet, ist
`flutter run` auf dem Emulator **kein** Beweis, dass es startet.

## 4. Geraetepruefung (echtes Geraet, Release-APK)

> **Emulator zaehlt nicht.** Dort gibt es kein echtes Advertising, keine
> realistische Reichweite und kein Funkrauschen. Fuer 3.1 bis 3.4 zaehlt nur
> ein physisches Geraet mit dem Release-Artefakt.

Geraet: `a86fc552`. `adb devices` zeigt zusaetzlich `emulator-5562 offline` -
**immer** mit `-s a86fc552` arbeiten.

```powershell
$adb = "C:\Users\Thoralf\AppData\Local\Android\Sdk\platform-tools\adb.exe"
& $adb devices                       # a86fc552 muss "device" sein, nicht "offline"
& $adb -s a86fc552 logcat -v time > "$env:TEMP\log.txt"
```

| # | Test | Vorgehen | Erwartetes Ergebnis | Bei Abweichung |
| --- | --- | --- | --- | --- |
| 4.1 | **Release-APK auf echtem Geraet installieren und starten** | `& $adb -s a86fc552 uninstall com.thestia.app` (falls vorhanden), dann die **Universal-APK** aus `releases\v0.9.2\` installieren, Start per Hand | Startet durch. Kein Absturz, kein schwarzer Bildschirm, kein Force-Close. | **Das ist der Test, der 3.1 findet.** Nicht den Debug-Build starten. Wenn die Universal-APK nicht startet, erst die Split-APK derselben Version probieren - dann ist es ein ABI-Problem. |
| 4.2 | **Erster Start bis zum ersten Frame** | App kalt starten (vorher `& $adb -s a86fc552 shell am force-stop com.thestia.app`), Zeit stoppen | Logo erscheint, Splash mit Version, **kein Schwarz**, Weiterleitung zum Willkommens-Screen. Dauer plausibel (Groessenordnung: wenige Sekunden). | Schwarzes Bild = der Fehler aus 3.1. `logcat` nach `flutter` und `AndroidRuntime` filtern. |
| 4.3 | **Registrierung meldet in 20 s einen Fehler** | Registrierung mit **unbekannter** E-Mail starten, Uhr stoppen. Optional mit Flugmodus, um den Fall ohne Server zu erzwingen | Spatestens nach 20 s eine Meldung. Erwartet sind drei verschiedene Texte: `error.serverUnreachable` (Timeout), `error.captchaRejected` (CAPTCHA), `error.signupFailed` (Server). Nach Migration 134 **sollte die Registrierung durchlaufen** und zum E-Mail-Bestaetigungs-Screen fuehren. | Endloses Drehen = Timeout fehlt oder greift nicht (`login_screen.dart`, `authTimeout`). „Etwas ist schiefgelaufen" = ein anderer Fehler als der Timeout; im Server-Log nach `500` und `42703` filtern — das war bis Migration 134 der Normalfall. |
| 4.4 | Login | Bekanntes Konto anmelden | Anmeldung erfolgreich, Home-Screen. Bei falschem Passwort: verstaendliche Meldung, kein Absturz. | Fehlermeldung im Log pruefen. |
| 4.5 | **Eigener Chat** | Chat mit dem eigenen zweiten Konto öffnen | Historie laedt, Zeitstempel korrekt, Senden funktioniert. | Leere Historie bei echten Nachrichten = Relay-Problem, `relay_fetch` pruefen. |
| 4.6 | **Chat mit zweitem Konto** | Vom zweiten Konto eine Nachricht senden, in der ersten App öffnen | Nachricht erscheint innerhalb von ~6 s, entschluesselt lesbar. | Laenger als 6 s: Backoff-Stufe im Log (`[RelayInbox]`) pruefen. |
| 4.7 | **Einstellungen: Darstellung hell / dunkel / system** | Alle drei Modi umschalten, App neu starten | Modus wird uebernommen und **ueberlebt den Neustart**. Kein Absturz beim Wechsel. | Wert wird nicht persistiert: Hive-Key pruefen. |
| 4.8 | **Einstellungen: Chat-Verlauf-Modi** | Jeden Verlauf-Modus durchschalten (z. B. unbegrenzt / 7 Tage / 30 Tage / aus) | Auswahl greift sichtbar, kein Absturz. | Modus ohne Wirkung: Logik in den Chat-Screens. |
| 4.9 | **Alterspruefung mit ECHTEM Gesicht** | Alterpruefung mit dem **Gesicht der testenden Person** durchlaufen | Pruefung laeuft durch und erkennt das Alter (bzw. stuft korrekt ein). | **Groesste offene Luecke: nie mit echten Gesichtern getestet.** Die App verkauft die Alterspruefung. Ein Fehler hier ist ein Release-Blocker, kein Nice-to-have. |
| 4.10 | **Transit Spark mit zwei Geraeten** | Vollstaendiges Protokoll: [BLE-GERAETETEST.md](BLE-GERAETETEST.md) | Drei Kriterien bestanden, beide Richtungen. | Ergebnis dort eintragen. Transit Spark gilt laut ROADMAP erst mit zwei Geraeten verschiedener Hersteller als stabil. |

### 4.11 Was der Wortlaut der Registrierungsmeldung verraet

**ERLEDIGT seit v0.9.3 / Migration 134 (06.10.2026).** Die Registrierung ist
behoben; die Ursache war *nicht* Netz und *nicht* CAPTCHA, sondern ein
Datenbank-Trigger. Deshalb ist die Registrierung hier als Blocker gestrichen
und die Zeile davor ergaenzt.

| Angezeigter Text | L10n-Key | Bedeutung |
| --- | --- | --- |
| „Der Server hat nicht geantwortet. Prüfe deine Internetverbindung…" | `error.serverUnreachable` | Kein Server erreichbar, oder die Anfrage haengt im Netz |
| „Der Sicherheitscheck wurde vom Server abgelehnt…" | `error.captchaRejected` | Turnstile hat abgelehnt |
| „Registrierung auf dem Server fehlgeschlagen…" | `error.signupFailed` | Server hat geantwortet und den Nutzer abgelehnt |
| „Zu viele Anfragen in kurzer Zeit…" | `error.rateLimited` | Rate-Limit greift |
| „Etwas ist schiefgelaufen…" | `error.generic` | Unbekannt – `logcat` nach `[LoginScreen]` filtern |

#### Die behobene Ursache (v0.9.2-Befund)

Seit der Migration 128 gab es einen Trigger `trg_init_profile_auth_flags`
auf `public.profiles`, dessen Funktion `NEW.id` las. **`profiles` hat keine
Spalte `id`**, sein Schluessel heisst `user_id`. Postgres brach den
`handle_new_user`-Pfad mit `42703 record "new" has no field "id"` ab, die
Transaktion wurde mit `25P02` vergiftet, und GoTrue gab **500** statt einer
Anmeldung zurueck. Die App meldete das als `error.signupFailed` — daher war
die Registrierung seit v0.9.2 kaputt.

Zwei fast identische Funktionen aus Migration 128 spiegelten
`email_verified_at`: eine korrekt auf `auth.users` (dort *gibt* es `id`),
eine als Kopie auf `profiles`. Die Kopie war der Fehler. Migration 134
ersetzt sie und setzt den Wert direkt aus `NEW.email_confirmed_at` (eine echte
`profiles`-Spalte).

Belegt am Geraet: der Server-Log vom 06.10.2026, 17:38:16 zeigt genau
`500`, `42703` und `25P02`. Nach Migration 134 liefert derselbe Aufruf
`captcha_failed` (HTTP 400) — der Trigger bricht nicht mehr ab, es greift
nur noch die Turnstile-Pruefung, die ein echter Client mit Token besteht.

## 5. Store-Material

| # | Pruefbefehl | Erwartetes Ergebnis | Bei Abweichung |
| --- | --- | --- | --- |
| 5.1 | `Get-ChildItem "fastlane\metadata\android\de-DE\images\phoneScreenshots" -Filter *.png` | **5** PNGs: `01_willkommen`, `02_chat`, `03_entdecken`, `04_anpassen`, `05_eisbrecher` | Fehlt einer: neu rendern (5.3). |
| 5.2 | `python tool\check_store_screenshots.py` | `OK  Seitenverhaeltnis, Statusleisten-Reserve und System-Indikatoren stimmen.` | Screenshots neu rendern (5.3). |
| 5.3 | Neu rendern: `$env:STORE_SHOTS="1"; flutter test --update-goldens test/screenshots/store_v091_shots_test.dart`, danach `python tool\make_store_screenshots.py` und `python tool\check_store_screenshots.py` | 5 PNGs in `fastlane\...\phoneScreenshots` | **Ohne `$env:STORE_SHOTS="1"` meldet `flutter test` „All tests skipped" und die PNGs bleiben alt.** Der Composer setzt dann alte Bilder zu neuen Dateinamen zusammen - ohne Fehler. Das ist der Grund, warum hier „leer" nicht als Erfolg gilt. |
| 5.4 | `python tool\check_screenshot_consistency.py` | Exitcode `0` | Uebergroesse Schrift in mindestens einem Screenshot. |
| 5.5 | Screenshots gegen **diesen** Build pruefen | Jeder Screenshot zeigt den aktuellen Stand: kein veralteter Screen, keine alte Versionsnummer | Screenshot stammt aus einem aelteren Build: 5.3 wiederholen. |
| 5.6 | `python tool\check_png_integrity.py` | Exitcode `0` | Beschaedigte PNG-Datei. Neu rendern. |

## 6. Freigabe

Erst wenn 1 bis 5 vollstaendig ohne Abweichung durchlaufen sind:

| Feld | Eintrag |
| --- | --- |
| Alle Punkte 1-5 bestanden | ☐ |
| Uebersprungene Punkte mit Grund | ____________ |
| Migrationen angewendet (`supabase migration list` - kein leeres `remote`-Feld) | ☐ |
| Store-Upload durchgefuehrt | ☐ |
| Abnahme unterschrieben | ____________ |

### Migrationen vor dem Upload

`supabase migration list` zeigt fuer jede Zeile ein `remote`-Feld. Ein leeres
`remote` bedeutet: geschrieben, aber **nicht angewendet**.

```powershell
& "$env:APPDATA\npm\supabase.cmd" migration list
& "$env:APPDATA\npm\supabase.cmd" db push
```

Nach `db push` sind **Registrierung, Login, Chat und Radar** erneut zu pruefen
(4.3 bis 4.6). Eine fehlgeschlagene Migration aus diesem Satz - insbesondere
eine, die `search_path` an `SECURITY DEFINER`-Funktionen setzt - faellt dort
auf, weil die Funktion ihre Rechte verliert.

## 7. Bekannte offene Punkte (kein Grund, die Prüfung zu überspringen)

Diese Punkte sind **offen**. Sie stehen hier, damit niemand sie für erledigt
hält - nicht, damit sie übersprungen werden.

| Punkt | Stand | Wirkung auf die Abnahme |
| --- | --- | --- |
| Registrierung | **BEHOBEN** (Migration 134, 06.10.2026). Ursache war ein DB-Trigger, kein Netz und kein CAPTCHA. Nachweis: 500+42703 im Server-Log, nach dem Fix `captcha_failed`. | **Punkt 4.3 einmal auf dem Geraet bestaetigen**, dann ist er durch. |
| Alterspruefung | nie mit echten Gesichtern getestet | **Blocker** (4.9). |
| Transit Spark | [BLE-GERAETETEST.md](BLE-GERAETETEST.md) Status OFFEN | **Blocker** fuer die Behauptung „stabil". |
| Admin-APKs | tragen die als kompromittiert dokumentierte UUID, bewusst nicht neu gebaut | Kein Blocker fuer den oeffentlichen Release. Erst nach Rotation neu bauen. |

## 8. Werkzeug-Fallen

Die Kosten, die diese Liste schon einmal gekostet hat. Sie sind nicht
theoretisch, jeder Punkt hat Zeit gekostet.

| Falle | Wirkung | Konsequenz |
| --- | --- | --- |
| `build_release.ps1` ohne `-UniversalApk` **und** `-SplitPerAbi` **und** `-Aab` | Baut **gar nichts** und meldet „Fertig". Zweimal passiert. | Immer alle drei Schalter (2.1). Danach Dateiliste pruefen, nicht die Erfolgsmeldung. |
| Ausfuehrungsrichtlinie blockiert Skripte | `build_release.ps1` startet nicht | `powershell -NoProfile -ExecutionPolicy Bypass -File ...`. **Die Systemeinstellung nicht aendern.** |
| Screenshot-Tests ohne `$env:STORE_SHOTS="1"` | `flutter test` meldet „All tests skipped", PNGs bleiben alt | Nur mit Variable (5.3). „All tests skipped" gilt nie als bestanden. |
| Pruefen gegen die Quelldatei oder den Merge-Report | Beide koennen recht haben und das APK trotzdem falsch sein | Immer gegen das Binaer-Manifest (2.5). |
| Split-APKs haben einen ABI-Zusatz im versionCode | Wird als „gemischter Ordner" gemeldet, obwohl korrekt | Nicht als Fehler behandeln (2.5.6). |
| Supabase-CLI ohne `.cmd` | Der `.ps1`-Shim scheitert an der Ausfuehrungsrichtlinie | `& "$env:APPDATA\npm\supabase.cmd" ...`. |
| `adb devices` zeigt `emulator-5562 offline` | Befehle gehen an das falsche Geraet, logcat bleibt leer | Immer `-s a86fc552`. |
| Rohes Mehrzeilen-Literal in Dart | `lib\l10n\app_strings.dart` wurde dadurch unlesbar | String-Literale nicht ueber eine Zeilengrenze ziehen. |
| Generator mit Zeitstempel | Jeder Lauf erzeugt einen Diff | Generatoren deterministisch halten. |

## 9. Verwandte Dokumente

- [BUILD.md](BUILD.md) – Build-Voraussetzungen und Flavors
- [BLE-GERAETETEST.md](BLE-GERAETETEST.md) – Transit-Spark-Abnahme (4.10)
- [ADMIN-UUID.md](ADMIN-UUID.md) – getrennte Admin- und oeffentliche Ablage
- [DATENSCHUTZ.md](DATENSCHUTZ.md) – Datenschutzerklaerung und Aufbewahrung
- [INCIDENT-RESPONSE.md](INCIDENT-RESPONSE.md) – Reaktion auf kompromittierte Secrets
- [ROADMAP.md](../ROADMAP.md) – offene Punkte und Stabilitaetszusagen
