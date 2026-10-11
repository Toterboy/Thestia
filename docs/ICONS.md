# Icon-Quellen und wo was benutzt wird

Eine einzige Bildquelle: `assets/images/thestia_icon_base.png`. Alles
andere wird daraus erzeugt. Diese Datei sagt, welches Werkzeug welches
Ziel bedient - damit niemand drei Stellen gleichzeitig anfasst.

## Werkzeuge

| Werk | Erzeugt | Aufruf |
|---|---|---|
| `tool/generate_launcher_icon.py` | `ic_launcher_background/foreground/monochrome` in `drawable-*`, das Legacy-`ic_launcher.png` in `mipmap-*`, `mipmap-anydpi-v26/ic_launcher.xml`, `assets/images/thestia_icon_{foreground,background}.png` | `python tool\generate_launcher_icon.py` |
| `tool/make_play_icon.py` | `fastlane/metadata/android/de-DE/images/icon.png` (512x512) | `python tool\make_play_icon.py` |

## Wo welches Symbol sichtbar ist

| Oberfläche | Symbol | Form |
|---|---|---|
| App-Liste des Geräts (Android 8+) | adaptives Icon (`ic_launcher.xml`) | Rund/Squircle, je nach Launcher |
| App-Liste (vor Android 8) | `mipmap-*/ic_launcher.png` | Rund (vom Werkzeug gebaut) |
| Startbildschirm (Android 12+) | `drawable/android12splash.png` | **Kreis, 240 dp in 288 dp Leinwand** |
| In der App (Willkommen etc.) | `assets/images/thestia_icon_base.png` über `AppLogo` | Squircle, 34 px transparenter Rand |
| Play-Store-Eintrag | `fastlane/.../icon.png` | Squircle (Play maskiert selbst) |

## Der Schatten am Start und die Größe des Kreises (v0.10.0)

**Befund:** Beim App-Start erschien das Symbol erst rund und groß, mit
einem dunklen Rand an den unteren Ecken - wie ein Schatten. Danach
erschien das eckige Symbol in der App, ohne Schatten. Später kam die
zweite Beschwerde: der Kreis sei **zu groß aufgezoomt**.

**Ursache des Schattens:** `android:windowSplashScreenAnimatedIcon`
zeigte auf `@mipmap/ic_launcher`, also auf das **adaptive** Icon. Dessen
Vordergrund liegt in der 72-dp-Safe-Zone einer 108-dp-Leinwand - ein
Drittel der Fläche ist transparent. Die Systemmaske des Splash zeichnet
den sichtbaren Teil mit einem Schatten. Der Schatten gehört also nicht
zum Logo, sondern kommt von der Maskierung.

**Ursache der zu großen Darstellung:** Der Splash zeichnet in ein
Fenster von 288 dp × 288 dp, die sichtbare Maske ist ein Kreis von
**240 dp**. `android12splash.png` füllte die 288-dp-Leinwand mit einem
randlosen Kreis - er kam damit mit 288 dp statt 240 dp auf dem Gerät.

**Lösung (aktuell):** `android12splash.png` ist ein Kreis von exakt
240 dp, mittig in einer 288-dp-Leinwand, der Rand (24 dp je Seite)
transparent. Die Systemmaske greift, ohne etwas zu beschneiden, und der
Kreis erscheint in der vorgesehenen Größe. Der Rand ist weich
ausgeblendet - ein harter Alphaschnitt zeigt nach dem Downsample des
Systems eine Treppe am Kreisrand.

## Wartung

Wer das Logo ändert, muss **drei** Schritte laufen lassen, sonst zeigen
Splash, App-Liste und Store verschiedene Bilder:

```powershell
python tool\generate_launcher_icon.py   # adaptive Icons + App-Liste
python tool\make_splash_icon.py         # Splash (240-dp-Kreis)
python tool\make_play_icon.py           # Play-Store-Eintrag
```

`android12splash.png` wird von `tool/make_splash_icon.py` erzeugt und
darf **nicht** von Hand editiert werden: Das Skript kennt die
Systemgeometrie (240/288) und den weichen Rand. Wer die Datei manuell
verändert, verliert beides - und genau das war der Grund, warum der
Kreis zu groß war: Es gab vorher kein Werkzeug.

Die `-night`-Varianten sind identisch zur Tag-Variante: das Logo ist ein
Farbverlauf und braucht keine Anpassung. Sie existieren, weil Android
sie dort erwartet, wo das normale `drawable` nicht greift.
