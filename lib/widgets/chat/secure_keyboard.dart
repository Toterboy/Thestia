import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/settings/tastatur_einstellungen.dart';

/// Die eigene Bildschirmtastatur der App (v0.10.1).
///
/// **Der Wunsch des Betreibers (13.11.2026):** "dass die Handytastatur
/// nicht tracken kann was man schreibt. Das soll ja irgendwie gehen
/// können anscheinend".
///
/// **Was das Problem überhaupt ist:** Die Systemtastatur (Gboard,
/// SwiftKey, ...) ist ein eigenes Programm auf dem Gerät. Sie sieht
/// jeden Buchstaben, den man tippt, und darf daraus lernen - das
/// Wörterbuch, die Autokorrektur, die personalisierten Vorschlüge. Auf
/// einem Gerät, das man nicht besitzt (Fremdgerät, Secondhand,
/// manipulierte ROM) ist das nicht aufhaltbar - und "es ist nur die
/// Tastatur" ist keine Antwort, wenn man der anderen Person nicht
/// vertraut.
///
/// **Was hier dagegen steht:** Die Zeichen laufen vom Tasten-Widget
/// direkt in den Textcontroller. Die Systemtastatur wird gar nicht erst
/// geöffnet: Das Textfeld steht auf `readOnly`, und auf Android und iOS
/// entsteht bei einem `readOnly`-Feld überhaupt keine Eingabeverbindung
/// (`_shouldCreateInputConnection` ist dort `false`). Es gibt damit
/// nichts, was die Systemtastatur sehen kännte - nicht den getippten
/// Text, nicht einzelne Zeichen, nicht den Cursor.
///
/// **Was das NICHT ist - ehrlich gesagt:**
/// * Das gilt für die **Zeichen**. Alles, was sichtbar auf dem
///   Bildschirm steht, kann auch ein Zugriff auf das Display abgreifen.
///   Dagegen steht die Screenshot-Sperre (`FLAG_SECURE`), die die App
///   bereits auf allen Bildschirmen setzt.
/// * Es schützt nicht davor, dass jemand **über die Schulter** liest.
/// * Ein **gerootetes** Gerät ist pauschal nicht mehr zu retten.
///
/// **Ehrliche Grenze der Plattform:** Auf iOS gibt es zu
/// `enableIMEPersonalizedLearning` (Android) keine Entsprechung - dort
/// wirkt nur `autocorrect: false` + `enableSuggestions: false`. Der Weg
/// über die eigene Tastatur ist deshalb der einzige, der auf BEIDEN
/// Plattformen dasselbe verspricht - und deshalb der, den die App geht.
class SecureKeyboard extends StatefulWidget {
  const SecureKeyboard({
    required this.onCharacter,
    required this.onBackspace,
    this.onEnter,
    this.onHide,
    this.onPaste,
    this.layout,
    this.stil,
    this.farbe,
    super.key,
  });

  /// Die Belegung (0.11.0).
  ///
  /// Null bedeutet "wie die App" - dann folgt die Belegung der
  /// Sprache der App (deutsch → QWERTZ, englisch → QWERTY). Ein
  /// gesetzter Wert zwingt eine Belegung: wer auf Deutsch schreibt,
  /// aber in einer englischen Umgebung arbeitet, will die
  /// App-Sprache ändern, ohne dass sich die Tasten verschieben.
  final TastaturBelegung? layout;

  /// Der Farbstil der Tastatur (0.11.0).
  ///
  /// Null bedeutet "wie die App" - dann kommen die Farben aus dem
  /// App-Thema (das heutige Verhalten).
  final TastaturStil? stil;

  /// Die eigene Farbe der Tastatur (0.11.0) als ARGB-Zahl.
  ///
  /// Wird nur benutzt, wenn [stil] auf "eigeneFarbe" steht.
  final int? farbe;

