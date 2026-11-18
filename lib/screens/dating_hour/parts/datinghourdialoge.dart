// Die Methoden '_DatingHourDialoge'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unveraendert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

extension _DatingHourDialoge on _DatingHourChatScreenState {
  Widget _buildOutcomeBanner(DatingHourSession session) {
    // DER UMBRUCH (18.11.2026, gefunden von einem Test): Der Text stand
    // in einer festen Reihe - bei grosser Schrift (oder einer
    // System-Schriftgroesse ueber 100 %) lief er ueber den Rand.
    //
    // DER WEG: "Flexible" laesst den Text umbrechen, statt zu
    // ueberlaufen. Und der Text kommt aus den Uebersetzungen (vorher
    // stand er fest in Deutsch da - in der englischen Fassung stand
    // trotzdem Deutsch).
    if (session.isMutualMatch) {
      return Container(
        width: double.infinity,
        color: Colors.green,
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                L10n.t(context, 'dh.chat.bannerMatch'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      color: Colors.orange,
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_border, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              L10n.t(context, 'dh.chat.bannerNoMatch'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t(ctx, 'dh.chat.leaveTitle')),
        content: Text(L10n.t(ctx, 'dh.chat.leaveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t(context, 'dh.chat.stay')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleDecision(false); // Verlassen = Ablehnen
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(L10n.t(context, 'dh.chat.leaveDecline')),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _getDefaultRejectionMessage() {
    const messages = [
      'Diese Verbindung hat leider nicht ganz gepasst. Aber keine Sorge, das sagt nichts über dich aus! Wir suchen gleich jemand Neues für dich.',
      'Manchmal funkt es einfach nicht, und das ist völlig okay! Dein nächster Funke wartet schon.',
      'Nicht jede Begegnung führt zum Funken. Aber jeder Chat bringt dich näher an die richtige Person. Weiter so!',
      'Schade, dass es nicht gepasst hat. Aber hey: Du hast dich getraut, dich zu zeigen! Das nächste Gespräch kommt bestimmt.',
    ];
    return messages[DateTime.now().millisecondsSinceEpoch % messages.length];
  }

  void _showDecisionDialog() {
    _setzeState(() => _showDecision = true);
  }

  void _showRejectionMessage(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.favorite_border,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            // DER UMBRUCH (18.11.2026, gefunden von einem Test): Die
            // Ueberschrift stand neben dem Symbol in einer festen Reihe -
            // bei grosser Schrift (oder der breiten Test-Schrift im Test)
            // lief sie ueber den Rand.
            //
            // DER WEG: "Flexible" laesst die Ueberschrift umbrechen,
            // statt zu ueberlaufen.
            Flexible(child: Text(L10n.t(context, 'dh.chat.noSpark'))),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) context.go(AppRoutes.datingHourEvent);
            },
            child: Text(L10n.t(context, 'dh.chat.keepSearching')),
          ),
        ],
      ),
    );
  }

  /// Setzt den mittigen Hinweis in den Verlauf.
  ///
  /// Er ist ein Hinweis der App und keine Nachricht einer Person -
  /// er wird deshalb nicht gesendet und steht nur in diesem
  /// Verlauf. Beide Seiten sehen ihn zur selben Zeit (die Fuenf
  /// Minuten gelten fuer dieselbe Session).
  void _zeigeFuenfMinutenHinweis(DatingHourSession session) {
    final myId = _currentUserId;
    final peerId = _peerId;
    if (myId == null || peerId == null) return;

    // Nicht doppelt: steht der Hinweis schon im Verlauf (der Screen
    // wurde neu geoeffnet), bleibt er dort - es wird kein zweiter
    // eingefuegt.
    final vorhanden = ref
        .read(chatProvider.notifier)
        .messagesFor(widget.sessionId)
        .any((m) => m.type == MessageType.notice);
    if (vorhanden) return;

    final hinweis = Message(
      id: Message.newId('notice'),
      senderId: myId,
      receiverId: peerId,
      text: L10n.t(context, 'dh.chat.fiveMinutesDone'),
      timestamp: DateTime.now(),
      type: MessageType.notice,
    );
    ref
        .read(chatProvider.notifier)
        .addMessage(widget.sessionId, hinweis, ref: ref);
    if (mounted) _setzeState(() {});
  }
}
