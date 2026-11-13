import 'package:flutter/material.dart';

import 'package:thestia/l10n/app_strings.dart';

/// Die eigene Bildschirmtastatur der App (v0.10.1).
///
/// **Der Wunsch des Betreibers (13.11.2026):** "dass die Handytastatur
/// nicht tracken kann was man schreibt. Das soll ja irgendwie gehen
/// koennen anscheinend".
///
/// **Was das Problem ueberhaupt ist:** Die Systemtastatur (Gboard,
/// SwiftKey, ...) ist ein eigenes Programm auf dem Geraet. Sie sieht
/// jeden Buchstaben, den man tippt, und darf daraus lernen - das
/// Wörterbuch, die Autokorrektur, die personalisierten Vorschlaege. Auf
/// einem Geraet, das man nicht besitzt (Fremdgeraet, Secondhand,
/// manipulierte ROM) ist das nicht aufhaltbar - und "es ist nur die
/// Tastatur" ist keine Antwort, wenn man der anderen Person nicht
/// vertraut.
///
/// **Was hier dagegen steht:** Die Zeichen laufen vom Tasten-Widget
/// direkt in den Textcontroller. Die Systemtastatur wird gar nicht erst
/// geoeffnet: Das Textfeld steht auf `readOnly`, und auf Android und iOS
/// entsteht bei einem `readOnly`-Feld ueberhaupt keine Eingabeverbindung
/// (`_shouldCreateInputConnection` ist dort `false`). Es gibt damit
/// nichts, was die Systemtastatur sehen koennte - nicht den getippten
/// Text, nicht einzelne Zeichen, nicht den Cursor.
///
/// **Was das NICHT ist - ehrlich gesagt:**
/// * Das gilt fuer die **Zeichen**. Alles, was sichtbar auf dem
///   Bildschirm steht, kann auch ein Zugriff auf das Display abgreifen.
///   Dagegen steht die Screenshot-Sperre (`FLAG_SECURE`), die die App
///   bereits auf allen Bildschirmen setzt.
/// * Es schuetzt nicht davor, dass jemand **ueber die Schulter** liest.
/// * Ein **gerootetes** Geraet ist pauschal nicht mehr zu retten.
///
/// **Ehrliche Grenze der Plattform:** Auf iOS gibt es zu
/// `enableIMEPersonalizedLearning` (Android) keine Entsprechung - dort
/// wirkt nur `autocorrect: false` + `enableSuggestions: false`. Der Weg
/// ueber die eigene Tastatur ist deshalb der einzige, der auf BEIDEN
/// Plattformen dasselbe verspricht - und deshalb der, den die App geht.
class SecureKeyboard extends StatefulWidget {
  const SecureKeyboard({
    required this.onCharacter,
    required this.onBackspace,
    this.onEnter,
    this.onHide,
    this.onPaste,
    super.key,
  });

  /// Ein einzelnes Zeichen (Buchstabe, Ziffer, Satzzeichen, Leerzeichen).
  final void Function(String character) onCharacter;

  /// Backspace.
  final VoidCallback onBackspace;

  /// Enter. Ohne Callback wird die Taste als inaktiv gezeigt.
  final VoidCallback? onEnter;

  /// Tastatur ausblenden (der Nutzer will zurueck in den Chat).
  final VoidCallback? onHide;

  /// Einfuegen aus der Zwischenablage.
  ///
  /// Der Umweg ueber die Systemtastatur ist hier nicht moeglich: mit
  /// `readOnly` ist das Einfuegen deaktiviert. Der Text kommt deshalb
  /// direkt aus der Zwischenablage der App - die Systemtastatur sieht
  /// dabei nichts.
  final VoidCallback? onPaste;

  @override
  State<SecureKeyboard> createState() => _SecureKeyboardState();
}

class _SecureKeyboardState extends State<SecureKeyboard> {
  /// Gross-/Kleinschreibung (nur in der Buchstabenebene).
  bool _upperCase = false;

  /// Zahlen- und Zeichenebene.
  bool _symbols = false;

  /// Emoji-Auswahl.
  bool _emoji = false;

  /// Deutsche QWERTZ-Belegung.
  static const List<List<String>> _letterRows = <List<String>>[
    <String>['q', 'w', 'e', 'r', 't', 'z', 'u', 'i', 'o', 'p'],
    <String>['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    <String>['y', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  static const List<List<String>> _symbolRows = <List<String>>[
    <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    <String>['!', '"', '§', r'$', '%', '&', '/', '(', ')', '='],
    <String>['?', '@', '€', '+', '-', '*', '_', ',', '.'],
  ];

  /// Die Umlaute liegen bei der deutschen Tastatur auf eigenen Tasten -
  /// deshalb sind sie hier auch eigene Tasten und nicht irgendein
  /// Sonderzeichen-Menue.
  static const List<String> _umlauts = <String>['ä', 'ö', 'ü', 'ß'];

  List<List<String>> get _charRows {
    if (_symbols) return _symbolRows;
    if (!_upperCase) return _letterRows;
    return _letterRows
        .map((row) => row.map((c) => c.toUpperCase()).toList())
        .toList();
  }

  List<String> get _umlautKeys {
    if (!_upperCase) return _umlauts;
    // Das grosse Eszett gibt es nicht - "SS" waere zwei Zeichen und
    // wuerde den Text unlesbar machen. Der Buchstabe bleibt "ß".
    return <String>['Ä', 'Ö', 'Ü', 'ß'];
  }

  /// Die haeufigsten Emoji fuer den Chat.
  ///
  /// Ohne Emoji waere der Chat um einiges steifer - sie gehoeren fuer
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
    onTap: () => widget.onCharacter(c),
    child: Text(
      c,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
    ),
  );

  Widget _actionCap({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool active = false,
  }) => _KeyCap(
    label: label,
    onTap: onTap,
    active: active,
    child: Icon(icon, size: 20),
  );

  /// Die Emoji-Auswahl (feste Hoehe, damit die Tastatur nicht wächst).
  Widget _emojiPanel(BuildContext context) => SizedBox(
    height: 168,
    child: GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        // Feste Zeilenhoehe statt Seitenverhaeltnis: sonst waere eine
        // Zelle so breit wie das Gitter (132 Pixel) und die Auswahl
        // waere unbrauchbar.
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

    if (_emoji) {
      // Die Emoji-Auswahl ersetzt die Buchstaben - unten bleibt die
      // Leiste mit Leertaste, Löschen und der Umschaltung zurück.
      rows.add(_emojiPanel(context));
    } else {
      for (final row in _charRows) {
        rows.add(_row(<Widget>[for (final c in row) _charCap(c)]));
      }

      if (_symbols) {
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
            for (final c in _umlautKeys) _charCap(c),
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
          onTap: () => widget.onCharacter(' '),
          child: Text(
            L10n.t(context, 'keyboard.space'),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ]),
    );

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
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

/// Eine einzelne Taste. Die [flex] bestimmt, wie breit sie wird
/// (die Leertaste ist breiter als ein Buchstabe).
class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.child,
    required this.onTap,
    required this.label,
    this.flex = 1,
    this.active = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Vorlesetext fuer den Screenreader (Barrierefreiheit).
  final String label;

  final int flex;

  /// Hervorgehobene Taste (aktive Umschaltung).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Material(
            color: active
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
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
