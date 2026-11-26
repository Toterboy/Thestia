// Die Methoden '_DatingHourP2p'.
//
// DER WEG: Die Klasse war zu lang (> 1000 Zeilen). Die Methoden
// liegen in einer EXTENSION auf dieselbe Klasse - so haben sie
// weiterhin Zugriff auf die privaten Felder, und der Aufrufer
// bleibt unverändert (`_methode(...)` ist derselbe Name).
//
// Der Test `code_datei_groessen_test` verhindert, dass die
// Hauptdatei wieder zu lang wird.

part of '../dating_hour_chat_screen.dart';

extension _DatingHourP2p on _DatingHourChatScreenState {
  Future<void> _fetchRelay() async {
    final peerId = _peerId;
    if (peerId == null || peerId.isEmpty || !mounted) return;
    if (!SupabaseService.isInitialized) return;
    // Netzwerkfehler: nächster Timer-Takt versucht es erneut.
    await bestEffort('relayServiceProvider.fetchPending', () async {
      final pending = await ref
          .read(relayServiceProvider)
          .fetchPending(from: peerId);
      if (!mounted || pending.isEmpty) return;
      for (final r in pending) {
        final msgId = 'relay_${r.id}';
        if (_seenDhRelayIds.contains(msgId)) continue;
        _seenDhRelayIds.add(msgId);
        final msg = Message(
          id: msgId,
          senderId: peerId,
          receiverId: _currentUserId ?? '',
          text: r.text,
          timestamp: r.createdAt,
        );
        ref
            .read(chatProvider.notifier)
            .addMessage(widget.sessionId, msg, ref: ref);
      }
    });
  }