  /// Die Belegung, die zur Sprache der App passt.
  ///
  /// Deutsch hat **QWERTZ** (das "y" und das "z" sind gegenüber der
  /// englischen Belegung vertauscht) und vier Umlaut-Tasten. Englisch
  /// hat **QWERTY**. Wer die App auf Englisch stellt, bekommt also die
  /// englische Tastatur - und umgekehrt.
  ///
  /// Alles ausser Deutsch bekommt QWERTY: das ist die weltweit
  /// übliche Belegung, und die App spricht ohnehin nur Deutsch und
  /// Englisch.
  static SecureKeyboardLayout layoutFuerSprache(String sprache) =>
      sprache == 'de'
      ? SecureKeyboardLayout.qwertz
      : SecureKeyboardLayout.qwerty;

  /// Ein einzelnes Zeichen (Buchstabe, Ziffer, Satzzeichen, Leerzeichen).
  final void Function(String character) onCharacter;

  /// Backspace.
  final VoidCallback onBackspace;

  /// Enter. Ohne Callback wird die Taste als inaktiv gezeigt.
  final VoidCallback? onEnter;

  /// Tastatur ausblenden (der Nutzer will zurück in den Chat).
  final VoidCallback? onHide;

  /// Einfügen aus der Zwischenablage.
  ///
  /// Der Umweg über die Systemtastatur ist hier nicht möglich: mit
  /// `readOnly` ist das Einfügen deaktiviert. Der Text kommt deshalb
  /// direkt aus der Zwischenablage der App - die Systemtastatur sieht
  /// dabei nichts.
  final VoidCallback? onPaste;

  @override
  State<SecureKeyboard> createState() => _SecureKeyboardState();
}

/// Die Belegung der eigenen Tastatur.
///
/// Deutsch hat QWERTZ (das "y" und das "z" sind vertauscht) und vier
/// Umlaut-Tasten; Englisch hat QWERTY. Die Belegung folgt der Sprache
/// der App - wer die App auf Englisch stellt, bekommt die englische
/// Tastatur.
enum SecureKeyboardLayout {
  /// Deutsch: QWERTZ mit ä, oe, ü, ss auf eigenen Tasten.
  qwertz,

  /// Englisch: QWERTY.
  qwerty,
}

/// Die Tasten einer Belegung.
class _Belegung {
  const _Belegung({
    required this.buchstaben,
    required this.extra,
    required this.zeichen,
  });

  /// Die drei Buchstabenreihen.
  final List<List<String>> buchstaben;

  /// Die Tasten neben den Buchstaben: bei QWERTZ die Umlaute, bei
  /// QWERTY die Satzzeichen.
  final List<String> extra;

  /// Die Zahlen- und Zeichenebene.
  final List<List<String>> zeichen;
}

class _SecureKeyboardState extends State<SecureKeyboard> {
  /// Groß-/Kleinschreibung (nur in der Buchstabenebene).
  bool _upperCase = false;

  /// Zahlen- und Zeichenebene.
  bool _symbols = false;

  /// Emoji-Auswahl.
  bool _emoji = false;

