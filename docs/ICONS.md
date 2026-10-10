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
| Startbildschirm (Android 12+) | `drawable/android12splash.png` | **Kreis, füllt die Leinwand** |
| In der App (Willkommen etc.) | `assets/images/thestia_icon_base.png` über `AppLogo` | Squircle, 34 px transparenter Rand |
| Play-Store-Eintrag | `fastlane/.../icon.png` | Squircle (Play maskiert selbst) |

## Der Schatten am Start (v0.10.0)

**Befund:** Beim App-Start erschien das Symbol erst rund und groß, mit
einem dunklen Rand an den unteren Ecken - wie ein Schatten. Danach
erschien das eckige Symbol in der App, ohne Schatten.

**Ursache:** `android:windowSplashScreenAnimatedIcon` zeigte auf
`@mipmap/ic_launcher`, also auf das **adaptive** Icon. Dessen Vordergrund
liegt in der 72-dp-Safe-Zone einer 108-dp-Leinwand - ein Drittel der
Fläche ist transparent. Die Systemmaske des Splash zeichnet den
sichtbaren Teil mit einem Schatten. Der Schatten gehört also nicht zum
Logo, sondern kommt von der Maskierung.

**Was vorher schon versucht wurde und warum es nicht half:** Der
entgegengesetzte Weg - `@drawable/android12splash` statt
`@mipmap/ic_launcher`. Die `android12splash.png` von damals war ein
Squircle **auf weissem Grund**, sichtbar kleiner als der Kreis des
Systems. Genau dieser Zwischenraum erzeugte denselben Schatten. Die
Datei hatte nicht die Form, die das Splash braucht.

**Lösung:** `android12splash.png` ist jetzt ein Kreis, der die Leinwand
voll ausfüllt - die Kante berührt die Mitte jeder Seite, die Ecken sind
transparent (Deckung 78,7 % = π/4, exakt eingeschrieben). Die Systemmaske
hat damit nichts zu beschneiden und keinen Rand, an dem ein Schatten
entstehen kann.

## Wartung

Wer das Logo ändert, muss **drei** Schritte laufen lassen, sonst zeigen
Splash, App-Liste und Store verschiedene Bilder:

```powershell
python tool\generate_launcher_icon.py   # adaptive Icons + App-Liste
python tool\make_play_icon.py           # Play-Store-Eintrag
# android12splash.png: siehe unten
```

`android12splash.png` hat noch **kein** Werkzeug - es wurde einmalig aus
der Basis-Datei erzeugt. Wer es ändert, muss den Kreischarakter
beibehalten: eingeschriebener Kreis, Kanten in der Seitenmitte, Ecken
transparent. Ein undurchsichtiges Rechteck darum würde im Nachtmodus als
helle Kante auffallen, weil der Splash-Hintergrund aus dem Theme kommt
(`#ffffff` hell, `#121212` dunkel).

Die `-night`-Varianten sind identisch zur Tag-Variante: das Logo ist ein
Farbverlauf und braucht keine Anpassung. Sie existieren, weil Android
sie dort erwartet, wo das normale `drawable` nicht greift.