  Future<void> _handleDecision(bool accept) async {
    final session = _session;
    // Die eigene User-ID wird nur in _initP2P() gesetzt. Bricht das ohne
    // Supabase-Session früh ab, ist sie null - ein Tipp auf "Treffen" würde
    // dann mit einem Null-Check-Crash enden (User sähe einen roten Screen).
    final myId = _currentUserId;
    if (session == null || myId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.t(context, 'common.errorOccurred'))),
        );
      }
      return;
    }

    final service = ref.read(datingHourServiceProvider);
    try {
      final updated = await service.recordDecision(
        widget.sessionId,
        myId,
        accept,
      );

      if (updated != null && mounted) {
        _setzeState(() {
          _session = updated;
          _hasVoted = true;
          _showDecision = true;
        });
        _evaluateSessionOutcome();
      }
    } on DatingHourException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tf(context, 'common.errorWith', {'error': e.message}),
            ),
          ),
        );
      }
    }
  }

  /// Baut die E2E-P2P-Verbindung zum Chat-Partner auf (einmalig pro Screen).
  Future<void> _initP2P(DatingHourSession session) async {
    if (_p2pInitStarted) return;
    _p2pInitStarted = true;

    final p2p = ref.read(p2pChatServiceProvider);
    _p2p = p2p;

    // Eigene ID strikt aus der Supabase-Session (Fix): Stale Secure-Store-
    // oder Demo-Fallbacks ('me') erzeugen ein Signaling-Topic ohne die
    // echte auth.uid() -> RLS verweigert den Join, Nachrichten adressieren
    // den falschen Peer. Ohne Session: kein P2P, kein Relay.
    final myId = SupabaseService.currentUser?.id;
    if (myId == null || myId.isEmpty) {
      debugPrint('[DatingHourChat] Keine Supabase-Session - P2P übersprungen.');
      return;
    }
    _currentUserId = myId;
    final peerId = session.getPeerId(_currentUserId!);
    _peerId = peerId;
    // NUTZERWUNSCH: Notification-Unterdrückung (lokal + Server-Push)
    // solange dieser Chat sichtbar ist.
    _aktiveChatPeerId.state = peerId;

    // Eingehende (bereits entschlüsselte) Nachrichten in den Verlauf.
    _msgSub = p2p.incomingMessages.listen((text) {
      if (!mounted) return;
      final msg = Message(
        id: Message.newId('p2p'),
        senderId: peerId,
        receiverId: _currentUserId!,
        text: text,
        timestamp: DateTime.now(),
      );
      ref
          .read(chatProvider.notifier)
          .addMessage(widget.sessionId, msg, ref: ref);
    });

    // Relay-Wake-up: Partner hat eine Relay-Nachricht hinterlegt.
    _pingSub?.cancel();
    _pingSub = p2p.relayPing.listen((_) {
      if (mounted) unawaited(_fetchRelay());
    });

    try {
      await p2p.connect(myUserId: _currentUserId!, peerId: peerId);
    } catch (e) {
      debugPrint('[DatingHourChat] P2P Verbindung fehlgeschlagen: $e');
    }
  }

  Future<void> _retryHandshakeThrottled() async {
    final p2p = _p2p;
    if (p2p == null || !mounted) return;
    if (p2p.isConnected) return;
    if (!SupabaseService.isInitialized) return;
    final myId = _currentUserId;
    final peerId = _peerId;
    if (myId == null || myId.isEmpty || peerId == null || peerId.isEmpty) {
      return;
    }
    final now = DateTime.now();
    if (_lastDhHandshakeRetry != null &&
        now.difference(_lastDhHandshakeRetry!) < const Duration(seconds: 25)) {
      return;
    }
    _lastDhHandshakeRetry = now;
    try {
      await p2p.ensureConnected(myUserId: myId, peerId: peerId);
    } catch (e) {
      debugPrint('[DatingHourChat] Handshake-Retry fehlgeschlagen: $e');
    }
  }

  Future<void> _sendIceBreaker() async {
    final iceBreakers = [
      'Hey! Was war das Beste, das dir diese Woche passiert ist? 😊',
      'Wenn du morgen überall auf der Welt aufwachen könntest, wo wärst du? ✨',
      'Was ist dein liebstes "Guilty Pleasure"? 🤭',
      'Hast du ein verborgenes Talent? 🎯',
      'Was würdest du tun, wenn du für einen Tag unsichtbar wärst? 👻',
    ];
    _messageController.text =
        iceBreakers[DateTime.now().millisecondsSinceEpoch % iceBreakers.length];
    _sendMessage();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _session == null) return;

    // IDs ZUERST prüfen (Fix: _currentUserId!-Crash bei fehlender Session
    // + Ghost-Bubble mit receiverId '' bei fehlendem Peer).
    final myId = _currentUserId;
    final peerId = _peerId;
    if (myId == null || myId.isEmpty || peerId == null || peerId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'dh.chat.sendFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    _messageController.clear();

    // Lokal für die Anzeige ablegen (kein Mock-Auto-Reply) ...
    final localMsg = Message(
      id: Message.newId('local'),
      senderId: myId,
      receiverId: peerId,
      text: text,
      timestamp: DateTime.now(),
    );
    ref
        .read(chatProvider.notifier)
        .addMessage(widget.sessionId, localMsg, ref: ref);

    // ... und ECHT E2E-verschlüsselt zustellen: erst direkt per
    // P2P-DataChannel, bei geschlossenem Kanal über den Server-Relay
    // (Migration 093/106 - Dating-Hour-Sessions sind relay-berechtigt).
    // Vorher gab es NUR den P2P-Pfad: Ohne Direktverbindung lief die
    // Nachricht still in die Outbox und kam im 5-Minuten-Fenster nie an.
    final ueberP2p = await bestEffortOr(
      'p2p.trySendText',
      () async => await _p2p?.trySendText(text) == true,
      false,
    );
    // BEFUND (15.11.2026, gefunden von einem Test): `trySendText` meldet
    // Erfolg, auch wenn der Kanal NICHT steht - die Nachricht liegt dann
    // nur in der Outbox und kommt im 5-Minuten-Fenster nicht an. Der
    // Bildschirm beendete sich hier und der Nutzer bekam nie eine
    // Meldung: Seine Nachricht stand in der Liste, aber sie kam nicht
    // an.
    //
    // DER WEG: Nur ein wirklich offener Kanal zählt als "zugestellt".
    // Sonst geht der Weg über das Relay - und wenn auch der scheitert,
    // erfährt der Nutzer davon.
    if (ueberP2p && _p2p?.isConnected == true) {
      return;
    }
    try {
      await ref
          .read(relayServiceProvider)
          .storeText(peerId: peerId, text: text);
      // Dual-Delivery-Schutz: trySendText oben hat bei geschlossenem Kanal
      // bereits in die Outbox eingereiht - nach erfolgreichem Relay-Store
      // muss der Eintrag raus, sonst Doppelzustellung bei Kanalöffnung.
      _p2p?.dequeueText(text);
      unawaited(_p2p?.sendRelayPing());
      // NUTZERWUNSCH: Push, dass eine Nachricht wartet (nur Metadaten;
      // Beziehung = offene Dating-Hour-Session).
      unawaited(() async {
        await bestEffort('invoke', () async {
          // MIT ZEITLIMIT (15.11.2026): ohne Grenze blieb der
          // Aufruf stehen.
          await SupabaseService.rufeEdgeFunktion(
            'notify-user',
            body: {'kind': 'messages', 'target_user_id': peerId},
          );
        });
      }());
      return;
    } catch (e) {
      debugPrint('[DatingHourChat] Relay-Send fehlgeschlagen: $e');
      // Weder direkt noch über das Relay: der Nutzer muss erfahren,
      // dass seine Nachricht nicht rausging - sonst schreibt er ins
      // Leere und weiß es nicht.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.t(context, 'dh.chat.sendFailed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
  }
}