  /// Deutsche QWERTZ-Belegung: das "y" steht unten, das "z" oben.
  ///
  /// Die Umlaute liegen bei der deutschen Tastatur auf eigenen Tasten -
  /// deshalb sind sie hier auch eigene Tasten und nicht irgendein
  /// Sonderzeichen-Menü.
  static const _Belegung _qwertz = _Belegung(
    buchstaben: <List<String>>[
      <String>['q', 'w', 'e', 'r', 't', 'z', 'u', 'i', 'o', 'p'],
      <String>['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      <String>['y', 'x', 'c', 'v', 'b', 'n', 'm'],
    ],
    extra: <String>['ä', 'ö', 'ü', 'ß'],
    zeichen: <List<String>>[
      <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
      <String>['!', '"', '§', r'$', '%', '&', '/', '(', ')', '='],
      <String>['?', '@', '€', '+', '-', '*', '_', ',', '.'],
    ],
  );

  /// Englische QWERTY-Belegung: das "z" steht unten, das "y" oben.
  static const _Belegung _qwerty = _Belegung(
    buchstaben: <List<String>>[
      <String>['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
      <String>['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
      <String>['z', 'x', 'c', 'v', 'b', 'n', 'm'],
    ],
    extra: <String>[',', '.', "'", '-'],
    zeichen: <List<String>>[
      <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
      <String>['!', '"', '#', r'$', '%', '&', "'", '(', ')', '*'],
      <String>['+', '_', ':', ';', '=', '?', '@', '\\', '|', '~'],
    ],
  );

  /// Die Farben der Tastatur (0.11.0).
  ///
  /// DER WEG: "Wie die App" nimmt die Flächenfarben des Themas (das
  /// heutige Verhalten), "in der Farbe der App" die Akzentfarbe der
  /// Farbwelt, "eigene Farbe" den selbst gewählten Ton. Der Text
  /// darauf muss in beiden Helligkeiten lesbar bleiben - darum wird
  /// er aus der Helligkeit der Fläche berechnet, nicht geraten.
  _TastaturFarben _farben(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stil = widget.stil;
    if (stil == null || stil == TastaturStil.wieApp) {
      return _TastaturFarben(
        hintergrund: scheme.surfaceContainer,
        taste: scheme.surfaceContainerHighest,
        aktiv: scheme.primaryContainer,
        text: scheme.onSurface,
        aktivText: scheme.onPrimaryContainer,
      );
    }
    final eigene = stil == TastaturStil.eigeneFarbe && widget.farbe != null;
    final flaeche = eigene ? Color(widget.farbe!) : scheme.primary;
    return _TastaturFarben(
      hintergrund: scheme.surfaceContainer,
      taste: flaeche,
      aktiv: flaeche,
      // DER KONTRAST: Auf einer dunklen Fläche braucht es einen hellen
      // Text und umgekehrt. Das rechnet die Helligkeit der Fläche -
      // geraten wäre hier ein Fehler, den der Nutzer sieht.
      text: _lesbarerText(flaeche),
      aktivText: _lesbarerText(flaeche),
    );
  }

  /// Der lesbare Text für eine Fläche (hell auf dunkel, dunkel auf hell).
  static Color _lesbarerText(Color flaeche) {
    final helligkeit = flaeche.computeLuminance();
    return helligkeit > 0.5 ? Colors.black87 : Colors.white;
  }

  /// Die Belegung, die gerade gilt (0.11.0).
  ///
  /// DER WEG: "Wie die App" folgt der Sprache der App; sonst zählt die
  /// eigene Wahl. Die Emoji-Auswahl und die Zahlenebene sind
  /// sprachneutral - die betrifft das nicht.
  SecureKeyboardLayout aktiveLayout(BuildContext context) {
    final wahl = widget.layout;
    if (wahl == TastaturBelegung.deutsch) {
      return SecureKeyboardLayout.qwertz;
    }
    if (wahl == TastaturBelegung.englisch) {
      return SecureKeyboardLayout.qwerty;
    }
    return SecureKeyboard.layoutFuerSprache(
      L10n.localeOf(context).languageCode,
    );
  }

  /// Das große Eszett gibt es nicht - "SS" wäre zwei Zeichen und
  /// würde den Text unlesbar machen. Der Buchstabe bleibt "ß".
  static String _gross(String zeichen) =>
      zeichen == 'ß' ? 'ß' : zeichen.toUpperCase();

  List<List<String>> _grossZeilen(List<List<String>> zeilen) =>
      zeilen.map((zeile) => zeile.map(_gross).toList()).toList();

  List<String> _grossKeys(List<String> tasten) => tasten.map(_gross).toList();

  /// Die häufigsten Emoji für den Chat.
  ///
  /// Ohne Emoji wäre der Chat um einiges steifer - sie gehören für
  /// eine Dating-App zum Schreiben dazu. Sie kommen aus dieser Liste
  /// und laufen wie alle anderen Zeichen direkt in den Text.
  static const List<String> _emojiListe = <String>[
    '😀',
    '😂',
    '🥰',
    '😍',
    '😘',
    '😊',
    '😉',
    '😎',
    '🤔',
    '😅',
    '🙃',
    '😇',
    '🥳',
    '😴',
    '🤗',
    '🤩',
    '😋',
    '😜',
    '🤤',
    '😭',
    '😢',
    '😡',
    '🤭',
    '🫠',
    '👍',
    '👎',
    '👏',
    '🙏',
    '💪',
    '👋',
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '💔',
    '💯',
    '🔥',
    '✨',
    '🎉',
    '🌹',
    '🍷',
    '☕',
    '🍕',
    '🎵',
    '👀',
    '💋',
    '🙌',
    '🤝',
    '🫶',
    '🎂',
  ];

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: children),
  );

  Widget _charCap(String c) => _KeyCap(
    label: c,
    farben: _farben,
    onTap: () => widget.onCharacter(c),
    child: Text(
      c,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: _farben(context).text,
      ),
    ),
  );

