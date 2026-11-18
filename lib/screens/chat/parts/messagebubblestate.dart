// Der Teil '_MessageBubbleState'.
//
// DER WEG: Die Datei war zu lang (> 1000 Zeilen). Der Teil
// ist ueber `part` mit der Hauptdatei verbunden - so bleiben
// die privaten Namen (und der Zugriff auf die privaten Felder)
// unveraendert.
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

class _MessageBubbleState extends State<_MessageBubble> {
  /// Vom Nutzer nach Warnung freigegebene Bilder (Session-lokal).
  bool _revealed = false;

  /// Bereits angesehene View-Once-Bilder (Session-lokal).
  /// Wird beim App-Neustart zurückgesetzt – das ist beabsichtigt,
  /// da der Sender die Kontrolle über die Einmaligkeit hat.
  static final Set<String> _viewedOnceIds = {};

  bool get _isViewOnceViewed =>
      _viewedOnceIds.contains(widget.msg.id) || widget.msg.viewed;

  void _markViewed() {
    _viewedOnceIds.add(widget.msg.id);
    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final msg = widget.msg;
    final color = mine
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = mine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;
    // Blur-Zustand einmal pro Build berechnen (siehe Bild-Zweig).
    final blurred = widget.blurEnabled && !widget.mine && !_revealed;

    return Column(
      crossAxisAlignment: widget.mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Absendername über der Bubble (nur Gruppenstart, Nutzerwunsch).
        if (widget.showName && widget.senderName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
            child: Text(
              widget.senderName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        GestureDetector(
          // BEFUND (11.11.2026): Long-Press auf eine eigene Textnachricht
          // bietet "Fuer alle loeschen" an (wie bei Whatsapp). Fremde
          // Nachrichten lassen sich nicht loeschen - das waere eine
          // Rechteausweitung.
          onLongPress: widget.onDelete == null
              ? null
              : () => _confirmDelete(context),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
            ),
            child: switch (msg.type) {
              MessageType.image =>
                _isViewOnceViewed && !widget.mine
                    ? _buildViewedOncePlaceholder(textColor)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Schutz vor unangemessenen Inhalten: Bilder der
                          // Gegenseite sind standardmäßig verpixelt (Einstellung
                          // "blurChatImages", Default an). Freigabe nur nach
                          // ausdrücklicher Bestätigung.
                          GestureDetector(
                            onTap: () {
                              if (blurred) {
                                _confirmRevealImage();
                                return;
                              }
                              if (widget.mine) {
                                _showFullscreenImage(context, msg);
                              } else if (msg.viewOnce) {
                                _showViewOnceImage(context, msg);
                              } else {
                                _showFullscreenImage(context, msg);
                              }
                            },
                            onLongPress: () =>
                                _showImageActions(context, blurred),
                            child: Semantics(
                              label: blurred
                                  ? L10n.t(context, 'chat.imageBlurredHint')
                                  : L10n.t(context, 'chat.imageHint'),
                              button: true,
                              child: Stack(
                                children: [
                                  // Nur wenn wirklich unscharf: ein ImageFiltered mit
                                  // sigma 0 erzeugt trotzdem einen Offscreen-Layer und
                                  // einen Filter-Pass - pro Bild-Bubble beim Scrollen.
                                  _ChatImage(
                                    mediaUrl: msg.mediaUrl ?? '',
                                    blurred: blurred,
                                  ),
                                  if (blurred)
                                    Positioned(
                                      bottom: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(6),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.visibility_off,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              L10n.t(context, 'chat.blurred'),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (msg.viewOnce)
                                    Positioned(
                                      top: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(6),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.lock,
                                              size: 12,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              L10n.t(context, 'chat.viewOnce'),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (msg.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                msg.text,
                                style: TextStyle(color: textColor),
                              ),
                            ),
                        ],
                      ),
              MessageType.voice => _VoiceMessage(
                msgId: msg.id,
                path: msg.mediaUrl ?? '',
                durationSeconds: msg.durationSeconds,
                textColor: textColor,
                mine: mine,
              ),
              _ => Text(msg.text, style: TextStyle(color: textColor)),
            },
          ),
        ),
        // Zeitanzeige unter der Bubble (Nutzerwunsch, dezent).
        if (widget._timeLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
            child: Text(
              widget._timeLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }

  /// Fragt nach, ob die Nachricht fuer alle geloescht werden soll.
  ///
  /// BEFUND (11.11.2026): "Wie bei Whatsapp - die Nachricht kann man
  /// irgendwie fuer alle loeschen, aber ein Hinweis steht dann da."
  Future<void> _confirmDelete(BuildContext context) async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'chat.deleteForAllTitle')),
        content: Text(L10n.t(ctx, 'chat.deleteForAllBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L10n.t(ctx, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L10n.t(ctx, 'chat.deleteForAllAction')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    onDelete(widget.msg);
  }

  /// Bestätigt das Entzerren eines verpixelten Bildes mit Warnhinweis.
  void _confirmRevealImage() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(context, 'chat.revealTitle')),
        content: Text(L10n.t(context, 'chat.revealBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(context, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _revealed = true);
            },
            child: Text(L10n.t(context, 'chat.revealAction')),
          ),
        ],
      ),
    );
  }

