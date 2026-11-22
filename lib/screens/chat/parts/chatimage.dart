// Der Teil '_ChatImage'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

/// Das Bild einer Bildnachricht.
///
/// BEFUND (09.11.2026, Betreiber): "Die Bilder sind nicht sichtbar, wenn
/// hochgeladen." DER GRUND: Die Bildnachricht war eine Attrappe - die
/// Blase zeichnete einen Farbverlauf mit einem Bild-Symbol, egal was
/// angezeigt werden sollte.
///
/// Die Bytes sind aber da: Das Bild kommt E2E-verschluesselt ueber den
/// DataChannel an (als Daten-URL in `mediaUrl`, Chat-Screen Zeile 910)
/// und wird auch lokal so abgelegt (Zeile 1271). Es fehlte nur die
/// Anzeige.
///
/// Der Verpixel-Schutz bleibt: Ist [blurred] true, wird das echte Bild
/// verpixelt - erst nach der ausdruecklichen Bestaetigung wird es
/// scharf (Datenschutz-Einstellung "blurChatImages", Default an).
class _ChatImage extends StatelessWidget {
  const _ChatImage({
    required this.mediaUrl,
    this.blurred = false,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  /// Die Daten-URL des Bildes ("data:image/jpeg;base64,...").
  final String mediaUrl;

  /// Ob das Bild verpixelt gezeigt wird (Datenschutz).
  final bool blurred;

  final BoxFit fit;
  final double? width;
  final double? height;

  /// Die groesste Kante eines Bildes in der Blase (px).
  ///
  /// BEFUND (09.11.2026): Die Bilder waren viel zu gross im Chat.
  static const double _maxKachel = 160;

  /// Der Radius der abgerundeten Ecken.
  ///
  /// NUTZERWUNSCH (22.11.2026): "Bilder im Chat an den Kanten
  /// abgerundet, damit sie nicht eckig sind." Davor stand das Bild
  /// als Rechteck in der Blase - die eckigen Kanten fielen auf.
  static const double _radius = 12;

  /// Die dekodierten Bytes - mit Cache.
  ///
  /// Der Cache ist wichtig: Ohne ihn wuerde die Blase bei JEDEM
  /// Neuaufbau das Base64 dekodieren (die Bilder sind einige hundert
  /// Kilobyte gross). Der Cache ist begrenzt, damit er nicht wächst.
  static final Map<String, Uint8List> _cache = {};

  static Uint8List? _bytesOf(String url) {
    if (url.isEmpty) return null;
    final imCache = _cache[url];
    if (imCache != null) return imCache;
    if (!url.startsWith('data:')) return null;
    final komma = url.indexOf(',');
    if (komma < 0) return null;
    try {
      final bytes = base64Decode(url.substring(komma + 1));
      if (_cache.length > 24) _cache.clear();
      _cache[url] = bytes;
      return bytes;
    } catch (_) {
      // Kein gueltiges Base64 - dann bleibt der Platzhalter.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytesOf(mediaUrl);
    if (bytes == null) {
      return const _ImageBubblePlaceholder();
    }
    // BEFUND (09.11.2026, Betreiber): "Die Bild anzeige von Bildern,
    // die man schickt, ist viel zu gross im Chat." Das Bild fuellte die
    // ganze Zeile der Blase aus. Es ist jetzt auf eine Feste Kachel
    // begrenzt (160 px) - ein Vorschaubild, kein Vollbild.
    //
    // NUTZERWUNSCH (22.11.2026): Die Kanten sind abgerundet - das Bild
    // soll nicht eckig wirken. Das Zuschneiden kommt VOR der
    // Weichzeichnung: sonst laeuft der weiche Rand ueber die runden
    // Ecken hinaus.
    Widget bild = ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Image.memory(
        bytes,
        fit: fit,
        width: width ?? _maxKachel,
        height: height,
        // In der Blase reichen 600 px - ohne das waeren es mehrere MB
        // dekodierte Bitmap pro Bild.
        cacheWidth: fit == BoxFit.contain ? null : 600,
      ),
    );
    if (blurred) {
      bild = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: bild,
      );
    }
    return bild;
  }
}