  Widget _actionCap({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool active = false,
  }) => _KeyCap(
    label: label,
    farben: _farben,
    onTap: onTap,
    active: active,
    child: Icon(icon, size: 20, color: _farben(context).text),
  );

  /// Die Emoji-Auswahl (feste Höhe, damit die Tastatur nicht wächst).
  Widget _emojiPanel(BuildContext context) => SizedBox(
    height: 168,
    child: GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        // Feste Zeilenhöhe statt Seitenverhältnis: sonst wäre eine
        // Zelle so breit wie das Gitter (132 Pixel) und die Auswahl
        // wäre unbrauchbar.
        mainAxisExtent: 40,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _emojiListe.length,
      itemBuilder: (context, i) {
        final zeichen = _emojiListe[i];
        return Semantics(
          button: true,
          label: zeichen,
          child: InkWell(
            onTap: () => widget.onCharacter(zeichen),
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Text(zeichen, style: const TextStyle(fontSize: 22)),
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    // Die Belegung: entweder die der Einstellung oder - wie bisher -
    // die der Sprache der App (Deutsch -> QWERTZ, Englisch -> QWERTY).
    final belegung = aktiveLayout(context) == SecureKeyboardLayout.qwertz
        ? _qwertz
        : _qwerty;

    if (_emoji) {
      // Die Emoji-Auswahl ersetzt die Buchstaben - unten bleibt die
      // Leiste mit Leertaste, Löschen und der Umschaltung zurück.
      rows.add(_emojiPanel(context));
    } else {
      final buchstaben = _upperCase
          ? _grossZeilen(belegung.buchstaben)
          : belegung.buchstaben;

      for (final zeile in buchstaben) {
        rows.add(_row(<Widget>[for (final z in zeile) _charCap(z)]));
      }

      if (_symbols) {
        for (final zeile in belegung.zeichen) {
          rows.add(_row(<Widget>[for (final z in zeile) _charCap(z)]));
        }
        rows.add(
          _row(<Widget>[
            _actionCap(
              icon: Icons.abc,
              label: L10n.t(context, 'keyboard.letters'),
              onTap: () => setState(() => _symbols = false),
            ),
            if (widget.onPaste != null)
              _actionCap(
                icon: Icons.content_paste_outlined,
                label: L10n.t(context, 'keyboard.paste'),
                onTap: widget.onPaste,
              ),
            _actionCap(
              icon: Icons.backspace_outlined,
              label: L10n.t(context, 'keyboard.backspace'),
              onTap: widget.onBackspace,
            ),
            _actionCap(
              icon: Icons.keyboard_return,
              label: L10n.t(context, 'keyboard.enter'),
              onTap: widget.onEnter,
            ),
          ]),
        );
      } else {
        rows.add(
          _row(<Widget>[
            _actionCap(
              icon: Icons.arrow_upward,
              label: L10n.t(context, 'keyboard.shift'),
              active: _upperCase,
              onTap: () => setState(() => _upperCase = !_upperCase),
            ),
            _actionCap(
              icon: Icons.numbers,
              label: L10n.t(context, 'keyboard.symbols'),
              onTap: () => setState(() => _symbols = true),
            ),
            for (final z
                in _upperCase ? _grossKeys(belegung.extra) : belegung.extra)
              _charCap(z),
            _actionCap(
              icon: Icons.backspace_outlined,
              label: L10n.t(context, 'keyboard.backspace'),
              onTap: widget.onBackspace,
            ),
            _actionCap(
              icon: Icons.keyboard_return,
              label: L10n.t(context, 'keyboard.enter'),
              onTap: widget.onEnter,
            ),
          ]),
        );
      }
    }

    rows.add(
      _row(<Widget>[
        _actionCap(
          icon: _emoji ? Icons.abc : Icons.emoji_emotions_outlined,
          label: L10n.t(
            context,
            _emoji ? 'keyboard.letters' : 'keyboard.emoji',
          ),
          active: _emoji,
          onTap: () => setState(() => _emoji = !_emoji),
        ),
        if (widget.onPaste != null)
          _actionCap(
            icon: Icons.content_paste_outlined,
            label: L10n.t(context, 'keyboard.paste'),
            onTap: widget.onPaste,
          ),
        if (widget.onHide != null)
          _actionCap(
            icon: Icons.keyboard_hide_outlined,
            label: L10n.t(context, 'keyboard.hide'),
            onTap: widget.onHide,
          ),
        _KeyCap(
          flex: 4,
          label: L10n.t(context, 'keyboard.space'),
          farben: _farben,
          onTap: () => widget.onCharacter(' '),
          child: Text(
            L10n.t(context, 'keyboard.space'),
            style: TextStyle(fontSize: 14, color: _farben(context).text),
          ),
        ),
      ]),
    );

    return Material(
      color: _farben(context).hintergrund,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}

/// Die Farben der Tastatur (0.11.0).
///
/// DER WEG: Die Tastatur holt ihre Farben nicht selbst aus dem Theme -
/// sie bekommt sie von oben (der Einstellung). So verändert sie das
/// Theme der anderen Bildschirme nicht.
class _TastaturFarben {
  const _TastaturFarben({
    required this.hintergrund,
    required this.taste,
    required this.aktiv,
    required this.text,
    required this.aktivText,
  });

  /// Der Hintergrund der Tastatur.
  final Color hintergrund;

  /// Die Farbe einer Taste.
  final Color taste;

  /// Die Farbe einer aktiven Taste (Umschaltung).
  final Color aktiv;

  /// Der Text auf den Tasten.
  final Color text;

  /// Der Text auf einer aktiven Taste.
  final Color aktivText;
}

/// Eine einzelne Taste. Die [flex] bestimmt, wie breit sie wird
/// (die Leertaste ist breiter als ein Buchstabe).
class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.child,
    required this.onTap,
    required this.label,
    required this.farben,
    this.flex = 1,
    this.active = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Vorlesetext für den Screenreader (Barrierefreiheit).
  final String label;

  final int flex;

  /// Hervorgehobene Taste (aktive Umschaltung).
  final bool active;

  /// Die Farben der Tastatur (kommen von oben - die Tastatur hängt
  /// sich nicht selbst um).
  final _TastaturFarben Function(BuildContext context) farben;

  @override
  Widget build(BuildContext context) {
    final palette = farben(context);
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Material(
            color: active ? palette.aktiv : palette.taste,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
