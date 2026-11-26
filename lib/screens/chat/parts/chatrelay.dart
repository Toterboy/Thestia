// Die Methoden '_ChatRelay'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../chat_detail_screen.dart';

extension _ChatRelay on _ChatDetailScreenState {
  /// Holt E2E-verschlüsselte Relay-Nachrichten des Partners ab (Fallback,
  /// wenn P2P nicht zustande kam) und hängt sie in den Verlauf.
  Future<void> _fetchRelay() async {
    var match =
        _match ?? ref.read(chatProvider.notifier).getMatchById(widget.matchId);

    // BEFUND (09.11.2026): "Nachrichten kommen nicht richtig an. Eine
    // Benachrichtigung gab es aber ich sehe die Nachricht nicht."
    //
    // DER GRUND: `match` kommt aus dem LOKALEN Chat-Speicher. Für
    // einen Server-Funke (Interessen-Screen) gibt es dieses lokale
    // Match erst, wenn `_ensureLocalMatch()` es angelegt hat. Fehlt es
    // (Chat direkt aus einer Benachrichtigung geöffnet, Server-RPC
    // noch nicht durch), brach der Abruf hier komplett ab
    // (`if (match == null) return;`) - und die Nachricht blieb im Relay
    // liegen: für den Nutzer unsichtbar, obwohl die Benachrichtigung
    // ankam.
    //
    // JETZT: Fehlt das lokale Match, wird es einmalig vom Server
    // geholt (derselbe Pfad, den der Chat-Screen ohnehin nutzt).
    if (match == null) {
      await _ensureLocalMatch();
      if (!mounted) return;
      match = ref.read(chatProvider.notifier).getMatchById(widget.matchId);
    }
    if (!mounted) return;
    if (!SupabaseService.isInitialized) return;
    // Ohne Partner können wir die Zeile nicht zuordnen. Wir holen
    // sie dann NICHT - fremde Zeilen bleiben für ihren eigenen Chat
    // liegen (kein Datenverlust, und nichts wird fälschlich
    // bestätigt).
    final partnerId = match?.partner.id;
    if (partnerId == null) return;

    try {
      // Nur Zeilen DIESES Partners abholen/bestätigen - fremde warten
      // unangetastet auf ihren eigenen Chat (RelayService.fetchPending).
      final pending = await ref
          .read(relayServiceProvider)
          .fetchPending(from: partnerId);
      if (!mounted) return;
      var added = false;
      for (final r in pending) {
        if (r.senderId != partnerId) continue;
        // DIE HULLE auspacken (BEFUND 11.11.2026): Die Nachrichten-ID
        // kommt vom SENDER - damit ist sie auf beiden Seiten gleich
        // (Grundlage für "für alle löschen"). Eine Nachricht ohne
        // Hülle (alte App) bekommt wie bisher eine lokale ID.
        final draht = parseEnvelope(r.text);
        final msgId = draht.fromNewFormat ? draht.id : 'relay_${r.id}';
        if (_seenMessageIds.contains(msgId)) continue;
        _seenMessageIds.add(msgId);
        final msg = Message(
          id: msgId,
          senderId: r.senderId,
          receiverId: _myUserId ?? AppConstants.currentUserId,
          text: draht.text,
          timestamp: r.createdAt,
          type: draht.fromNewFormat
              ? (draht.kind == WireKind.icebreaker
                    ? MessageType.icebreaker
                    : MessageType.text)
              : (r.kind == 'icebreaker'
                    ? MessageType.icebreaker
                    : MessageType.text),
        );
        ref
            .read(chatProvider.notifier)
            .addMessage(match?.id ?? widget.matchId, msg, ref: ref);
        added = true;
      }
      // Die "für alle gelöscht"-Hinweise (BEFUND 11.11.2026) - auch
      // zwischendurch, damit sie im laufenden Gespräch ankommen.
      await _applyMessageDeletions(widget.matchId);
      if (added) {
        // Zustellung lief -> Intervall wieder auf Ausgangswert.
        _relayBackoffStep = 0;
        if (mounted) _setzeState(() {});
      }
    } catch (e) {
      debugPrint('[ChatDetail] Relay-Abruf fehlgeschlagen: $e');
    }
  }

  /// Versucht den P2P-Handshake erneut, solange keine direkte Verbindung
  /// besteht (Initiator sendet Re-Offer, sonst voller Neuaufbau).
  /// Läuft nur im geöffneten Chat im Vordergrund und ist auf max. einen
  /// Versuch alle 25 Sekunden gedrosselt (Akku).
  Future<void> _retryHandshakeThrottled() async {
    if (_p2pConnected || _p2p == null || !mounted) return;
    if (!SupabaseService.isInitialized) return;
    final match = _match;
    final myId = _myUserId;
    if (match == null || myId == null) return;
    final now = DateTime.now();
    if (_lastHandshakeRetry != null &&
        now.difference(_lastHandshakeRetry!) < const Duration(seconds: 25)) {
      return;
    }
    _lastHandshakeRetry = now;
    try {
      await _p2p!.ensureConnected(myUserId: myId, peerId: match.partner.id);
    } catch (e) {
      // Still - nächster Timer-Takt versucht es erneut. Fehler für die
      // Diagnose-Zeile merken.
      if (mounted) {
        _setzeState(
          () => _lastP2pError = _ChatDetailScreenState._shortError(e),
        );
      }
      return;
    }
    if (!mounted) return;
    final open = _p2p?.isConnected ?? false;
    if (open != _p2pConnected || (open && _lastP2pError != null)) {
      _setzeState(() {
        _p2pConnected = open;
        if (open) _lastP2pError = null;
      });
    }
  }

  void _startRelayTimer() {
    _relayTimer?.cancel();
    _relayTimer = null;
    if (!mounted) return;
    final step = _relayBackoffStep.clamp(
      0,
      _ChatDetailScreenState._relayIntervals.length - 1,
    );
    _relayTimer = Timer(_ChatDetailScreenState._relayIntervals[step], () async {
      if (!mounted) return;
      final before = _relayBackoffStep;
      await _fetchRelay();
      if (!mounted) return;
      // Leerer Abruf -> eine Stufe langsamer, Timer neu aufsetzen.
      if (_relayBackoffStep == before &&
          _relayBackoffStep <
              _ChatDetailScreenState._relayIntervals.length - 1) {
        _relayBackoffStep++;
      }
      unawaited(_retryHandshakeThrottled());
      _startRelayTimer();
    });
  }
}
