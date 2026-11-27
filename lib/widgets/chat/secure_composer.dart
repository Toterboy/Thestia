import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:thestia/l10n/app_strings.dart';
import 'package:thestia/models/settings/tastatur_einstellungen.dart';
import 'package:thestia/providers/settings/settings_provider.dart';
import 'package:thestia/utils/common/best_effort.dart';
import 'package:thestia/widgets/chat/secure_keyboard.dart';

/// Eingabeleiste für private Nachrichten - mit der eigenen Tastatur der
/// App (v0.10.1).
///
/// **Der Kern:** Das Textfeld steht auf `readOnly`. Auf Android und iOS
/// entsteht bei einem `readOnly`-Feld keine Eingabeverbindung zur
/// Systemtastatur - es gibt also nichts, was sie sehen kännte. Die
/// Zeichen kommen stattdessen aus der eigenen Tastatur
/// ([SecureKeyboard]) und gehen direkt in den Controller.
///
/// **Was sonst noch passiert:**
/// * Die eigene Tastatur öffnet sich, wenn man das Feld antippt (und
///   sie ist über eine Taste auch wieder zuklappbar).
/// * Eine **Hardwaretastatur** (Tablet mit Tastaturhülle) funktioniert
///   weiterhin: die Tastenereignisse werden hier abgefangen und
///   eingefügt. Auch dabei läuft nichts über die Systemtastatur.
/// * **Einfügen** aus der Zwischenablage gibt es als eigene Taste -
///   mit `readOnly` wäre es sonst deaktiviert.
class SecureComposer extends ConsumerStatefulWidget {
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
    this.layout,
    this.stil,
    this.farbe,
    super.key,
  });

  /// Die Belegung der eigenen Tastatur (0.11.0).
  ///
  /// Null bedeutet "wie die App" - dann folgt die Belegung der Sprache
  /// der App. Gesetzt zwingt sie eine Belegung (QWERTZ oder QWERTY).
  final TastaturBelegung? layout;

  /// Der Farbstil der eigenen Tastatur (0.11.0).
  ///
  /// Null bedeutet "wie die App" - dann kommen die Farben aus dem
  /// App-Thema.
  final TastaturStil? stil;

  /// Die eigene Farbe der Tastatur (0.11.0) als ARGB-Zahl.
  final int? farbe;

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

  /// Ladekreis statt der Senden-Taste (während ein Bild hochlädt).
  final bool showSendSpinner;

  /// Mehrzeilig wachsend (wie WhatsApp/Telegram).
  final int maxLines;

  /// Mindestzahl der Zeilen.
  final int minLines;

  /// Enter sendet (statt einen Umbruch einzufügen).
  final bool enterSends;

  /// Innenabstand der Leiste.
  final EdgeInsets padding;

  @override
  ConsumerState<SecureComposer> createState() => _SecureComposerState();
}

class _SecureComposerState extends ConsumerState<SecureComposer> {
  final FocusNode _focus = FocusNode();
  bool _keyboardOpen = false;

  /// Die System-Tastatur statt der eigenen benutzen?
  ///
  /// NUTZERWUNSCH (27.11.2026): "Außerdem soll man zwischen der system
  /// und app tastatur auch wechseln können."
  ///
  /// DER WEG: Die eigene Tastatur ist der Default - sie sieht keinen
  /// einzigen Buchstaben der Systemtastatur. Wer trotzdem die
  /// Systemtastatur will (etwa für die Autokorrektur des Systems),
  /// tippt auf den kleinen Knopf neben dem Eingabefeld.
  bool _systemTastatur = false;

