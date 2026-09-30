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

## Offen: UUID gilt als bekannt

Es ist **nicht geklärt, ob v0.9.1 bereits an Nutzer ausgeliefert wurde**
(weder Play Store noch F-Droid). Bis das geklärt ist, wird die UUID
**als kompromittiert behandelt**.

Daraus folgt:

1. **Neues Admin-Konto in Supabase anlegen** – die bisherige User-ID
   nicht wiederverwenden.
2. **Admin-APKs neu bauen** mit der neuen UUID. Die v0.9.2-Admin-APKs
   tragen ebenfalls die alte und sind damit genauso betroffen; sie sind
   nur nicht öffentlich verteilt (`releases/*/admin/` ist gitignoriert).
3. **Öffentliche APKs müssen nicht neu gebaut werden** – sie enthalten die
   UUID nachweislich nicht (durch `tool/check_release_artifacts.py`
   geprüft).

Der öffentliche Pfad ist damit sauber, die Admin-Funktion muss vor einem
echten Admin-Einsatz neu aufgesetzt werden.

## Prüfen

```powershell
# Ohne UUID: prüft Signatur und Admin-Trennung, verlangt keine Geheimnisse.
python tool\check_release_artifacts.py

# Mit UUID: prüft zusätzlich, dass die UUID in den Admin-Builds steckt
# und in keinem öffentlichen.
$env:ADMIN_UUID="…"
python tool\check_release_artifacts.py
```
