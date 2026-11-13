import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:thestia/utils/best_effort.dart';
import 'package:thestia/widgets/secure_keyboard.dart';

/// Eingabeleiste fuer private Nachrichten - mit der eigenen Tastatur der
/// App (v0.10.1).
///
/// **Der Kern:** Das Textfeld steht auf `readOnly`. Auf Android und iOS
/// entsteht bei einem `readOnly`-Feld keine Eingabeverbindung zur
/// Systemtastatur - es gibt also nichts, was sie sehen koennte. Die
/// Zeichen kommen stattdessen aus der eigenen Tastatur
/// ([SecureKeyboard]) und gehen direkt in den Controller.
///
/// **Was sonst noch passiert:**
/// * Die eigene Tastatur oeffnet sich, wenn man das Feld antippt (und
///   sie ist ueber eine Taste auch wieder zuklappbar).
/// * Eine **Hardwaretastatur** (Tablet mit Tastaturhuelle) funktioniert
///   weiterhin: die Tastenereignisse werden hier abgefangen und
///   eingefuegt. Auch dabei laeuft nichts ueber die Systemtastatur.
/// * **Einfuegen** aus der Zwischenablage gibt es als eigene Taste -
///   mit `readOnly` waere es sonst deaktiviert.
class SecureComposer extends StatefulWidget {
  const SecureComposer({
    required this.controller,
    required this.onSend,
    this.hintText,
    this.leading = const <Widget>[],
    this.sendIcon = Icons.send,
    this.sendEnabled = true,
    this.showSendSpinner = false,
    this.maxLines = 5,
    this.minLines = 1,
    this.enterSends = false,
    this.padding = const EdgeInsets.all(12),
    super.key,
  });

  /// Der Controller des Aufrufers (der Screen besitzt ihn, damit er
  /// senden und leeren kann).
  final TextEditingController controller;

  /// Nachricht absenden.
  final VoidCallback onSend;

  /// Platzhalter im Eingabefeld.
  final String? hintText;

  /// Tasten vor dem Eingabefeld (Bild, Mikrofon, ...).
  final List<Widget> leading;

  /// Symbol der Senden-Taste.
  final IconData sendIcon;

  /// Ist die Senden-Taste aktiv?
  final bool sendEnabled;

  /// Ladekreis statt der Senden-Taste (während ein Bild hochlaedt).
  final bool showSendSpinner;

  /// Mehrzeilig wachsend (wie WhatsApp/Telegram).
  final int maxLines;

  /// Mindestzahl der Zeilen.
  final int minLines;

  /// Enter sendet (statt einen Umbruch einzufuegen).
  final bool enterSends;

  /// Innenabstand der Leiste.
  final EdgeInsets padding;

  @override
  State<SecureComposer> createState() => _SecureComposerState();
}

class _SecureComposerState extends State<SecureComposer> {
  final FocusNode _focus = FocusNode();
  bool _keyboardOpen = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Zeichen an der Cursor-Position einfuegen (ersetzt eine Auswahl).
  void _insert(String text) {
    final value = widget.controller.value;
    var start = value.selection.start;
    var end = value.selection.end;
    if (!value.selection.isValid || start < 0 || end < 0) {
      // Kein Cursor (z. B. direkt nach `clear()`) - dann wird angehaengt.
      start = value.text.length;
      end = value.text.length;
    }
    if (start > end) {
      final tausch = start;
      start = end;
      end = tausch;
    }
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
  }

  /// Das Zeichen vor dem Cursor loeschen.
  void _backspace() {
    final value = widget.controller.value;
    if (value.text.isEmpty) return;
    var start = value.selection.start;
    var end = value.selection.end;
    if (!value.selection.isValid || start < 0 || end < 0) {
      start = value.text.length - 1;
      end = value.text.length;
    }
    if (start == end) {
      if (start == 0) return;
      start = start - 1;
    }
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
      composing: TextRange.empty,
    );
  }

  /// Text aus der Zwischenablage einfuegen.
  ///
  /// Die Zwischenablage wird direkt gelesen - die Systemtastatur ist
  /// daran nicht beteiligt und sieht nichts.
  Future<void> _paste() async {
    final text = await bestEffortOr<String?>('Zwischenablage lesen', () async {
      final daten = await Clipboard.getData(Clipboard.kTextPlain);
      return daten?.text;
    }, null);
    // Ist die Zwischenablage nicht lesbar (seltener Sonderfall auf
    // Android), tippt der Nutzer den Text eben von Hand.
    if (text == null || text.isEmpty || !mounted) return;
    _insert(text);
  }

  /// Enter: senden oder Umbruch.
  void _enter() {
    if (widget.enterSends) {
      widget.onSend();
    } else {
      _insert('\n');
    }
  }

  /// Hardwaretastatur: die Zeichen kommen als Tastenereignis an, nicht
  /// ueber die Systemtastatur. Deshalb werden sie hier eingefuegt.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _enter();
      return KeyEventResult.handled;
    }
    final zeichen = event.character;
    if (zeichen != null && zeichen.length == 1) {
      final code = zeichen.codeUnitAt(0);
      // Steuerzeichen (Steuerung, Escape, ...) sind keine Eingabe.
      if (code >= 32 && code != 127) {
        _insert(zeichen);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _openKeyboard() {
    if (_keyboardOpen) return;
    setState(() => _keyboardOpen = true);
  }

  void _closeKeyboard() {
    if (!_keyboardOpen) return;
    setState(() => _keyboardOpen = false);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final sendetaste = widget.showSendSpinner
        ? const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : IconButton.filled(
            onPressed: widget.sendEnabled ? widget.onSend : null,
            icon: Icon(widget.sendIcon),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SafeArea(
          child: Padding(
            padding: widget.padding,
            child: Row(
              children: <Widget>[
                ...widget.leading,
                Expanded(
                  child: Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      // DIE entscheidende Zeile: ein `readOnly`-Feld
                      // erzeugt auf Android und iOS keine
                      // Eingabeverbindung - die Systemtastatur sieht
                      // damit nichts. `TextInputType.none` ist die
                      // zweite Sicherung fuer die Plattformen, auf
                      // denen es eine Verbindung gibt.
                      readOnly: true,
                      keyboardType: TextInputType.none,
                      enableIMEPersonalizedLearning: false,
                      autocorrect: false,
                      enableSuggestions: false,
                      showCursor: true,
                      maxLines: widget.maxLines,
                      minLines: widget.minLines,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onTap: () {
                        _focus.requestFocus();
                        _openKeyboard();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                sendetaste,
              ],
            ),
          ),
        ),
        if (_keyboardOpen)
          SecureKeyboard(
            onCharacter: _insert,
            onBackspace: _backspace,
            onEnter: _enter,
            onHide: _closeKeyboard,
            onPaste: _paste,
          ),
      ],
    );
  }
}
