# Admin-UUID: Stand und offene Punkte

## Was die Admin-UUID ist

`ADMIN_UUID` ist die User-ID eines Supabase-Kontos mit Admin-Rolle. Sie
wird per `--dart-define=ADMIN_UUID=…` in den Admin-Build kompiliert. Die
App prüft beim Start, ob die angemeldete User-ID damit übereinstimmt, und
schaltet dann die Admin-Funktionen frei.

Zwei Eigenschaften machen sie zu einem Geheimnis:

1. Sie steht als **Klartextzeichenkette im kompilierten Dart-Code** und
   lässt sich aus jeder APK herausziehen (`strings`, oder eigener Scanner).
2. Wer sie kennt, kann sie **selbst setzen** – in einem eigenen, umgebauten
   Build. Der Schutz ist nicht das Geheimnis, sondern dass es nicht
   öffentlich im Repository steht.

Deshalb steht sie in **keiner** Datei dieses Repos, auch nicht in
`build_release.ps1`. Sie wird beim Bauen über die Kommandozeile oder die
Umgebung übergeben.

## Befund vom 30.09.2026: Admin-Build im öffentlichen Ablageort

Bei v0.9.1 waren die beiden universellen APKs **byte-identisch** mit den
Admin-Builds:

```
v0.9.1/Thestia-v0.9.1-play.apk   == v0.9.1/admin/Thestia-v0.9.1-play-ADMIN.apk
v0.9.1/Thestia-v0.9.1-fdroid.apk  == v0.9.1/admin/Thestia-v0.9.1-fdroid-ADMIN.apk
   sha256 7d022cefc7fbc3e5… bzw. 69d174afe532d97e…
```

Ursache: der Admin-Build hat den öffentlichen Ablagepfad überschrieben.
Im Play Store wäre das nicht aufgefallen – beide Dateien sind gültig
signiert, und die übliche Publish-Prüfung sieht nur die *aktuelle* Version.

Die Split-APKs und das AAB von v0.9.1 waren nicht betroffen (dort steht
die UUID nicht drin). Die beiden universellen APKs wurden entfernt, weil
sie den Admin-Zugang enthielten und redundant waren.

`tool/check_release_artifacts.py` erkennt diesen Fall jetzt über alle
Versionen hinweg und lässt die CI bei einem Treffer fehlschlagen.

## Erledigt: Rotation und Neubau (v0.10.0)

Die drei Punkte sind abgearbeitet. Der Wert der neuen UUID steht
**bewusst nicht in diesem Dokument** – dieses File ist versioniert, und
eine UUID, die Admin-Zugriff freischaltet, gehört da nicht hinein.

1. **Neues Admin-Konto** – angelegt, neue User-ID, die alte wird nicht
   wiederverwendet.
2. **Admin-APKs neu gebaut** für v0.10.0, nach
   `releases/v0.10.0/admin/` (gitignoriert, `.gitignore:104`).
   Geprüft mit gesetzter Umgebungsvariable:
   `OK 11 Artefakte: Signatur und Admin-Trennung stimmen.` Die neue
   UUID steckt in beiden Admin-APKs und in **keinem** öffentlichen.
3. **Öffentliche APKs unverändert** – sie enthalten die UUID nachweislich
   nicht. Das ist keine Vermutung, sondern jedes Mal das Ergebnis von
   `check_release_artifacts.py`.

Die v0.9.2-Admin-APKs tragen die alte UUID und bleiben kompromittiert.
Sie sind nur deshalb nicht im Umlauf, weil `releases/*/admin/` ignoriert
ist. **Vor einem Admin-Einsatz prüfen, ob der alte Ablageort noch APKs
enthält** – der Bump von 0.9.2 auf 0.10.0 hat den Ordner
`releases/v0.9.2/admin/` nicht automatisch mitgenommen.

### Handhabung beim Bauen

Der Wert gehört in die Umgebungsvariable, nicht als Parameter:

```powershell
$env:ADMIN_UUID = "…"
powershell -NoProfile -ExecutionPolicy Bypass `
  -File ".\tool\build_release.ps1" -Flavor both -UniversalApk
Remove-Item Env:\ADMIN_UUID
```

`build_release.ps1` bricht ab, wenn `-AdminUUID` gesetzt ist: der Wert
landete achtmal unredigiert in der PowerShell-History und war während
des Laufs in der Prozessliste sichtbar. Für den Weg über die
Zwischenablage-/Temp-Datei geht derselbe Weg ohne beide Spuren.

## Offen: alte UUID gilt weiter als bekannt

Unabhängig von der Rotation bleibt offen, **ob v0.9.1 bereits an
Nutzer ausgeliefert wurde** (weder Play Store noch F-Droid). Die alte
UUID wird deshalb weiter als kompromittiert behandelt und nie wieder
verwendet – auch nicht für Testzwecke.

## Prüfen

```powershell
# Ohne UUID: prüft Signatur und Admin-Trennung, verlangt keine Geheimnisse.
python tool\check_release_artifacts.py

# Mit UUID: prüft zusätzlich, dass die UUID in den Admin-Builds steckt
# und in keinem öffentlichen.
$env:ADMIN_UUID="…"
python tool\check_release_artifacts.py
```