  /// Aktionsmenü für Bilder: Melden und ggf. Freigeben.
  void _showImageActions(BuildContext context, bool blurred) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.red),
              title: Text(L10n.t(context, 'chat.reportImage')),
              subtitle: Text(L10n.t(context, 'chat.reportImageSub')),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                widget.onReportImage(widget.msg);
              },
            ),
            if (blurred)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(L10n.t(context, 'chat.revealAction')),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _confirmRevealImage();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Platzhalter für bereits angesehene View-Once-Bilder.
  Widget _buildViewedOncePlaceholder(Color textColor) {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade300,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera, size: 28, color: Colors.grey),
            const SizedBox(height: 4),
            Text(
              L10n.t(context, 'chat.viewedOnce'),
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// Zeigt ein View-Once-Bild im Vollbild – NUR EINMAL.
  /// Danach wird die Nachricht als "angesehen" markiert.
  void _showViewOnceImage(BuildContext context, Message msg) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        // BEFUND (09.11.2026, Betreiber): "Wenn Bild geöffnet und zurück
        // swipe, dann im Hintergrund zurück, aber Bild noch offen (Swipe
        // soll Bild schließen und nicht im Hintergrund weiter machen)."
        //
        // DER GRUND: `canPop: false` hat jeden Pop VERBOTEN - auch den
        // Zurück-Wisch des Systems. Das Bild blieb stehen, während der
        // Hintergrund schon zurückging. Und der eigene `Navigator.pop()`
        // im Handler wurde von demselben Verbot wieder blockiert (er
        // loeste nur wieder den Handler aus).
        //
        // JETZT: Der Pop ist erlaubt. Das Bild wird beim Schließen als
        // gesehen markiert - es kann danach nicht wieder geöffnet
        // werden (das war der Zweck des Verbots).
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _markViewed();
        },
        child: Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: double.infinity,
                  height: 320,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple, Colors.blue],
                    ),
                  ),
                  child: _ChatImage(
                    mediaUrl: msg.mediaUrl ?? '',
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: 320,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        L10n.t(context, 'chat.viewOnce'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: L10n.t(context, 'chat.closeImageHint'),
                  onPressed: () {
                    _markViewed();
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// E: Vollbild-Ansicht des Bildes (Mock-Platzhalter mit Hinweis).
  void _showFullscreenImage(BuildContext context, Message msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SwipeToClose(
        child: Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: double.infinity,
                  height: 320,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple, Colors.blue],
                    ),
                  ),
                  child: _ChatImage(
                    mediaUrl: msg.mediaUrl ?? '',
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: 320,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