  /// Zwischen der eigenen und der System-Tastatur wechseln.
  void _wechseleTastatur() {
    setState(() {
      _systemTastatur = !_systemTastatur;
      if (_systemTastatur) {
        // Die eigene Tastatur verschwindet, die System-Tastatur kommt.
        _keyboardOpen = false;
        _focus.requestFocus();
      } else {
        // Zurück zur eigenen Tastatur: das Feld verliert kurz den
        // Fokus (das schließt die System-Tastatur) und bekommt ihn
        // wieder - ohne Eingabeverbindung gibt es keine Systemtastatur.
        _focus.unfocus();
        _focus.requestFocus();
        _openKeyboard();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Zeichen an der Cursor-Position einfügen (ersetzt eine Auswahl).
  void _insert(String text) {
    final value = widget.controller.value;
    var start = value.selection.start;
    var end = value.selection.end;
    if (!value.selection.isValid || start < 0 || end < 0) {
      // Kein Cursor (z. B. direkt nach `clear()`) - dann wird angehängt.
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

  /// Das Zeichen vor dem Cursor löschen.
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

  /// Text aus der Zwischenablage einfügen.
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
  /// über die Systemtastatur. Deshalb werden sie hier eingefügt.
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

    // DIE EINSTELLUNGEN DER TASTATUR (0.11.0).
    //
    // BEFUND (27.11.2026, Betreiber): "Die eigene Tastatur wird nicht
    // überall angewendet." Ursache: Die drei Werte (Belegung, Stil,
    // Farbe) mussten an jeder Stelle durchgereicht werden - im
    // Dating-Hour-Chat fehlten sie, dort galt immer der Standard.
    //
    // DER WEG: Der Composer holt sie selbst. Damit kann keine neue
    // Stelle sie vergessen - und wer sie doch einmal anders will,
    // gibt sie als Parameter mit (der Parameter hat Vorrang).
    final settings = ref.watch(settingsProvider);
    final layout =
        widget.layout ??
        TastaturBelegungWert.ausWert(settings.tastaturBelegung);
    final stil = widget.stil ?? TastaturStilWert.ausWert(settings.tastaturStil);
    final farbe = widget.farbe ?? settings.tastaturFarbe;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SafeArea(
          child: Padding(
            padding: widget.padding,
            child: Row(
              children: <Widget>[
                // DER KNOPF FÜR DIE TASTATUR (27.11.2026): Er steht
                // immer da - die eigene Tastatur ist der Default, aber
                // wer die Systemtastatur will, muss jederzeit dorthin
                // wechseln können.
                IconButton(
                  // Das Ziel: die gefüllte Taste steht für die eigene
                  // Tastatur der App, die offene für die des Systems.
                  icon: Icon(
                    _systemTastatur ? Icons.keyboard : Icons.keyboard_outlined,
                  ),
                  tooltip: L10n.t(
                    context,
                    _systemTastatur
                        ? 'chat.keyboardToApp'
                        : 'chat.keyboardToSystem',
                  ),
                  onPressed: _wechseleTastatur,
                ),
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
                      // zweite Sicherung für die Plattformen, auf
                      // denen es eine Verbindung gibt.
                      //
                      // AUSNAHME (27.11.2026): Wer ausdrücklich auf die
                      // System-Tastatur umschaltet, braucht eine
                      // Eingabeverbindung - dann ist das Feld normal
                      // beschreibbar.
                      readOnly: !_systemTastatur,
                      // `multiline` passt zum Feld (es wächst mit) und
                      // zur Enter-Taste (sie setzt einen Umbruch).
                      keyboardType: _systemTastatur
                          ? TextInputType.multiline
                          : TextInputType.none,
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
                        // In der System-Tastatur ist die eigene zu.
                        if (!_systemTastatur) _openKeyboard();
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
        // DIE EINFUG-ANIMATION (27.11.2026): Die Tastatur fährt von
        // unten ein, statt einfach da zu sein. Das ist einer der
        // Unterschiede zur Systemtastatur - die fährt ebenfalls auf.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: _keyboardOpen && !_systemTastatur
              ? SecureKeyboard(
                  layout: layout,
                  stil: stil,
                  farbe: farbe,
                  onCharacter: _insert,
                  onBackspace: _backspace,
                  onEnter: _enter,
                  onHide: _closeKeyboard,
                  onPaste: _paste,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
